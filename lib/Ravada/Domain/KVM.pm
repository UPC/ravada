package Ravada::Domain::KVM;

use warnings;
use strict;

=head2 NAME

Ravada::Domain::KVM - KVM Virtual Machines library for Ravada

=cut

use Carp qw(cluck confess croak);
use Data::Dumper;
use File::Copy;
use File::Path qw(make_path);
use Hash::Util qw(lock_keys);
use IPC::Run3 qw(run3);
use Moose;
use Sys::Virt::Stream;
use XML::LibXML;

no warnings "experimental::signatures";
use feature qw(signatures);

with 'Ravada::Domain';

has 'domain' => (
      is => 'rw'
    ,isa => 'Sys::Virt::Domain'
    ,required => 1
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

our %GET_DRIVER_SUB = (
    network => \&_get_driver_network
     ,sound => \&_get_driver_sound
     ,video => \&_get_driver_video
     ,image => \&_get_driver_image
     ,jpeg => \&_get_driver_jpeg
     ,zlib => \&_get_driver_zlib
     ,playback => \&_get_driver_playback
     ,streaming => \&_get_driver_streaming
);
our %SET_DRIVER_SUB = (
    network => \&_set_driver_network
     ,sound => \&_set_driver_sound
     ,video => \&_set_driver_video
     ,image => \&_set_driver_image
     ,jpeg => \&_set_driver_jpeg
     ,zlib => \&_set_driver_zlib
     ,playback => \&_set_driver_playback
     ,streaming => \&_set_driver_streaming
);

##################################################


=head2 name

Returns the name of the domain

=cut

sub name {
    my $self = shift;
    $self->{_name} = $self->domain->get_name if !$self->{_name};
    return $self->{_name};
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

    warn "WARNING: No disk files removed for ".$self->domain->get_name."\n"
            .Dumper([$self->list_disks])
        if !$removed && $0 !~ /\.t$/;

}

=head2 pre_remove_domain

Cleanup operations executed before removing this domain

    $self->pre_remove_domain

=cut

sub pre_remove_domain {
    my $self = shift;
    $self->domain->managed_save_remove()    if $self->domain->has_managed_save_image;
}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    my $warning = shift;

    my $name;
    ($name) = $file =~ m{.*/(.*)}   if $file =~ m{/};

    #TODO: do a remove_volume in the VM
    my @vols = $self->_vm->storage_pool->list_volumes();
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
    my $user = shift;

    if ($self->domain->is_active) {
        $self->_do_force_shutdown();
    }


    eval { $self->remove_disks(); };
    die $@ if $@ && $@ !~ /libvirt error code: 42/;
#    warn "WARNING: Problem removing disks for ".$self->name." : $@" if $@ && $0 !~ /\.t$/;

    eval { $self->_remove_file_image() };
    die $@ if $@ && $@ !~ /libvirt error code: 42/;
#    warn "WARNING: Problem removing file image for ".$self->name." : $@" if $@ && $0 !~ /\.t$/;

#    warn "WARNING: Problem removing ".$self->file_base_img." for ".$self->name
#            ." , I will try again later : $@" if $@;

    eval { $self->domain->undefine() };
    die $@ if $@ && $@ !~ /libvirt error code: 42/;
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
                #TODO: do a refresh of all the storage pools in the VM if anything removed
                $self->_vm->storage_pool->refresh();
            };
            warn $@ if $@;
        }
        next if ! -e $file;
        warn $@ if $@;
    }
}

sub _disk_device {
    my $self = shift;
    my $with_target = shift;


    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description)
        or die "ERROR: $!\n";

    my @img;
    my $list_disks = '';

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        $list_disks .= $disk->toString();

        my ($file,$target);
        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                $file = $child->getAttribute('file');
            }
            if ($child->nodeName eq 'target') {
                $target = $child->getAttribute('dev');
            }
        }
        push @img,[$file,$target]   if $with_target;
        push @img,($file)           if !$with_target;
    }
    if (!scalar @img) {
        my (@devices) = $doc->findnodes('/domain/devices/disk');
        die "I can't find disk device FROM "
            .join("\n",map { $_->toString() } @devices);
    }
    return @img;

}

