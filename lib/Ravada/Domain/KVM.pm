package Ravada::Domain::KVM;

use warnings;
use strict;

use Carp qw(cluck confess croak);
use Data::Dumper;
use Hash::Util qw(lock_keys);
use IPC::Run3 qw(run3);
use Moose;
use Sys::Virt::Stream;
use XML::LibXML;

with 'Ravada::Domain';

has 'domain' => (
      is => 'rw'
    ,isa => 'Sys::Virt::Domain'
    ,required => 1
);

has 'storage' => (
    is => 'ro'
    ,isa => 'Sys::Virt::StoragePool'
    ,required => 0
);

has '_vm' => (
    is => 'ro'
    ,isa => 'Ravada::VM::KVM'
    ,required => 0
);

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $OUT;

##################################################


=head2 name

Returns the name of the domain

=cut

sub name {
    my $self = shift;
    $self->{_name} = $self->domain->get_name if !$self->{_name};
    return $self->{_name};
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

=head2 list_disks

Returns a list of the disks used by the virtual machine. CDRoms are not included

  my@ disks = $domain->list_disks();

=cut

sub list_disks {
    my $self = shift;
    my @disks = ();

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                my $file = $child->getAttribute('file');
                push @disks,($file);
            }
        }
    }
    return @disks;
}

=head2 remove_disks

Remove the volume files of the domain

=cut

sub remove_disks {
    my $self = shift;

    my $removed = 0;

    return if !$self->is_known();

    my $id;
    eval { $id = $self->id };
    return if $@ && $@ =~ /No DB info/i;
    die $@ if $@;

    $self->_vm->connect();
    for my $file ($self->list_disks) {
        if (! -e $file ) {
            warn "WARNING: $file already removed for ".$self->domain->get_name."\n"
                if $0 !~ /.t$/;
            next;
        }
        $self->_vol_remove($file);
        if ( -e $file ) {
            unlink $file or die "$! $file";
        }
        $removed++;

    }
    $self->_vm->disconnect();

    warn "WARNING: No disk files removed for ".$self->domain->get_name."\n"
        if !$removed;

}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    my $warning = shift;

    my ($name) = $file =~ m{.*/(.*)}   if $file =~ m{/};

    my @vols = $self->storage->list_volumes();
    for my $vol ( @vols ) {
        $vol->delete() if$vol->get_name eq $name;
    }
    return 1;
}

=head2 remove

Removes this domain. It removes also the disk drives and base images.

=cut

sub remove {
    my $self = shift;
    $self->domain->shutdown  if $self->domain->is_active();

    $self->_wait_down();

    $self->domain->destroy   if $self->domain->is_active();

    $self->remove_disks();
#    warn "WARNING: Problem removing disks for ".$self->name." : $@" if $@ && $0 !~ /\.t$/;

    $self->_remove_file_image();
#    warn "WARNING: Problem removing file image for ".$self->name." : $@" if $@ && $0 !~ /\.t$/;

#    warn "WARNING: Problem removing ".$self->file_base_img." for ".$self->name
#            ." , I will try again later : $@" if $@;

    $self->domain->undefine();
}


sub _remove_file_image {
    my $self = shift;
    for my $file ( $self->list_files_base ) {

        next if !$file || ! -e $file;

        chmod 0770, $file or die "$! chmodding $file";
        chown $<,$(,$file    or die "$! chowning $file";
        eval { $self->_vol_remove($file,1) };

        if ( -e $file ) {
            eval { 
                unlink $file or die "$! $file" ;
                $self->storage->refresh();
            };
            warn $@ if $@;
        }
        next if ! -e $file;
        warn $@ if $@;
    }
}

sub _disk_device {
    my $self = shift;
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description) 
        or die "ERROR: $!\n";

    my @img;
    my $list_disks = '';

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        $list_disks .= $disk->toString();

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
#                die $child->toString();
                push @img , ($child->getAttribute('file'));
            }
        }
    }
    if (!scalar @img) {
        my (@devices) = $doc->findnodes('/domain/devices/disk');
        die "I can't find disk device FROM "
            .join("\n",map { $_->toString() } @devices);
    }
    return @img;

}

=head2 disk_device

Returns the file name of the disk of the domain.

  my $file_name = $domain->disk_device();

=cut

sub disk_device {
    my $self = shift;
    return $self->_disk_device();
}

sub _create_qcow_base {
    my $self = shift;

    my @qcow_img;

    my $base_name = $self->name;
    for  my $base_img ( $self->list_volumes()) {

        my $qcow_img = $base_img;
    
        $qcow_img =~ s{\.\w+$}{\.ro.qcow2};

        push @qcow_img,($qcow_img);

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
        $self->_prepare_base_db($qcow_img);
    }
    return @qcow_img;

}

