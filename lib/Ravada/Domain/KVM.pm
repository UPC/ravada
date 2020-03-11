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
use Hash::Util qw(lock_keys lock_hash);
use IPC::Run3 qw(run3);
use MIME::Base64;
use Moose;
use Sys::Virt::Stream;
use Sys::Virt::Domain;
use Sys::Virt;
use XML::LibXML;

no warnings "experimental::signatures";
use feature qw(signatures);

extends 'Ravada::Front::Domain::KVM';
with 'Ravada::Domain';

has 'domain' => (
      is => 'rw'
    ,isa => 'Sys::Virt::Domain'
    ,required => 0
);

has '_vm' => (
    is => 'rw'
    ,isa => 'Ravada::VM::KVM'
    ,required => 0
);

has readonly => (
    isa => 'Int'
    ,is => 'rw'
    ,default => 0
);

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $OUT;

our %SET_DRIVER_SUB = (
    network => \&_set_driver_network
     ,sound => \&_set_driver_sound
     ,video => \&_set_driver_video
     ,image => \&_set_driver_image
     ,jpeg => \&_set_driver_jpeg
     ,zlib => \&_set_driver_zlib
     ,playback => \&_set_driver_playback
     ,streaming => \&_set_driver_streaming
     ,disk => \&_set_driver_disk
);

our %GET_CONTROLLER_SUB = (
    usb => \&_get_controller_usb
    ,disk => \&_get_controller_disk
    ,network => \&_get_controller_network
    );
our %SET_CONTROLLER_SUB = (
    usb => \&_set_controller_usb
    ,disk => \&_set_controller_disk
    ,network => \&_set_controller_network
    );
our %REMOVE_CONTROLLER_SUB = (
    usb => \&_remove_controller_usb
    ,disk => \&_remove_controller_disk
    ,network => \&_remove_controller_network
    );

our %CHANGE_HARDWARE_SUB = (
    disk => \&_change_hardware_disk
    ,vcpus => \&_change_hardware_vcpus
    ,memory => \&_change_hardware_memory
    ,network => \&_change_hardware_network
);
##################################################

sub BUILD {
    my ($self, $arg) = @_;
    $self->readonly( $arg->{readonly} or 0);
}


=head2 name

Returns the name of the domain

=cut

sub name {
    my $self = shift;

    return $self->domain->get_name if $self->domain;

    confess "ERROR: Unknown domain name";
}

=head2 list_disks

Returns a list of the disks used by the virtual machine. CDRoms are not included

  my@ disks = $domain->list_disks();

=cut

sub list_disks {
    my $self = shift;
    my @disks = ();

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                my $file = $child->getAttribute('file');
                next if $file =~ /\.iso$/;
                push @disks,($file);
            }
        }
    }
    return @disks;
}

sub xml_description($self, $inactive=0) {
    return $self->_data_extra('xml')
        if ($self->is_removed || !$self->domain )
            && $self->is_known;

    confess "ERROR: KVM domain not available ".$self->is_known   if !$self->domain;
    my $xml;
    eval {
        my @flags;
        @flags = ( Sys::Virt::Domain::XML_INACTIVE ) if $inactive;

        $xml = $self->domain->get_xml_description(@flags);
        $self->_data_extra('xml', $xml) if $self->is_known
                                        && ( $inactive
                                                || !$self->_data_extra('xml')
                                                || !$self->is_active
                                        );
    };
    confess $@ if $@ && $@ !~ /libvirt error code: 42/;
    if ( $@ ) {
        return $self->_data_extra('xml');
    }
    return $xml;
}

sub xml_description_inactive($self) {
    return $self->xml_description(1);
}

=head2 remove_disks

Remove the volume files of the domain

=cut

sub remove_disks {
    my $self = shift;

    my $removed = 0;

    my $id;
    eval { $id = $self->id };
    return if $@ && $@ =~ /No DB info/i;
    confess $@ if $@;

    $self->_vm->connect();
    for my $file ($self->list_disks( device => 'disk')) {
        if (! -e $file ) {
            next;
        }
        $self->_vol_remove($file);
        $self->_vol_remove($file);
#        if ( -e $file ) {
#            unlink $file or die "$! $file";
#        }
        $removed++;

    }
    return if $self->is_removed;
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
    return if $self->is_removed;
    $self->xml_description();
    $self->domain->managed_save_remove()    if $self->domain->has_managed_save_image;
}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    my $warning = shift;

    confess "Error: I won't remove an iso file " if $file =~ /\.iso$/i;

    my $name;
    ($name) = $file =~ m{.*/(.*)}   if $file =~ m{/};

    my $removed = 0;
    for my $pool ( $self->_vm->vm->list_storage_pools ) {
        $pool->refresh;
        my $vol;
        eval { $vol = $pool->get_volume_by_name($name) };
        if (! $vol ) {
            warn "VOLUME $name not found in $pool \n".($@ or '')
                if $@ !~ /libvirt error code: 50,/i;
            next;
        }
        $vol->delete();
        $pool->refresh;
    }
    return 1;
}

sub remove_volume {
    return _vol_remove(@_);
}

=head2 remove

Removes this domain. It removes also the disk drives and base images.

=cut