sub _disk_devices_xml {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain
                                        ->get_xml_description)
        or die "ERROR: $!\n";

    my @devices;

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        my $is_disk = 0;
        for my $child ($disk->childNodes) {
            $is_disk++ if $child->nodeName eq 'source';
        }
        push @devices,($disk) if $is_disk;
    }
    return @devices;

}

=head2 disk_device

Returns the file name of the disk of the domain.

  my $file_name = $domain->disk_device();

=cut

sub disk_device {
    my $self = shift;
    return $self->_disk_device(@_);
}

sub _create_qcow_base {
    my $self = shift;

    my @base_img;

    my $base_name = $self->name;
    for  my $vol_data ( $self->list_volumes_target()) {
        my ($file_img,$target) = @$vol_data;
        my $base_img = $file_img;

        my @cmd;
        $base_img =~ s{\.\w+$}{\.ro.qcow2};

        die "ERROR: base image already exists '$base_img'" if -e $base_img;

        if ($file_img =~ /\.SWAP\.\w+$/) {
            @cmd = _cmd_copy($file_img, $base_img);
        } else {
            @cmd = _cmd_convert($file_img,$base_img);
        }

        push @base_img,([$base_img,$target]);

        my ($in, $out, $err);
        run3(\@cmd,\$in,\$out,\$err);
        warn $out  if $out;
        warn "$?: $err"   if $err;

        if ($? || ! -e $base_img) {
            chomp $err;
            chomp $out;
            die "ERROR: Output file $base_img not created at "
                ."\n"
                ."ERROR $?: '".($err or '')."'\n"
                ."  OUT: '".($out or '')."'\n"
                ."\n"
                .join(" ",@cmd);
        }

        chmod 0555,$base_img;
        unlink $file_img or die "$! $file_img";
        $self->_vm->_clone_disk($base_img, $file_img);
    }
    $self->_prepare_base_db(@base_img);
    return @base_img;

}

sub _cmd_convert {
    my ($base_img, $qcow_img) = @_;

    return    ('qemu-img','convert',
                '-O','qcow2', $base_img
                ,$qcow_img
        );

}

sub _cmd_copy {
    my ($base_img, $qcow_img) = @_;

    return ('cp'
            ,$base_img, $qcow_img
    );
}

=pod

sub _create_swap_base {
    my $self = shift;

    my @swap_img;

    my $base_name = $self->name;
    for  my $base_img ( $self->list_volumes()) {

      next unless $base_img =~ 'SWAP';

        confess "ERROR: missing $base_img"
            if !-e $base_img;
        my $swap_img = $base_img;

        $swap_img =~ s{\.\w+$}{\.ro.img};

        push @swap_img,($swap_img);

        my @cmd = ('qemu-img','convert',
                '-O','raw', $base_img
                ,$swap_img
        );

        my ($in, $out, $err);
        run3(\@cmd,\$in,\$out,\$err);
        warn $out if $out;
        warn $err if $err;

        if (! -e $swap_img) {
            warn "ERROR: Output file $swap_img not created at ".join(" ",@cmd)."\n";
            exit;
        }

        chmod 0555,$swap_img;
        $self->_prepare_base_db($swap_img);
    }
    return @swap_img;

}

=cut

=head2 prepare_base

Prepares a base virtual machine with this domain disk

=cut


sub prepare_base {
    my $self = shift;

#    my @img = $self->_create_swap_base();
    my @img = $self->_create_qcow_base();
    $self->_store_xml();
    return @img;
}

sub _store_xml {
    my $self = shift;
    my $xml = $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE);
    my $sth = $self->_dbh->prepare(
        "INSERT INTO base_xml (id_domain, xml) "
        ." VALUES ( ?,? ) "
    );
    $sth->execute($self->id , $xml);
    $sth->finish;
}

=head2 get_xml_base

Returns the XML definition for the base, only if prepare_base has been run befor

=cut

sub get_xml_base{

    my $self = shift;
    my $sth = $self->_dbh->prepare(
        "SELECT xml FROM base_xml WHERE id_domain=?"
    );
    $sth->execute($self->id);
    my $xml = $sth->fetchrow;
    return ($xml or $self->domain->get_xml_description);
}

