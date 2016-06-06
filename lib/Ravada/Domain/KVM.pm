package Ravada::Domain::KVM;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

with 'Ravada::Domain';

has 'domain' => (
      is => 'ro'
    ,isa => 'Sys::Virt::Domain'
    ,required => 1
);

has 'storage' => (
    is => 'ro'
    ,isa => 'Sys::Virt::StoragePool'
    ,required => 1
);

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################


=head2 name

Returns the name of the domain

=cut

sub name {
    my $self = shift;
    return $self->domain->get_name;
}

sub _wait_down {
    my $self = shift;
    my $seconds = (shift or $self->timeout_shutdown);
    for my $sec ( 0 .. $seconds) {
        return if !$self->domain->is_active;
        print "Waiting for ".$self->domain->get_name." to shutdown." if !$sec;
        print ".";
        sleep 1;
    }
    print "\n";

}

sub remove_disks {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my $removed = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                my $file = $child->getAttribute('file');
                if (! -e $file ) {
                    warn "WARNING: $file already removed for ".$self->domain->get_name."\n";
                    next;
                }
                $self->vol_remove($file);
                if ( -e $file ) {
                    unlink $file or die "$! $file";
                }
                $removed++;
            }
        }
    }
    warn "WARNING: No disk files removed for ".$self->domain->get_name."\n"
        if !$removed;

}

sub vol_remove {
    my $self = shift;
    my $file = shift;
    my $warning = shift;

    my ($name) = $file =~ m{.*/(.*)}   if $file =~ m{/};

    my $vol;
    eval { $vol = $self->storage->get_volume_by_name($name) };
    if (!$vol) {
#        cluck "WARNING: I can't find volume $name" if !$warning;
        return;
    }
    $vol->delete();
    return 1;
}

sub remove {
    my $self = shift;
    $self->domain->shutdown  if $self->domain->is_active();

    $self->_wait_down();

    $self->vol_remove($self->file_base_img,1) if $self->file_base_img();
    $self->domain->destroy   if $self->domain->is_active();

    $self->remove_disks();
    $self->remove_file_image();

    $self->domain->undefine();

    $self->_remove_domain_db();
}


sub remove_file_image {
    my $self = shift;
    my $file = $self->file_base_img;

    return if !$file;

    $self->vol_remove($file,1);
    unlink $file or die "$! $file" if -e $file;
}

sub _disk_device {
    my $self = shift;
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description) 
        or die "ERROR: $!\n";

    my $cont = 0;
    my $img;
    my $list_disks = '';

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        $list_disks .= $disk->toString();

        die "ERROR: base disks only can have one device\n" 
                .$list_disks
            if $cont++>1;

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
#                die $child->toString();
                $img = $child->getAttribute('file');
                $cont++;
            }
        }
    }
    return $img;

}

sub _create_qcow_base {
    my $self = shift;

    my $base_name = $self->name;
    my $base_img = $self->_disk_device();

    my $qcow_img = $base_img;
    
    $qcow_img =~ s{\.\w+$}{\.ro.qcow2};
    my @cmd = ('qemu-img','convert',
                '-O','qcow2', $base_img
                ,$qcow_img
    );

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;

    if (! -e $qcow_img) {
        warn "ERROR: Output file $qcow_img not created at ".join(" ",@cmd)."\n";
        exit;
    }

    chmod 0555,$qcow_img;
    return $qcow_img;

}

sub prepare_base {
    my $self = shift;
    my $file_qcow  = $self->_create_qcow_base();

    $self->_prepare_base_db($file_qcow);
}

=head2 display

Returns the display URI

=cut
sub display {
    my $self = shift;

    $self->start if !$self->is_active;

    my $xml = XML::LibXML->load_xml(string => $self->domain->get_xml_description);
    my ($graph) = $xml->findnodes('/domain/devices/graphics') 
        or die "ERROR: I can't find graphic";

    my ($type) = $graph->getAttribute('type');
    my ($port) = $graph->getAttribute('port');
    my ($address) = $graph->getAttribute('listen');

    die "Unable to get port for domain ".$self->name
        if !$port;

    return "$type://$address:$port";
}

=head2 is_active

Returns whether the domain is running or not

=cut

sub is_active {
    my $self = shift;
    return $self->domain->is_active;
}

=head2 start

Starts the domain

=cut

sub start {
    my $self = shift;
    $self->domain->create();
}

=head2 shutdown

Stops the domain

=cut

sub shutdown {
    my $self = shift;

    my %args = @_;
    my $req = $args{req};
    my $timeout = ($args{timeout} or $TIMEOUT_SHUTDOWN);

    if (!$self->is_active) {
        $req->status("done")                if $req;
        $req->error("Domain already down")  if $req;
        return;
    }
    $self->domain->shutdown();
    $req->status("Shutting down") if $req;

    for (0 .. $timeout) {
        my $msg = "Domain ".$self->name." shutting down ($_ / $timeout)\n";
        $req->error($msg)  if $req;

        last if !$self->is_active;
        sleep 1;
    }
    if ($self->is_active) {
        my $msg = "Domaing wouldn't shut down, destroying\n";
        $req->error($msg)  if $req;
        $self->domain->destroy();
    }
    $req->status("done")        if $req;
}


=head2 pause

Pauses the domain

=cut

sub pause {
}

#sub BUILD {
#    warn "Builder KVM.pm";
#}

1;