sub remove {
    my $self = shift;
    my $user = shift;

    my @volumes;
    if (!$self->is_removed ) {
        for my $vol ( $self->list_volumes_info ) {
            push @volumes,($vol->{file})
                if exists $vol->{file}
                   && exists $vol->{device}
                   && $vol->{device} eq 'file';
        }
    }

    if (!$self->is_removed && $self->domain && $self->domain->is_active) {
        $self->_do_force_shutdown();
    }

    eval { $self->domain->undefine()    if $self->domain && !$self->is_removed };
    confess $@ if $@ && $@ !~ /libvirt error code: 42/;

    eval { $self->remove_disks() if $self->is_known };
    confess $@ if $@ && $@ !~ /libvirt error code: 42/;

    for my $file ( @volumes ) {
        eval { $self->remove_volume($file) };
        warn $@ if $@;
    }

    eval { $self->_remove_file_image() };
        warn $@ if $@;
    confess $@ if $@ && $@ !~ /libvirt error code: 42/;
#    warn "WARNING: Problem removing file image for ".$self->name." : $@" if $@ && $0 !~ /\.t$/;

#    warn "WARNING: Problem removing ".$self->file_base_img." for ".$self->name
#            ." , I will try again later : $@" if $@;

    $self->_post_remove_base_domain() if $self->is_base();

}