sub _post_remove_base_domain {
    my $self = shift;
    my $sth = $self->_dbh->prepare(
        "DELETE FROM base_xml WHERE id_domain=?"
    );
    $sth->execute($self->id);
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
    $address = $self->_vm->nat_ip if $self->_vm->nat_ip;

    die "Unable to get port for domain ".$self->name." ".$graph->toString
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
    my %arg;

    if (!(scalar(@_) % 2))  {
        %arg = @_;
    }

    my $set_password=0;
    my $remote_ip = $arg{remote_ip};
    if ($remote_ip) {
        my $network = Ravada::Network->new(address => $remote_ip);
        $set_password = 1 if $network->requires_password();
    }
    $self->_set_spice_ip($set_password);
#    $self->domain($self->_vm->vm->get_domain_by_name($self->domain->get_name));
    $self->domain->create();
}

sub _pre_shutdown_domain {
    my $self = shift;
    my ($state, $reason) = $self->domain->get_state();

    if ($state == Sys::Virt::Domain::STATE_PMSUSPENDED_UNKNOWN 
         || $state == Sys::Virt::Domain::STATE_PMSUSPENDED_DISK_UNKNOWN 
         || $state == Sys::Virt::Domain::STATE_PMSUSPENDED) {
        $self->domain->pm_wakeup();
        for ( 1 .. 10 ) {
            last if $self->is_active;
            sleep 1;
        }
    }

    $self->domain->managed_save_remove()
        if $self->domain->has_managed_save_image();
}

=head2 shutdown

Stops the domain

=cut

sub shutdown {
    my $self = shift;

    my %args = @_;
    my $req = $args{req};

    if (!$self->is_active && !$args{force}) {
        $req->status("done")                if $req;
        $req->error("Domain already down")  if $req;
        return;
    }

    return $self->_do_force_shutdown() if $args{force};
    return $self->_do_shutdown();

}

sub _do_shutdown {
    my $self = shift;
    $self->domain->shutdown();

}

=head2 shutdown_now

Shuts down uncleanly the domain

=cut

sub shutdown_now {
    my $self = shift;
    return $self->_do_force_shutdown()  if $self->is_active;
}

=head2 force_shutdown

Shuts down uncleanly the domain

=cut

sub force_shutdown{
    my $self = shift;
    return $self->_do_force_shutdown() if $self->is_active;
}

sub _do_force_shutdown {
    my $self = shift;
    return if !$self->domain->is_active;

    eval { $self->domain->destroy   };
    warn $@ if $@;

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


=head2 is_hibernated

Returns if the domain has a managed saved state.

=cut

sub is_hibernated {
    my $self = shift;
    return $self->domain->has_managed_save_image;
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

=head2 can_hybernate

Returns true (1) for KVM domains

=cut

sub can_hybernate { 1 };

=head2 can_hybernate

Returns true (1) for KVM domains

=cut

sub can_hibernate { 1 };

=head2 hybernate

Take a snapshot of the domain's state and save the information to a
managed save location. The domain will be automatically restored with
this state when it is next started.

    $domain->hybernate();

=cut

sub hybernate {
    my $self = shift;
    $self->hibernate();
}

=head2 hybernate

Take a snapshot of the domain's state and save the information to a
managed save location. The domain will be automatically restored with
this state when it is next started.

    $domain->hybernate();

=cut

sub hibernate {
    my $self = shift;
    $self->domain->managed_save();
}


=head2 add_volume

Adds a new volume to the domain

    $domain->add_volume(name => $name, size => $size);
    $domain->add_volume(name => $name, size => $size, xml => 'definition.xml');

    $domain->add_volume(path => "/var/lib/libvirt/images/path.img");

=cut

sub add_volume {
    my $self = shift;
    my %args = @_;

    my %valid_arg = map { $_ => 1 } ( qw( name size vm xml swap target path));

    for my $arg_name (keys %args) {
        confess "Unknown arg $arg_name"
            if !$valid_arg{$arg_name};
    }
#    confess "Missing vm"    if !$args{vm};
    $args{vm} = $self->_vm if !$args{vm};
    confess "Missing name " if !$args{name};
    if (!$args{xml}) {
        $args{xml} = $Ravada::VM::KVM::DIR_XML."/default-volume.xml";
        $args{xml} = $Ravada::VM::KVM::DIR_XML."/swap-volume.xml"      if $args{swap};
    }

    my $path = delete $args{path};

    $path = $args{vm}->create_volume(
        name => $args{name}
        ,xml =>  $args{xml}
        ,swap => ($args{swap} or 0)
        ,size => ($args{size} or undef)
        ,target => ( $args{target} or undef)
    )   if !$path;

# TODO check if <target dev="/dev/vda" bus='virtio'/> widhout dev works it out
# change dev=vd*  , slot=*
#
    my ($target_dev) = ($args{target} or $self->_new_target_dev());
    my $pci_slot = $self->_new_pci_slot();
    my $driver_type = 'qcow2';
    my $cache = 'default';

    if ( $args{swap} ) {
        $cache = 'none';
        $driver_type = 'raw';
    }

    my $xml_device =<<EOT;
    <disk type='file' device='disk'>
      <driver name='qemu' type='$driver_type' cache='$cache'/>
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

    my $dev;

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk'
            && $disk->getAttribute('device') ne 'cdrom';


        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'target') {
#                die $child->toString();
                my $cur_dev = $child->getAttribute('dev');
                $target{$cur_dev}++;
                if (!$dev && $disk->getAttribute('device') eq 'disk') {
                    ($dev) = $cur_dev =~ /(.*).$/;
                }
            }
        }
    }
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