=head2 prepare_base

Prepares a base virtual machine with this domain disk

=cut


sub prepare_base {
    my $self = shift;

    return $self->_create_qcow_base();
}

=head2 display

Returns the display URI

=cut

sub display {
    my $self = shift;

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
    return ( $self->domain->is_active or 0);
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

    if (!$self->is_active && !$args{force}) {
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

=head2 shutdown_now

Shuts down uncleanly the domain

=cut

sub shutdown_now {
    my $self = shift;
    my $user = shift;
    return $self->shutdown(timeout => 1, user => $user);
}


=head2 pause

Pauses the domain

=cut

sub pause {
    my $self = shift;
    return $self->domain->suspend();
}

=head2 resume

Resumes a paused the domain

=cut

sub resume {
    my $self = shift;
    return $self->domain->resume();
}


=head2 is_paused

Returns if the domain is paused

=cut

sub is_paused {
    my $self = shift;
    my ($state, $reason) = $self->domain->get_state();

   

    return 0 if $state == 1;
    #TODO, find out which one of those id "1" and remove it from this list
    #
    return $state && 
        ($state == Sys::Virt::Domain::STATE_PAUSED_UNKNOWN 
        || $state == Sys::Virt::Domain::STATE_PAUSED_USER 
        || $state == Sys::Virt::Domain::STATE_PAUSED_DUMP
        || $state == Sys::Virt::Domain::STATE_PAUSED_FROM_SNAPSHOT
        || $state == Sys::Virt::Domain::STATE_PAUSED_IOERROR
        || $state == Sys::Virt::Domain::STATE_PAUSED_MIGRATION
        || $state == Sys::Virt::Domain::STATE_PAUSED_SAVE
        || $state == Sys::Virt::Domain::STATE_PAUSED_SHUTTING_DOWN
    );
    return 0;
}

=head2 add_volume

Adds a new volume to the domain

    $domain->add_volume($size);

=cut

sub add_volume {
    my $self = shift;
    my %args = @_;

    my %valid_arg = map { $_ => 1 } ( qw( name size path vm));

    for my $arg_name (keys %args) {
        confess "Unknown arg $arg_name"
            if !$valid_arg{$arg_name};
    }
    confess "Missing vm"    if !$args{vm};
    confess "Missing name " if !$args{name};

    my $path = $args{vm}->create_volume($args{name}, "etc/xml/trusty-volume.xml"
        ,($args{size} or undef));

# TODO check if <target dev="/dev/vda" bus='virtio'/> widhout dev works it out
# change dev=vd*  , slot=*
#
    my $target_dev = $self->_new_target_dev();
    my $pci_slot = $self->_new_pci_slot();
    
    my $xml_device =<<EOT;
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$path'/>
      <backingStore/>
      <target bus='virtio' dev='$target_dev'/>
      <alias name='virtio-disk1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='$pci_slot' function='0x0'/>
    </disk>
EOT

    eval { $self->domain->attach_device($xml_device,Sys::Virt::Domain::DEVICE_MODIFY_CONFIG) };
    die $@."\n".$self->domain->get_xml_description if$@;
}

sub _new_target_dev {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description) 
        or die "ERROR: $!\n";

    my %target;

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';


        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'target') {
#                die $child->toString();
                $target{ $child->getAttribute('dev') }++;
            }
        }
    }
    my ($dev) = keys %target;
    $dev =~ s/(.*).$/$1/;
    for ('b' .. 'z') {
        my $new = "$dev$_";
        return $new if !$target{$new};
    }
}

sub _new_pci_slot{
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description) 
        or die "ERROR: $!\n";

    my %target;

    for my $name (qw(disk controller interface graphics sound video memballoon)) {
        for my $disk ($doc->findnodes("/domain/devices/$name")) {


            for my $child ($disk->childNodes) {
                if ($child->nodeName eq 'address') {
#                    die $child->toString();
                    $target{ $child->getAttribute('slot') }++
                        if $child->getAttribute('slot');
                }
            }
        }
    }
    for ( 1 .. 99) {
        $_ = "0$_" if length $_ < 2;
        my $new = '0x'.$_;
        return $new if !$target{$new};
    }
}

=head2 BUILD

internal build method

=cut

sub BUILD {
    my $self = shift;
}

=head2 list_volumes

Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.

    my @volumes = $domain->list_volumes();

=cut