sub _remove_file_image {
    my $self = shift;
    for my $file ( $self->list_files_base ) {
        next if $file && $file =~ /\.iso$/i;

        next if !$file || ! -e $file;

        chmod 0770, $file or die "$! chmodding $file";
        chown $<,$(,$file    or die "$! chowning $file";
        eval { $self->_vol_remove($file,1) };
        warn $@ if $@;

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

sub _disk_device($self, $with_info=undef, $attribute=undef, $value=undef) {

    my $doc = XML::LibXML->load_xml(string
            => $self->xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    my @img;

    my $n_order = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        my ($source_node) = $disk->findnodes('source');
        my $file;
        $file = $source_node->getAttribute('file')  if $source_node;

        my ($target_node) = $disk->findnodes('target');
        my $device = $disk->getAttribute('device');
        my $target = $target_node->getAttribute('dev');
        my $bus = $target_node->getAttribute('bus');

        my ($boot_node) = $disk->findnodes('boot');
        my $info = {};
        eval { $info = $self->_volume_info($file) if $file && $device eq 'disk' };
        die $@ if $@ && $@ !~ /not found/i;
        $info->{device} = $device;
        if (!$info->{name} ) {
            if ($file) {
                ($info->{name}) = $file =~ m{.*/(.*)};
            } else {
                $info->{name} = $target."-".$info->{device};
            }
        }
        $info->{target} = $target;
        $info->{driver} = $bus;
        $info->{n_order} = $n_order++;
        $info->{boot} = $boot_node->getAttribute('order') if $boot_node;
        $info->{file} = $file if defined $file;

        next if defined $attribute
           && (!exists $info->{$attribute}
                || $info->{$attribute} ne $value);

        if (!$with_info) {
            push @img,($file) if $file;
            next;
        }
        push @img,Ravada::Volume->new(file => $file, info => $info, domain => $self);
    }
    return @img;

}

sub _volume_info($self, $file, $refresh=0) {
    confess "Error: No vm connected" if !$self->_vm->vm;

    my ($name) = $file =~ m{.*/(.*)};

    my $vol;
    for my $pool ( $self->_vm->vm->list_storage_pools ) {
        $pool->refresh() if $refresh;
        eval { $vol = $pool->get_volume_by_name($name) };
        warn $@ if $@ && $@ !~ /^libvirt error code: 50,/;
        last if $vol;
    }
    if (!$vol && !$refresh) {
        return $self->_volume_info($file, ++$refresh);
    }

    if (!$vol) {
        confess "Error: Volume $file not found ".$self->name;
        return;
    }

    my $info;
    eval { $info = $vol->get_info };
    warn "WARNING: $@" if $@ && $@ !~ /^libvirt error code: 50,/;
    $info->{file} = $file;
    $info->{name} = $name;
    $info->{driver} = delete $info->{bus} if exists $info->{bus};

    return $info;
}

sub _disk_devices_xml {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description)
        or die "ERROR: $!\n";

    my @devices;

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
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
    confess "Deprecated";
    my $self = shift;

    my @base_img;

    for  my $vol_data ( $self->list_volumes_info( device => 'disk')) {
        my $base_img = $vol_data->prepare_base();
        push @base_img,([$base_img,$vol_data->info->{target}]);

    }
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

=head2 post_prepare_base

Task to run after preparing a base virtual machine

=cut


sub post_prepare_base {
    my $self = shift;

    $self->_store_xml();
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


sub post_resume_aux($self) {
    my $time = time();
    eval {
        $self->domain->set_time($time, 0, 0);
    };
    if ($@) {
        $@='' if $@ !~ /libvirt error code: 86 /;
        die $@ if $@;
    }
}

=head2 display_info

Returns the display information as a hashref. The display URI is in the display entry

=cut

sub display_info($self, $user) {

    my $xml = XML::LibXML->load_xml(string => $self->xml_description);
    my ($graph) = $xml->findnodes('/domain/devices/graphics')
        or die "ERROR: I can't find graphic";

    my ($type) = $graph->getAttribute('type');
    my ($port) = $graph->getAttribute('port');
    my ($tls_port) = $graph->getAttribute('tlsPort');
    my ($address) = $graph->getAttribute('listen');

    warn "ERROR: Machine ".$self->name." is not active in node ".$self->_vm->name."\n"
        if !$port && !$self->is_active;

    my $display = $type."://$address:$port";

    my %display = (
                type => $type
               ,port => $port
                 ,ip => $address
            ,display => $display
          ,tls_port => $tls_port
    );
    lock_hash(%display);
    return \%display;
}

=head2 is_active

Returns whether the domain is running or not

=cut

sub is_active {
    my $self = shift;
    return 0 if $self->is_removed;
    my $is_active = 0;
    eval { $is_active = $self->domain->is_active };
    die $@ if $@ && $@ !~ /code: 42,/;
    return $is_active;
}

=head2 is_persistent

Returns wether the domain has a persistent configuration file

=cut

sub is_persistent($self) {
    return $self->domain->is_persistent;
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
    my $remote_ip = delete $arg{remote_ip};
    my $request = delete $arg{request};

    my $display_ip = $self->_listen_ip();
    if ($remote_ip) {
        $set_password = 0;
        my $network = Ravada::Network->new(address => $remote_ip);
        $set_password = 1 if $network->requires_password();
        $display_ip = $self->_listen_ip($remote_ip);
    }
    $self->_set_spice_ip($set_password, $display_ip);
    $self->status('starting');

    my $error;
    for ( ;; ) {
        eval { $self->domain->create() };
        $error = $@;
        next if $error && $error =~ /libvirt error code: 1, .* pool .* asynchronous/;
        last;
    }
    return if !$error || $error =~ /already running/i;
    if ($error =~ /libvirt error code: 38,/) {
        if (!$self->_vm->is_local) {
            warn "Disabling node ".$self->_vm->name();
            $self->_vm->enabled(0);
        }
        die $error;
    } elsif ( $error =~ /libvirt error code: 9, .*already defined with uuid/) {
        die "TODO";
    } elsif ( $error =~ /libvirt error code: 1,.*smbios/) {
        $self->_remove_smbios();
        $self->domain->create();
    } elsif ( $self->domain->has_managed_save_image ) {
        $request->status("removing saved image") if $request;
        $self->domain->managed_save_remove();
        $self->domain->create();
    } else {
        die $error;
    }
}

sub _remove_smbios($self) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));

    my ($os) = $doc->findnodes('/domain/os');
    my ($smbios) = $os->findnodes('smbios');
    $os->removeChild($smbios) if $smbios;

    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
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
    return if !$self->domain->is_active;
    eval { $self->domain->shutdown() };
    die $@ if $@ && $@ !~ /libvirt error code: 55,/;

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
    eval { $self->domain->resume() };
    die $@ if $@ && $@ !~ /libvirt error code: 55/;
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
    $self->hibernate(@_);
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

    my $bus = delete $args{driver};# or 'virtio');
    my $boot = (delete $args{boot} or undef);
    my $device = (delete $args{device} or 'disk');
    my $type = delete $args{type};
    my %valid_arg = map { $_ => 1 } ( qw( driver name size vm xml swap target file allocation));

    for my $arg_name (keys %args) {
        confess "Unknown arg $arg_name"
            if !$valid_arg{$arg_name};
    }

    $type = 'swap'  if !defined $type && $args{swap};
    $type = ''   if !defined $type || $type eq 'sys';
    confess "Error: type $type can't have swap flag" if $args{swap} && $type ne 'swap';

#    confess "Missing vm"    if !$args{vm};
    $args{vm} = $self->_vm if !$args{vm};
    my ($target_dev) = ($args{target} or $self->_new_target_dev());
    my $name = delete $args{name};
    if (!$args{xml}) {
        $args{xml} = $Ravada::VM::KVM::DIR_XML."/default-volume.xml";
        $args{xml} = $Ravada::VM::KVM::DIR_XML."/swap-volume.xml"      if $args{swap};
    }

    my $path = delete $args{file};
    ($name) = $path =~ m{.*/(.*)} if !$name && $path;

    $path = $args{vm}->create_volume(
        name => $name
        ,xml =>  $args{xml}
        ,swap => ($args{swap} or 0)
        ,size => ($args{size} or undef)
        ,type => $type
        ,allocation => ($args{allocation} or undef)
        ,target => $target_dev
    )   if !$path;
    ($name) = $path =~ m{.*/(.*)} if !$name;

# TODO check if <target dev="/dev/vda" bus='virtio'/> widhout dev works it out
# change dev=vd*  , slot=*
#
    my $driver_type = 'qcow2';
    my $cache = 'default';

    if ( $args{swap} || $device eq 'cdrom' ) {
        $cache = 'none';
        $driver_type = 'raw';
    }

    if ( !defined $bus ) {
        if  ($device eq 'cdrom') {
            $bus = 'ide';
        } else {
            $bus = 'virtio'
        }
    }
    my $xml_device = $self->_xml_new_device(
            bus => $bus
          ,file => $path
          ,type => $driver_type
         ,cache => $cache
        ,device => $device
        ,target => $target_dev
    );

    eval { $self->domain->attach_device($xml_device,Sys::Virt::Domain::DEVICE_MODIFY_CONFIG) };
    die $@ if $@;

    $self->_set_boot_order($path, $boot) if $boot;
    return $path;
}

sub _set_boot_hd($self, $value) {
    my $doc;
    if ($value ) {
        $doc = $self->_remove_boot_order() if $value;
    } else {
        $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));
    }
    my ($os) = $doc->findnodes('/domain/os');
    my ($boot) = $os->findnodes('boot');
    if (!$value) {
        $os->removeChild($boot) or die "Error removing ".$boot->toString();
    } else {
        if (!$boot) {
            $boot = $os->addNewChild(undef,'boot');
        }
        $boot->setAttribute(dev => 'hd');
    }
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
};