=head2 list_volumes

Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.

    my @volumes = $domain->list_volumes();

=cut

sub list_volumes {
    my $self = shift;
    return $self->disk_device();
}

=head2 list_volumes_target

Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.

    my @volumes = $domain->list_volumes_target();

=cut

sub list_volumes_target {
    my $self = shift;
    return $self->disk_device("target");
}

=head2 screenshot

Takes a screenshot, it stores it in file.

=cut

sub handler {
    my ($stream, $data, $n) = @_;
    my $file_tmp = "/var/tmp/$$.tmp";

    open my $out ,'>>',$file_tmp;
    print $out $data;
    close $out;

    return $n;
}

sub screenshot {
    my $self = shift;
    my $file = (shift or $self->_file_screenshot);

    my ($path) = $file =~ m{(.*)/};
    make_path($path) if ! -e $path;

    $self->domain($self->_vm->vm->get_domain_by_name($self->name));
    my $stream = $self->{_vm}->vm->new_stream();

    my $mimetype = $self->domain->screenshot($stream,0);
    $stream->recv_all(\&handler);

    my $file_tmp = "/var/tmp/$$.tmp";
    $stream->finish;

    $self->_convert_png($file_tmp,$file);
    unlink $file_tmp or warn "$! removing $file_tmp";
}

