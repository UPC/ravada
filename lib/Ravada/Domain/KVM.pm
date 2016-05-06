package Ravada::Domain::KVM;

use warnings;
use strict;

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

has 'connector' => (
    is => 'ro'
    ,isa => 'DBIx::Connector'
    ,required => 1
);

#################################################3
#
our $TIMEOUT_SHUTDOWN = 20;

##################################################
#


=head2 name

Returns the name of the domain

=cut

sub name {
    my $self = shift;
    return $self->domain->get_name;
}

sub _wait_down {
    my $self = shift;
    my $seconds = (shift or $TIMEOUT_SHUTDOWN);
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
    my ($name) = $file =~ m{.*/(.*)}   if $file =~ m{/};

    my $vol = $self->storage->get_volume_by_name($name);
    if (!$vol) {
        warn "WARNING: I can't find volumne $name\n";
        return;
    }
    $vol->delete();
}

sub remove {
    my $self = shift;
    $self->domain->shutdown  if $self->domain->is_active();

    $self->_wait_down();
    $self->domain->destroy   if $self->domain->is_active();

    $self->remove_disks();

    $self->domain->undefine();
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

    #update domains set is_base='y' , img = $file_qcow
    $self->_prepare_base_db($file_qcow);
}
1;