sub _remove_boot_order($self, $index=undef) {
    return $self->_cmd_boot_order(0,$index,0);
}

sub _set_boot_order($self, $index, $order) {
    my $doc = $self->_cmd_boot_order(1,$index, $order);

    my ($os) = $doc->findnodes('/domain/os');
    my ($boot) = $os->findnodes('boot');

    $os->removeChild($boot) if $boot;

    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
}

sub _cmd_boot_order($self, $set, $index=undef, $order=1) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));
    my $count = 0;

    # if index is not numeric is the file, search the real index
    $index = $self->_search_volume_index($index) if defined $index && $index !~ /^\d+$/;

    for my $device ($doc->findnodes('/domain/devices/disk')) {
        my ($boot) = $device->findnodes('boot');
        if ( defined $index && $count++ != $index) {
            next if !$set || !$boot;
            my $this_order = $boot->getAttribute('order');
            next if $this_order < $order;
            $boot->setAttribute( order => $this_order+1);
            next;
        }
        if (!$set) {
            next if !$boot;
            $device->removeChild($boot);
        } else {
            $boot = $device->addNewChild(undef,'boot')  if !$boot;
            $boot->setAttribute( order => $order );
        }
    }
    return $doc;
}

sub _search_volume_index($self, $file) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));
    my $index = 0;
    for my $device ($doc->findnodes('/domain/devices/disk')) {
        my ($source) = $device->findnodes('source');
        return $index if $source->getAttribute('file') eq $file;
        $index++;
    }
    confess "I can't find file $file in ".$self->name;
}

sub _xml_new_device($self , %arg) {
    my $bus = delete $arg{bus} or confess "Missing bus.";
    my $file = delete $arg{file} or confess "Missing target.";
    my $boot = delete $arg{boot};
    my $device = delete $arg{device};

    my $xml = <<EOT;
    <disk type='file' device='$device'>
      <driver name='qemu' type='$arg{type}' cache='$arg{cache}'/>
      <source file='$file'/>
      <backingStore/>
      <target bus='$bus' dev='$arg{target}'/>
      <address type=''/>
      <boot/>
    </disk>
EOT

    my $xml_device=XML::LibXML->load_xml(string => $xml);
    my ($address) = $xml_device->findnodes('/disk/address') or die "No address in ".$xml_device->toString();

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    $self->_change_xml_address($doc, $address, $bus);

    my ($boot_xml) = $xml_device->findnodes('/disk/boot');
    if ($boot) {
        $boot_xml->setAttribute( order => $boot );
    } else {
        my ($disk) = $xml_device->findnodes('/disk');
        $disk->removeChild($boot_xml) or die "I can't remove boot node from disk";
    }
    return $xml_device->toString();
}

sub _new_target_dev {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    my %target;

    my $dev='vd';

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
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
    for ('a' .. 'z') {
        my $new = "$dev$_";
        return $new if !$target{$new};
    }
}

# TODO try refactor this replacing by a call to
# return $self->_new_address_xml('slot','0x',2);
sub _new_pci_slot{
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    my %target;

    for my $name (qw(disk controller interface graphics sound video memballoon)) {
        for my $disk ($doc->findnodes("/domain/devices/$name")) {


            for my $child ($disk->childNodes) {
                if ($child->nodeName eq 'address') {
#                    die $child->toString();
                    my $hex = $child->getAttribute('slot');
                    next if !defined $hex;
                    my $dec = hex($hex);
                    $target{$dec}++;
                }
            }
        }
    }
    for my $dec ( 1 .. 99) {
        next if $target{$dec};
        return sprintf("0x%X", $dec);
    }
}

sub _new_address_xml($self, %arg) {

    my $doc = (delete $arg{xml} or XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE)));
    my $match = delete $arg{match}            or confess "Error: Missing argument match";
    my $prefix = ( delete $arg{prefix} or '');
    my $length = ( delete $arg{length} or 1);
    my $attribute = delete $arg{attribute}    or confess "Error: Missing argument attribute";

    die "Error: Unknown arguments ".Dumper(\%arg) if keys %arg;

    my %used;

    if (!ref($match)) {
        $match = {type => $match }
    }
    for my $device ($doc->findnodes('/domain/devices/*')) {
        for my $child ($device->childNodes) {
            if ($child->nodeName eq 'address') {
                my $found = 1;
                for my $field (keys %$match) {
                    $found = 0 if !defined $child->getAttribute($field)
                    || $child->getAttribute($field) ne $match->{$field}
                }
                if ( $found ) {
                    $used{ $child->getAttribute($attribute) }++
                }
            }
        }
    }
    for my $new ( 0 .. 99) {
        $new = "0$new" while length($new) < $length;
        my $new = $prefix.$new;
        return $new if !$used{$new};
    }
}

=head2 list_volumes

Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.

    my @volumes = $domain->list_volumes();

=cut

sub list_volumes {
    my $self = shift;
    return $self->disk_device(0,@_);
}

=head2 list_volumes_info

Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.

    my @volumes = $domain->list_volumes_info();

=cut