sub _file_screenshot {
    my $self = shift;
    my $doc = XML::LibXML->load_xml(string => $self->_vm->storage_pool->get_xml_description);
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

=head2 disk_size

Returns the size of the domains disk or disks
If an array is expected, it returns the list of disks sizes, if it
expects an scalar returns the first disk as it is asumed to be the main one.


    my $size = $domain->disk_size();

=cut


sub disk_size {
    my $self = shift;
    my @size;
    for my $disk ($self->_disk_devices_xml) {

        my ($source) = $disk->findnodes('source');
        next if !$source;

        my $file = $source->getAttribute('file');
        $file =~ s{.*/}{};

        my $vol;
        eval { $vol = $self->_vm->search_volume($file) };

        warn "I can't find volume in storage. source: $source , file: ".($file or '<UNDEF>')
            if !$vol;
        push @size, ($vol->get_info->{capacity})    if $vol;
    }
    return @size if wantarray;
    return ($size[0] or undef);
}

=pod

sub rename_volumes {
    my $self = shift;
    my $new_dom_name = shift;

    for my $disk ($self->_disk_devices_xml) {

        my ($source) = $disk->findnodes('source');
        next if !$source;

        my $volume = $source->getAttribute('file') or next;

        confess "ERROR: Domain ".$self->name
                ." volume '$volume' does not exists"
            if ! -e $volume;

        $self->domain->create if !$self->is_active;
        $self->domain->detach_device($disk);
        $self->domain->shutdown;

        my $cont = 0;
        my $new_volume;
        my $new_name = $new_dom_name;

        for (;;) {
            $new_volume=$volume;
            $new_volume =~ s{(.*)/.*\.(.*)}{$1/$new_name.$2};
            last if !-e $new_volume;
            $cont++;
            $new_name = "$new_dom_name.$cont";
        }
        warn "copy $volume -> $new_volume";
        copy($volume, $new_volume) or die "$! $volume -> $new_volume";
        $source->setAttribute(file => $new_volume);
        unlink $volume or warn "$! removing $volume";
        $self->storage->refresh();
        $self->domain->attach_device($disk);
    }
}

=cut

=head2 spinoff_volumes

Makes volumes indpendent from base

=cut

sub spinoff_volumes {
    my $self = shift;

    $self->_do_force_shutdown() if $self->is_active;

    for my $disk ($self->_disk_devices_xml) {

        my ($source) = $disk->findnodes('source');
        next if !$source;

        my $volume = $source->getAttribute('file') or next;

        confess "ERROR: Domain ".$self->name
                ." volume '$volume' does not exists"
            if ! -e $volume;

        #TODO check mktemp or something
        my $volume_tmp  = "$volume.$$.tmp";

        unlink($volume_tmp) or die "ERROR $! removing $volume.tmp"
            if -e $volume_tmp;

        my @cmd = ('qemu-img'
              ,'convert'
              ,'-O','qcow2'
              ,$volume
              ,$volume_tmp
        );
        my ($in, $out, $err);
        run3(\@cmd,\$in,\$out,\$err);
        warn $out  if $out;
        warn $err   if $err;
        die "ERROR: Temporary output file $volume_tmp not created at "
                .join(" ",@cmd)."\n"
            if (! -e $volume_tmp );

        copy($volume_tmp,$volume) or die "$! $volume_tmp -> $volume";
        unlink($volume_tmp) or die "ERROR $! removing $volume_tmp";
    }
}


sub _set_spice_ip {
    my $self = shift;
    my $set_password = shift;

    my $doc = XML::LibXML->load_xml(string
                            => $self->domain->get_xml_description) ;
    my @graphics = $doc->findnodes('/domain/devices/graphics');

    my $ip = $self->_vm->ip();

    for my $graphics ( $doc->findnodes('/domain/devices/graphics') ) {
        $graphics->setAttribute('listen' => $ip);

        if ( !$self->is_hibernated() ) {
            my $password;
            if ($set_password) {
                $password = Ravada::Utils::random_name(4);
                $graphics->setAttribute(passwd => $password);
            } else {
                $graphics->removeAttribute('passwd');
            }
            $self->_set_spice_password($password);
        }

        my $listen;
        for my $child ( $graphics->childNodes()) {
            $listen = $child if $child->getName() eq 'listen';
        }
        # we should consider in the future add a new listen if it ain't one
        next if !$listen;
        $listen->setAttribute('address' => $ip);
        $self->domain->update_device($graphics);
    }
}

sub _hwaddr {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my @hwaddr;
    for my $mac( $doc->findnodes("/domain/devices/interface/mac")) {
        push @hwaddr,($mac->getAttribute('address'));
    }
    return @hwaddr;
}

sub _find_base {
    my $self = shift;
    my $file = shift;
    my @cmd = ( 'qemu-img','info',$file);
    my ($in,$out, $err);
    run3(\@cmd,\$in, \$out, \$err);

    my ($base) = $out =~ m{^backing file: (.*)}mi;
    die "No base for $file in $out" if !$base;

    return $base;
}

=head2 clean_swap_volumes

Clean swap volumes. It actually just creates an empty qcow file from the base

=cut

sub clean_swap_volumes {
    my $self = shift;
    for my $file ($self->list_volumes) {
        next if $file !~ /\.SWAP\.\w+/;
        my $base = $self->_find_base($file) or next;

    	my @cmd = ('qemu-img','create'
                ,'-f','qcow2'
                ,'-b',$base
                ,$file
    	);
    	my ($in,$out, $err);
    	run3(\@cmd,\$in, \$out, \$err);
    	die $err if $err;
	}
}

=head2 get_driver

Gets the value of a driver

Argument: name

    my $driver = $domain->get_driver('video');

=cut

sub get_driver {
    my $self = shift;
    my $name = shift;

    my $sub = $GET_DRIVER_SUB{$name};

    die "I can't get driver $name for domain ".$self->name
        if !$sub;

    return $sub->($self);
}

=head2 set_driver

Sets the value of a driver

Argument: name , driver

    my $driver = $domain->set_driver('video','"type="qxl" ram="65536" vram="65536" vgamem="16384" heads="1" primary="yes"');

=cut

sub set_driver {
    my $self = shift;
    my $name = shift;

    my $sub = $SET_DRIVER_SUB{$name};

    die "I can't get driver $name for domain ".$self->name
        if !$sub;

    return $sub->($self,@_);
}

sub _get_driver_generic {
    my $self = shift;
    my $xml_path = shift;

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    for my $driver ($doc->findnodes($xml_path)) {
        my $str = $driver->toString;
        $str =~ s{^<$tag (.*)/>}{$1};
        push @ret,($str);
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

sub _get_driver_graphics {
    my $self = shift;
    my $xml_path = shift;

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    for my $tags (qw(image jpeg zlib playback streaming)){
        for my $driver ($doc->findnodes($xml_path)) {
            my $str = $driver->toString;
            $str =~ s{^<$tag (.*)/>}{$1};
            push @ret,($str);
        }
    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
    }
}

sub _get_driver_image {
    my $self = shift;

    my $image = $self->_get_driver_graphics('/domain/devices/graphics/image',@_);
#
#    if ( !defined $image ) {
#        my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);
#        Ravada::VM::KVM::xml_add_graphics_image($doc);
#    }
    return $image;
}

sub _get_driver_jpeg {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/jpeg',@_);
}

sub _get_driver_zlib {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/zlib',@_);
}

sub _get_driver_playback {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/playback',@_);
}

sub _get_driver_streaming {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/streaming',@_);
}

sub _get_driver_video {
    my $self = shift;
    return $self->_get_driver_generic('/domain/devices/video/model',@_);
}

sub _get_driver_network {
    my $self = shift;
    return $self->_get_driver_generic('/domain/devices/interface/model',@_);
}

sub _get_driver_sound {
    my $self = shift;
    my $xml_path ="/domain/devices/sound";

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    for my $driver ($doc->findnodes($xml_path)) {
        push @ret,('model="'.$driver->getAttribute('model').'"');
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;

}

sub _text_to_hash {
    my $text = shift;

    my %ret;

    for my $item (split /\s+/,$text) {
        my ($name, $value) = $item =~ m{(.*?)=(.*)};
        if (!defined $name) {
            warn "I can't find name=value in '$item'";
            next;
        }
        $value =~ s/^"(.*)"$/$1/;
        $ret{$name} = ($value or '');
    }
    return %ret;
}

sub _set_driver_generic {
    my $self = shift;
    my $xml_path= shift;
    my $value_str = shift or confess "Missing value";

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my %value = _text_to_hash($value_str);
    my $changed = 0;

    for my $video($doc->findnodes($xml_path)) {
        my $old_driver = $video->toString();
        for my $node ($video->findnodes('model')) {
            for my $attrib ( $node->attributes ) {
                my ( $name ) =$attrib =~ /\s*(.*)=/;
                next if !defined $name;
                my $new_value = ($value{$name} or '');
                if ($value{$name}) {
                    $node->setAttribute($name => $value{$name});
                } else {
                    $node->removeAttribute($name);
                }
            }
            for my $name ( keys %value ) {
                $node->setAttribute( $name => $value{$name} );
            }
        }
        $changed++ if $old_driver ne $video->toString();
    }
    return if !$changed;
    $self->_vm->connect if !$self->_vm->vm;
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);

}


sub _set_driver_generic_simple($self, $xml_path, $value_str) {
    my %value = _text_to_hash($value_str);

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my $changed = 0;
    my $found = 0;
    for my $node ( $doc->findnodes($xml_path)) {
        $found++;
        my $old_driver = $node->toString();
        for my $attrib ( $node->attributes ) {
            my ( $name ) =$attrib =~ /\s*(.*)=/;
            next if !defined $name;
            my $new_value = ($value{$name} or '');
            if ($value{$name}) {
                $node->setAttribute($name => $value{$name});
            } else {
                $node->removeAttribute($name);
            }
        }
        for my $name ( keys %value ) {
                $node->setAttribute( $name => $value{$name} );
        }
        $changed++ if $old_driver ne $node->toString();
    }
    $self->_add_driver($xml_path, \%value)       if !$found;

    return if !$changed;
    $self->_vm->connect if !$self->_vm->vm;
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);

}

sub _add_driver($self, $xml_path, $attributes=undef) {

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my @nodes = $doc->findnodes($xml_path);
    return if @nodes;

    my ($xml_parent, $new_node) = $xml_path =~ m{(.*)/(.*)};
    my @parent = $doc->findnodes($xml_parent);

    confess "Expecting one parent, I don't know what to do with ".scalar @parent
        if scalar@parent > 1;

    @parent = add_driver($self, $xml_parent)  if !@parent;

    my $node = $parent[0]->addNewChild(undef,$new_node);

    for my $name (keys %$attributes) {
        $node->setAttribute($name => $attributes->{$name});
    }
    $self->_vm->connect if !$self->_vm->vm;
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);

    return $node;
}

sub _set_driver_image {
    my $self = shift;
    my $value_str = shift or confess "Missing value";
    my $xml_path = '/domain/devices/graphics/image';

    return $self->_set_driver_generic_simple($xml_path, $value_str);
}

sub _set_driver_jpeg {
    my $self = shift;
    return $self->_set_driver_generic_simple('/domain/devices/graphics/jpeg',@_);
}

sub _set_driver_zlib {
    my $self = shift;
    return $self->_set_driver_generic_simple('/domain/devices/graphics/zlib',@_);
}

sub _set_driver_playback {
    my $self = shift;
    return $self->_set_driver_generic_simple('/domain/devices/graphics/playback',@_);
}

sub _set_driver_streaming {
    my $self = shift;
    return $self->_set_driver_generic_simple('/domain/devices/graphics/streaming',@_);
}

sub _set_driver_video {
    my $self = shift;
    return $self->_set_driver_generic('/domain/devices/video',@_);
}

sub _set_driver_network {
    my $self = shift;
    return $self->_set_driver_generic('/domain/devices/interface',@_);
}

sub _set_driver_sound {
    my $self = shift;
#    return $self->_set_driver_generic('/domain/devices/sound',@_);
    my $value_str = shift or confess "Missing value";

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my %value = _text_to_hash($value_str);
    for my $node ($doc->findnodes("/domain/devices/sound")) {
        my $old_driver = $node->toString();
        for my $attrib ( $node->attributes ) {
            my ( $name ) =$attrib =~ /\s*(.*)=/;
            next if !defined $name;
            my $new_value = ($value{$name} or '');
            if ($value{$name}) {
                $node->setAttribute($name => $value{$name});
            } else {
                $node->removeAttribute($name);
            }
        }
        for my $name ( keys %value ) {
                $node->setAttribute( $name => $value{$name} );
        }
        return if $old_driver eq $node->toString();
    }
    $self->_vm->connect if !$self->_vm->vm;
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);

}

=head2 pre_remove

Code to run before removing the domain. It can be implemented in each domain.
It is not expected to run by itself, the remove function calls it before proceeding.
In KVM it removes saved images.

    $domain->pre_remove();  # This isn't likely to be necessary
    $domain->remove();      # Automatically calls the domain pre_remove method

=cut

sub pre_remove {
    my $self = shift;
    $self->domain->managed_save_remove if $self->domain->has_managed_save_image;
}

sub is_removed($self) {
    my $is_removed = 0;
    eval { $self->domain->get_xml_description};
    return 1 if $@ && $@ =~ /libvirt error code: 42/;
    die $@ if $@;
    return 0;
}

sub internal_id($self) {
    return $self->domain->get_id();
}

1;