sub list_volumes {
    my $self = shift;
    return $self->disk_device();
}

=head2 screenshot

Takes a screenshot, it stores it in file.

=cut

sub screenshot {
    my $self = shift;
    my $file = (shift or $self->_file_screenshot);

    $self->domain($self->_vm->vm->get_domain_by_name($self->name));
    my $stream = $self->{_vm}->vm->new_stream();

    my $mimetype = $self->domain->screenshot($stream,0);

    my $file_tmp = "$file.tmp";
    my $data;
    my $bytes = 0;
    open my $out, '>', $file_tmp or die "$! $file_tmp";
    while ( my $rv =$stream->recv($data,1024)) {
        $bytes += $rv;
        last if $rv<=0;
        print $out $data;
    }
    close $out;

    $self->_convert_png($file_tmp,$file);
    unlink $file_tmp or warn "$! removing $file_tmp";

    $stream->finish;

    return $bytes;
}

sub _file_screenshot {
    my $self = shift;
    my $doc = XML::LibXML->load_xml(string => $self->storage->get_xml_description);
    my ($path) = $doc->findnodes('/pool/target/path/text()');
    return "$path/".$self->name.".png";
}

=head2 can_screenshot

Returns if a screenshot of this domain can be taken.

=cut

sub can_screenshot {
    my $self = shift;
    return 1 if $self->_vm();
}

=head2 storage_refresh

Refreshes the internal storage. Used after removing files such as base images.

=cut

sub storage_refresh {
    my $self = shift;
    $self->storage->refresh();
}


=head2 get_info

This is taken directly from Sys::Virt::Domain.

Returns a hash reference summarising the execution state of the
domain. The elements of the hash are as follows:

=over

=item maxMem

The maximum memory allowed for this domain, in kilobytes

=item memory

The current memory allocated to the domain in kilobytes

=item cpu_time

The amount of CPU time used by the domain

=item n_virt_cpu

The current number of virtual CPUs enabled in the domain

=item state

The execution state of the machine, which will be one of the
constants &Sys::Virt::Domain::STATE_*.

=back

=cut

sub get_info {
    my $self = shift;
    my $info = $self->domain->get_info;

    if ($self->is_active) {
        my $mem_stats = $self->domain->memory_stats();
        $info->{actual_ballon} = $mem_stats->{actual_balloon};
    }

    $info->{max_mem} = $info->{maxMem};
    $info->{memory} = $info->{memory};
    $info->{cpu_time} = $info->{cpuTime};
    $info->{n_virt_cpu} = $info->{nVirtCpu};

    lock_keys(%$info);
    return $info;
}

=head2 set_max_mem

Set the maximum memory for the domain

=cut

sub set_max_mem {
    my $self = shift;
    my $value = shift;

    confess "ERROR: Requested operation is not valid: domain is already running"
        if $self->domain->is_active();

    $self->domain->set_max_memory($value);

}

=head2 get_max_mem

Get the maximum memory for the domain

=cut

sub get_max_mem {
    return $_[0]->domain->get_max_memory();
}

=head2 set_memory

Sets the current available memory for the domain

=cut

sub set_memory {
    my $self = shift;
    my $value = shift;

    my $max_mem = $self->get_max_mem();
    confess "ERROR: invalid argument '$value': cannot set memory higher than max memory"
            ." ($max_mem)"
        if $value > $max_mem;

    confess "ERROR: Requested operation is not valid: domain is not running"
        if !$self->domain->is_active();

    $self->domain->set_memory($value,Sys::Virt::Domain::MEM_CONFIG);
#    if (!$self->is_active) {
#        $self->domain->set_memory($value,Sys::Virt::Domain::MEM_MAXIMUM);
#        return;
#    }

    $self->domain->set_memory($value,Sys::Virt::Domain::MEM_LIVE);
    $self->domain->set_memory($value,Sys::Virt::Domain::MEM_CURRENT);
#    $self->domain->set_memory($value,Sys::Virt::Domain::MEMORY_HARD_LIMIT);
#    $self->domain->set_memory($value,Sys::Virt::Domain::MEMORY_SOFT_LIMIT);
}

=head2 rename

Renames the domain

    $domain->rename("new name");

=cut

sub rename {
    my $self = shift;
    my %args = @_;
    my $new_name = $args{name};

    $self->domain->rename($new_name);
}

=head2 rename_volumes

Renames all the volumes of a domain

Argument: the new name of the volumes.

=cut

sub rename_volumes {
    my $self = shift;
    for my $volume ($self->list_volumes) {
        warn "Rename volume ".Dumper($volume);
    }
}

1;