sub list_volumes_info {
    my $self = shift;
    return $self->disk_device("info",@_);
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

sub screenshot($self) {
    $self->domain($self->_vm->vm->get_domain_by_name($self->name));
    my $stream = $self->{_vm}->vm->new_stream();

    my $mimetype = $self->domain->screenshot($stream,0);
    $stream->recv_all(\&handler);

    my $file_tmp = "/var/tmp/$$.tmp";
    $stream->finish;

    my $file = "$file_tmp.png";
    my $blob_file = $self->_convert_png($file_tmp,$file);
    $self->_data(screenshot => encode_base64($blob_file));
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

    my $doc = XML::LibXML->load_xml(
        string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));

    my ($mem_node) = $doc->findnodes('/domain/currentMemory/text()');
    my $mem_xml = $mem_node->getData();
    $info->{memory} = $mem_xml if $mem_xml ne $info->{memory};

    $info->{max_mem} = $info->{maxMem};
    ($mem_node) = $doc->findnodes('/domain/memory/text()');
    $mem_xml = $mem_node->getData();
    $info->{max_mem} = $mem_xml if $mem_xml ne $info->{max_mem};

    $info->{cpu_time} = $info->{cpuTime};
    $info->{n_virt_cpu} = $info->{nrVirtCpu};
    confess Dumper($info) if !$info->{n_virt_cpu};
    $info->{ip} = $self->ip()   if $self->is_active();

    lock_keys(%$info);
    return $info;
}

sub _ip_agent($self) {
    my @ip;
    eval { @ip = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_AGENT) };
    return if $@ && $@ =~ /^libvirt error code: (74|86),/;
    warn $@ if $@;

    for my $if (@ip) {
        next if $if->{name} =~ /^lo/;
        for my $addr ( @{$if->{addrs}} ) {
            return $addr->{addr}
            if $addr->{type} == 0 && $addr->{addr} !~ /^127\./;
        }
    }
}

sub ip($self) {
    my @ip;
    eval { @ip = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_LEASE) };
    warn $@ if $@;
    return $ip[0]->{addrs}->[0]->{addr} if $ip[0];

    return $self->_ip_agent();

}

=head2 set_max_mem

Set the maximum memory for the domain

=cut

sub set_max_mem {
    my $self = shift;
    my $value = shift;

    $self->_set_max_memory_xml($value);
    if ( $self->is_active ) {
        $self->needs_restart(1);
    }

    $self->domain->set_max_memory($value) if !$self->is_active;

}

=head2 get_max_mem

Get the maximum memory for the domain

=cut

sub get_max_mem($self) {
    return $self->get_info->{max_mem};
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

    $self->_set_memory_xml($value);

    if ($self->is_active) {

        $self->domain->set_memory($value,Sys::Virt::Domain::MEM_CONFIG);

        $self->domain->set_memory($value,Sys::Virt::Domain::MEM_LIVE);
        $self->domain->set_memory($value,Sys::Virt::Domain::MEM_CURRENT);
        #    $self->domain->set_memory($value,Sys::Virt::Domain::MEMORY_HARD_LIMIT);
        #    $self->domain->set_memory($value,Sys::Virt::Domain::MEMORY_SOFT_LIMIT);
    }
}

sub _set_memory_xml($self, $value) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my ($mem) = $doc->findnodes('/domain/currentMemory/text()');
    $mem->setData($value);

    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);

}

sub _set_max_memory_xml($self, $value) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my ($mem) = $doc->findnodes('/domain/memory/text()');
    $mem->setData($value);

    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);

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
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);
    $self->_vm->_xml_add_sysinfo_entry($doc, hostname => $new_name);

    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
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

=cut

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

    for my $volume ($self->list_volumes_info ) {
        #        $volume->spinoff;
    }
}


sub _old_spinoff_volumes {
    my $self = shift;

    $self->_do_force_shutdown() if $self->is_active;

    for my $volume ($self->list_disks) {

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
                .join(" ",@cmd)
                .($out or '')
                .($err or '')
                ."\n"
            if (! -e $volume_tmp );

        copy($volume_tmp,$volume) or die "$! $volume_tmp -> $volume";
        unlink($volume_tmp) or die "ERROR $! removing $volume_tmp";
    }
}


sub _set_spice_ip($self, $set_password, $ip=undef) {

    my $doc = XML::LibXML->load_xml(string
                            => $self->domain->get_xml_description);
    my @graphics = $doc->findnodes('/domain/devices/graphics');

    for my $graphics ( $doc->findnodes('/domain/devices/graphics') ) {

        next if $self->is_hibernated() || $self->domain->is_active;

            my $password;
            if ($set_password) {
                $password = Ravada::Utils::random_name(4);
                $graphics->setAttribute(passwd => $password);
            } else {
                $graphics->removeAttribute('passwd');
            }
            $self->_set_spice_password($password);

        $graphics->setAttribute('listen' => ($ip or $self->_vm->listen_ip));
        my $listen;
        for my $child ( $graphics->childNodes()) {
            $listen = $child if $child->getName() eq 'listen';
        }
        # we should consider in the future add a new listen if it ain't one
        next if !$listen;
        $listen->setAttribute('address' => ($ip or $self->_vm->listen_ip));
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

=pod

sub _find_base {
    my $self = shift;
    my $file = shift;

    my @cmd = ( 'qemu-img','info',$file);
    my ($in,$out, $err);
    run3(\@cmd,\$in, \$out, \$err);

    my ($base) = $out =~ m{^backing file: (.*)}mi;
    warn "No base for $file in $out" if !$base;

    return $base;
}

=head2 clean_swap_volumes

Clean swap volumes. It actually just creates an empty qcow file from the base

sub clean_swap_volumes {
    my $self = shift;
    return if !$self->is_local;
    for my $file ($self->list_volumes) {
        next if !$file || $file !~ /\.SWAP\.\w+/;
        next if ! -e $file;
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

=cut

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

    my $ret = $sub->($self,@_);
    $self->xml_description_inactive();
    return $ret;
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

sub _set_driver_disk($self, $value) {
    return $self->change_hardware('disk',0,{driver => $value });
}

sub set_controller($self, $name, $number=undef, $data=undef) {
    my $sub = $SET_CONTROLLER_SUB{$name};
    die "I can't get controller $name for domain ".$self->name
        if !$sub;

    my $ret = $sub->($self,$number, $data);
    $self->xml_description_inactive();
    return $ret;
}
#The only '$tipo' suported right now is 'spicevmc'
sub _set_controller_usb($self,$numero, $data={}) {

    my $tipo = 'spicevmc';
    $tipo = (delete $data->{type} or 'spicevmc');

    confess "Error: unkonwn fields in data ".Dumper($data) if keys %$data;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    my ($devices) = $doc->findnodes('/domain/devices');

    my $count = 0;
    for my $controller ($devices->findnodes('redirdev')) {
        $count=$count+1;
        if (defined $numero && $numero < $count) {
            $devices->removeChild($controller);
        }
    }
    $numero = $count+1 if !defined $numero;
    if ( $numero > $count ) {
        my $missing = $numero-$count-1;
        
        for my $i (0..$missing) {
            my $controller = $devices->addNewChild(undef,"redirdev");
            $controller->setAttribute(bus => 'usb');
            $controller->setAttribute(type => $tipo );
        } 
    }
    $self->_vm->connect if !$self->_vm->vm;
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
}

sub _set_controller_disk($self, $number, $data) {
    $self->add_volume(%$data);
}

sub _set_controller_network($self, $number, $data) {

    my $driver = (delete $data->{driver} or 'virtio');

    confess "Error: unkonwn fields in data ".Dumper($data) if keys %$data;

    my $pci_slot = $self->_new_pci_slot();

    my $device = "<interface type='network'>
        <mac address='52:54:00:a7:49:71'/>
        <source network='default'/>
        <model type='$driver'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='$pci_slot' function='0x0'/>
      </interface>";

      $self->domain->attach_device($device, Sys::Virt::Domain::DEVICE_MODIFY_CONFIG);
}

sub remove_controller($self, $name, $index=0) {
    my $sub = $REMOVE_CONTROLLER_SUB{$name};
    
    die "I can't get controller $name for domain ".$self->name
        ." ".$self->type
        ."\n".Dumper(\%REMOVE_CONTROLLER_SUB)
        if !$sub;

    my $ret = $sub->($self, $index);
    $self->xml_description_inactive();
    return $ret;
}

sub _remove_device($self, $index, $device, $attribute_name=undef, $attribute_value=undef) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    my ($devices) = $doc->findnodes('/domain/devices');
    my $ind=0;
    for my $controller ($devices->findnodes($device)) {
        next if defined $attribute_name
            && $controller->getAttribute($attribute_name) !~ $attribute_value;

        if( $ind++==$index ){
            $devices->removeChild($controller);
            $self->_vm->connect if !$self->_vm->vm;
            my $new_domain = $self->_vm->vm->define_domain($doc->toString);
            $self->domain($new_domain);
            return;
        }
    }

    my $msg = "";
    $msg = " $attribute_name=$attribute_value " if defined $attribute_name;
    confess "ERROR: $device $msg $index"
        ." not removed, only ".($ind)." found in ".$self->name."\n";
}

sub _remove_controller_usb($self, $index) {
    $self->_remove_device($index,'redirdev', bus => 'usb');
}

sub _remove_controller_disk($self, $index) {
    my @volumes = $self->list_volumes_info();
    confess "Error: domain ".$self->name
        ." trying to remove $index"
        ." has only ".scalar(@volumes)
        if $index >= scalar(@volumes);

    confess "Error: undefined volume $index ".Dumper(\@volumes)
        if !defined $volumes[$index];

    $self->_remove_device($index,'disk');

    my $file = $volumes[$index]->{file};
    $self->remove_volume( $file ) if $file && $file !~ /\.iso$/;
    $self->info(Ravada::Utils::user_daemon);
}

sub _remove_controller_network($self, $index) {
    $self->_remove_device($index,'interface', type => qr'(bridge|network)');
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
    return if $self->is_removed;
    $self->domain->managed_save_remove
        if $self->domain && $self->domain->has_managed_save_image;
}

sub _check_uuid($self, $doc, $node) {

    my ($uuid) = $doc->findnodes('/domain/uuid/text()');

    my @other_uuids;
    for my $domain ($node->vm->list_all_domains, $self->_vm->vm->list_all_domains) {
        push @other_uuids,($domain->get_uuid_string);
    }
    return if !(grep /^$uuid$/,@other_uuids);

    my $new_uuid = $self->_vm->_unique_uuid($uuid
            ,@other_uuids
    );
    $uuid->setData($new_uuid);

}

sub _check_machine($self,$doc) {
    my ($os_type) = $doc->findnodes('/domain/os/type');
    $os_type->setAttribute( machine => 'pc');
}

sub migrate($self, $node, $request=undef) {
    my $dom;
    eval { $dom = $node->vm->get_domain_by_name($self->name) };
    die $@ if $@ && $@ !~ /libvirt error code: 42/;

    if ($dom) {
        #dom already in remote node
        $self->domain($dom);
    } else {
        $self->_set_spice_ip(1, $node->ip);
        my $xml = $self->domain->get_xml_description();

        my $doc = XML::LibXML->load_xml(string => $xml);
        $self->_check_machine($doc);
        for ( ;; ) {
            $self->_check_uuid($doc, $node);
            eval { $dom = $node->vm->define_domain($doc->toString()) };
            my $error = $@;
            last if !$error;
            die $error if $error !~ /libvirt error code: 9, .*already defined with uuid/;
            my $msg = "migrating ".$self->name." ".$error;
            $request->error($msg) if $request;
            sleep 1;
        }
        $self->domain($dom);
    }
    $self->_set_spice_ip(1, $node->ip);

    $self->rsync(node => $node, request => $request);

    return if $self->is_removed;
    $self->domain->managed_save_remove
        if $self->domain && $self->domain->has_managed_save_image;
}

sub is_removed($self) {
    my $is_removed = 0;

    return if !$self->_vm->is_active;

    eval {
        $is_removed = 1 if !$self->domain;
        $self->domain->get_xml_description if !$is_removed;
    };
    if( $@ && $@ =~ /libvirt error code: 42,/ ) {
        $@ = '';
        $is_removed = 1;
    }
    die $@ if $@;
    return $is_removed;
}

sub internal_id($self) {
    confess "ERROR: Missing internal domain"    if !$self->domain;
    return $self->domain->get_id();
}

sub autostart($self, $value=undef, $user=undef) {
    $self->domain->set_autostart($value) if defined $value;
    return $self->domain->get_autostart();
}

sub change_hardware($self, $hardware, @args) {
    my $sub =$CHANGE_HARDWARE_SUB{$hardware}
        or confess "Error: I don't know how to change hardware '$hardware'";
    return $sub->($self, @args);
}

sub _change_hardware_disk($self, $index, $data) {
    my @volumes = $self->list_volumes_info();
    confess "Error: Unknown volume $index, only ".(scalar(@volumes)-1)." found"
        .Dumper(\@volumes)
        if $index>=scalar(@volumes);

    my $driver = delete $data->{driver};
    my $boot = delete $data->{boot};

    $self->_change_hardware_disk_bus($index, $driver)   if $driver;
    $self->_set_boot_order($index, $boot)               if $boot;

    my $capacity = delete $data->{'capacity'};
    $self->_change_hardware_disk_capacity($index, $capacity) if $capacity;

    my $file_new = delete $data->{'file'};
    $self->_change_hardware_disk_file($index, $file_new)    if defined $file_new;

    die "Error: I don't know how to change ".Dumper($data) if keys %$data;

}

sub _change_hardware_disk_capacity($self, $index, $capacity) {
    my @volumes = $self->list_volumes_info();
    my $vol_orig = $volumes[$index];
    my $file = $vol_orig->file;

    my $volume = $self->_vm->search_volume($file);
    if (!$volume ) {
            $self->_vm->refresh_storage_pools();
            $volume = $self->_vm->search_volume($file);
    }
    die "Error: Volume file $file not found in ".$self->_vm->name    if !$volume;

    my ($name) = $file =~ m{.*/(.*)};
    my $new_capacity = Ravada::Utils::size_to_number($capacity);
    #    my $old_capacity = $volume->get_info->{'capacity'};
    #    if ( $old_capacity ) {
    #    $vol_orig->set_info( capacity => $old_capacity);
    #    $self->cache_volume_info($vol_orig);
    #}
    $volume->resize($new_capacity);
}

sub _change_hardware_disk_file($self, $index, $file) {

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
        my $disk = $self->_search_device_xml($doc,'disk',$index);

    if (defined $file && length $file) {
        my ($source) = $disk->findnodes('source');
        $source = $disk->addNewChild(undef,'source') if !$source;
        $source->setAttribute(file => $file);
    } else {
        my ($source) = $disk->findnodes('source');
        $disk->removeChild($source);
    }

    $self->_post_change_hardware($doc);
}

sub _search_device_xml($self, $doc, $device, $index) {
    my $count = 0;
    for my $disk ($doc->findnodes("/domain/devices/$device")) {
        return $disk if $count++ == $index;
    }
    confess "Error: $device $index not found in ".$self->name;
}

sub _change_hardware_disk_bus($self, $index, $bus) {
    my $count = 0;
    my $changed = 0;
    $bus = lc($bus);

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $count++ != $index;

        my ($target) = $disk->findnodes('target') or die "No target";
        my ($address) = $disk->findnodes('address') or die "No address";
        $changed++;
        return if $target->getAttribute('bus') eq $bus;
        $target->setAttribute(bus => $bus);
        $self->_change_xml_address($doc, $address, $bus);

    }
    confess "Error: disk $index not found in ".$self->name if !$changed;

    $self->_post_change_hardware($doc);
}


sub _change_hardware_vcpus($self, $index, $data) {
    confess "Error: I don't understand vcpus index = '$index' , only 0"
    if defined $index && $index != 0;
    my $n_virt_cpu = delete $data->{n_virt_cpu};
    confess "Error: Unkown args ".Dumper($data) if keys %$data;

    if ($self->domain->is_active) {
        $self->domain->set_vcpus($n_virt_cpu, Sys::Virt::Domain::VCPU_GUEST);
    }

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my ($vcpus) = ($doc->findnodes('/domain/vcpu/text()'));
    $vcpus->setData($n_virt_cpu);
    $self->_post_change_hardware($doc);

}

sub _change_hardware_memory($self, $index, $data) {
    confess "Error: I don't understand memory index = '$index' , only 0"
    if defined $index && $index != 0;

    my $memory = delete $data->{memory};
    my $max_mem= delete $data->{max_mem};
    confess "Error: Unkown args ".Dumper($data) if keys %$data;

    $self->set_memory($memory)      if defined $memory;
    $self->set_max_mem($max_mem)    if defined $max_mem;

}

sub _change_hardware_network($self, $index, $data) {
    confess if !defined $index;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

       my $type = delete $data->{type};
     my $driver = lc(delete $data->{driver} or '');
     my $bridge = delete $data->{bridge};
    my $network = delete $data->{network};

    die "Error: Unknown arguments ".Dumper($data) if keys %$data;

    $type = lc($type) if defined $type;

    die "Error: Unknown type '$type' . Known: bridge, NAT"
        if $type && $type !~ /^(bridge|nat)$/;

    die "Error: Bridged type requires bridge ".Dumper($data)
        if $type && $type eq 'bridge' && !$bridge;

    die "Error: NAT type requires network ".Dumper($data)
        if $type && $type eq 'nat' && !$network;

    $type = 'network' if $type && $type eq 'nat';

    my $count = 0;
    my $changed = 0;

    for my $interface ($doc->findnodes('/domain/devices/interface')) {
        next if $interface->getAttribute('type') !~ /^(bridge|network)/;
        next if $count++ != $index;

        my ($model_xml) = $interface->findnodes('model') or die "No model";
        my ($source_xml) = $interface->findnodes('source') or die "No source";

        $source_xml->removeAttribute('bridge')          if $network;
        $source_xml->removeAttribute('network')         if $bridge;

        $interface->setAttribute(type => $type)         if $type;
        $model_xml->setAttribute(type => $driver)       if $driver;
        $source_xml->setAttribute(bridge => $bridge)    if $bridge;
        $source_xml->setAttribute(network=> $network)   if $network;

        $changed++;
    }

    die "Error: interface $index not found in ".$self->name if !$changed;

    $self->_post_change_hardware($doc);
}



sub _post_change_hardware($self, $doc) {
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
    $self->info(Ravada::Utils::user_daemon);
}

sub _change_xml_address($self, $doc, $address, $bus) {
    my $type_def = $address->getAttribute('type');
    return $self->_change_xml_address_ide($doc, $address, 1, 1)   if $bus eq 'ide';
    return $self->_change_xml_address_ide($doc, $address, 0, 5)   if $bus eq 'sata';
    return $self->_change_xml_address_ide($doc, $address, 0, 8)  if $bus eq 'scsi';
    return $self->_change_xml_address_virtio($address)      if $bus eq 'virtio';
    return $self->_change_xml_address_usb($address)         if $bus eq 'usb';

    confess "I don't know how to change XML address for bus=$bus";
}

sub _change_xml_address_usb($self, $address) {
    for ($address->attributes) {
        $address->removeAttribute($_);
    }
    my %attribute = (
        type => 'usb'
        ,bus => 0
    );
    for (keys %attribute) {
        $address->setAttribute($_ => $attribute{$_});
    }
    $address->setAttribute(unit => $self->_new_address_xml(
            match => 'usb'
       ,attribute => 'port'
        )
    );

}

sub _change_xml_address_ide($self, $doc, $address, $max_bus=2, $max_unit=9) {
    return if $address->getAttribute('type') eq 'drive'
        && $address->getAttribute('bus') =~ /^\d+$/
        && $address->getAttribute('bus') <= $max_bus
        && $address->getAttribute('unit') <= $max_unit;

    for my $attrib ($address->attributes) {
        $address->removeAttribute($attrib->getName);
    }

    my %attribute = (
        type => 'drive'
        ,controller => 0
        ,target => 0
    );
    my %match = ( type => 'drive' );
    for my $bus ( 0 .. $max_bus ) {
        $match{bus} = $bus;
        my $unit = $self->_new_address_xml(
                   xml => $doc
            ,    match => \%match
            ,attribute =>  'unit'
        );
        if ($unit <= $max_unit) {
            $attribute{unit} = $unit;
            $attribute{bus} = $bus;
            last;
        }
    }
    die "Error: No room for more drives for type='drive', max_bus=$max_bus, max_unit=$max_unit"
        if !exists $attribute{bus} || !exists $attribute{unit};
    for (keys %attribute) {
        $address->setAttribute($_ => $attribute{$_});
    }
}

sub _change_xml_address_virtio($self, $address) {
    return if $address->getAttribute('type') eq 'pci';
    for ($address->attributes) {
        $address->removeAttribute($_->getName);
    }
    my %attribute = (
        type => 'pci'
        ,domain => '0x0000'
        ,bus => '0x00'
        ,function => '0x0'
    );
    for (keys %attribute) {
        $address->setAttribute($_ => $attribute{$_});
    }
    $address->setAttribute(slot => $self->_new_pci_slot);
}

sub dettach($self, $user) {
    $self->id_base(undef);
    $self->start($user) if !$self->is_active;
    for my $vol ($self->list_disks ) {
        $self->domain->block_pull($vol,0);
    }
}

1;
