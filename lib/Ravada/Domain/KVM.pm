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
our $TIMEOUT_REBOOT = 60;
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
     ,cpu => \&_set_driver_cpu
     ,'usb controller'=> \&_set_driver_usb_controller

);

our %GET_HW_SUB = (
    usb => \&_get_hw_usb
    ,filesystem => \&_get_controller_filesystem
    ,disk => \&_get_controller_disk
    ,network => \&_get_controller_network
    ,video => \&_get_controller_video
    ,sound => \&_get_controller_sound
    ,'usb controller' => \&_get_hw_usb_controller
    );
our %SET_CONTROLLER_SUB = (
    usb => \&_set_hw_usb
    ,filesystem => \&_set_controller_filesystem
    ,disk => \&_set_controller_disk
    ,display => \&_set_controller_display
    ,network => \&_set_controller_network
    ,video => \&_set_controller_video
    ,sound => \&_set_controller_sound
    ,'usb controller' => \&_set_hw_usb_controller
    );
our %REMOVE_CONTROLLER_SUB = (
    usb => \&_remove_controller_usb
    ,disk => \&_remove_controller_disk
    ,filesystem => \&_remove_controller_filesystem
    ,display => \&_remove_controller_display
    ,network => \&_remove_controller_network
    ,video => \&_remove_controller_video
    ,sound => \&_remove_controller_sound
    ,'usb controller' => \&_remove_hw_usb_controller
    );

our %CHANGE_HARDWARE_SUB = (
    disk => \&_change_hardware_disk
    ,cpu => \&_change_hardware_cpu
    ,display => \&_change_hardware_display
    ,filesystem => \&_change_hardware_filesystem
    ,features => \&_change_hardware_features
    ,vcpus => \&_change_hardware_vcpus
    ,memory => \&_change_hardware_memory
    ,network => \&_change_hardware_network
    ,video => \&_change_hardware_video
    ,sound => \&_change_hardware_sound
    ,'usb controller' => \&_change_hardware_usb_controller
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

    return @disks if !$self->xml_description;
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
        if (! $self->_vm->file_exists($file) ) {
            next;
        }
        eval {
        $self->_vol_remove($file);
        $self->_vol_remove($file);
        };
        warn "Error: removing $file $@" if $@;
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
    $self->xml_description() if $self->is_known();
    $self->domain->managed_save_remove()    if $self->domain->has_managed_save_image;
}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    my $warning = shift;

    confess "Error: I won't remove an iso file " if $file && $file =~ /\.iso$/i;

    my $name;
    ($name) = $file =~ m{.*/(.*)}   if $file =~ m{/};

    my $removed = 0;
    for my $pool ( $self->_vm->vm->list_storage_pools ) {
        _pool_refresh($pool);
        my $vol;
        eval { $vol = $pool->get_volume_by_name($name) };
        if (! $vol ) {
            warn "VOLUME $name not found in $pool \n".($@ or '')
                if $@ !~ /libvirt error code: 50,/i;
            next;
        }
        for ( 1 .. 3 ) {
            eval { $vol->delete() };
            last if !$@;
            sleep 1;
        }
        die $@ if $@;
        eval { $pool->refresh };
        warn $@ if $@;
    }
    return 1;
}

sub remove_volume {
    my ($file) = $_[1];
    return if !defined $file || $file =~ /\.iso$/;
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
       my @vols_info;
       for ( 1 .. 10 ) {
           eval { @vols_info = $self->list_volumes_info };
           last if !$@;
           warn "WARNING: remove, volumes info: $@";
           sleep 1;
       }
       for my $vol ( @vols_info ) {
            push @volumes,($vol->{file})
                if exists $vol->{file}
                   && exists $vol->{device}
                   && $vol->{device} eq 'file';
        }
    }

    if (!$self->is_removed && $self->domain && $self->domain->is_active) {
        eval { $self->_do_force_shutdown() };
        warn $@ if $@;
    }

    eval { $self->domain->undefine(Sys::Virt::Domain::UNDEFINE_NVRAM)    if $self->domain && !$self->is_removed };
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

    # do a post remove but pass the remove flag = 1 ( it is 0 by default )
    $self->_post_remove_base_domain(1) if $self->is_base();

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
        my ($driver_node) = $disk->findnodes('driver');
        my ($backing_node) = $disk->findnodes('backingStore');
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
        # we use driver to make it compatible with other hardware but it is more accurate
        # to say bus
        $info->{driver} = $bus;
        $info->{bus} = $bus;
        $info->{n_order} = $n_order++;
        $info->{boot} = $boot_node->getAttribute('order') if $boot_node;
        $info->{file} = $file if defined $file;
        if ($driver_node) {
            for my $attr  ($driver_node->attributes()) {
                $info->{"driver_".$attr->name} = $attr->getValue();
            }
        }
        $info->{backing} = $backing_node->toString()
        if $backing_node && $backing_node->attributes();

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

sub _pool_refresh($pool) {
    for ( ;; ) {
        eval { $pool->refresh };
        return if !$@;
        warn "WARNING: on vol remove , pool refresh $@" if $@;
        sleep 1;
    }
}

sub _volume_info($self, $file, $refresh=0) {
    confess "Error: No vm connected" if !$self->_vm->vm;

    my ($name) = $file =~ m{.*/(.*)};

    my $vol;
    for my $pool ( $self->_vm->vm->list_storage_pools ) {
        _pool_refresh($pool) if $refresh;
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


=head2 pre_prepare_base

Run this before preparing the base. It is necessary to correctly
detect disks drivers for newer libvirts.

This is executed automatically so it shouldn't been called.

=cut

sub pre_prepare_base($self) {
    $self->_detect_disks_driver();
}

=head2 post_prepare_base

Task to run after preparing a base virtual machine

=cut


sub post_prepare_base {
    my $self = shift;

    $self->_set_volumes_backing_store();
    $self->_store_xml();
}

sub _set_backing_store($self, $disk, $backing_file) {
    my ($backing_store) = $disk->findnodes('backingStore');
    if ($backing_file) {
        my $vol_backing_file = Ravada::Volume->new(
            file => $backing_file
            ,vm => $self->_vm
        );
        my $backing_file_format = (
            $vol_backing_file->_qemu_info('file format')
                or 'qcow2'
        );

        $backing_store = $disk->addNewChild(undef,'backingStore') if !$backing_store;
        $backing_store->setAttribute('type' => 'file');

        my ($format) = $backing_store->findnodes('format');
        $format = $backing_store->addNewChild(undef,'format') if !$format;
        $format->setAttribute('type' => $backing_file_format);

        my ($source_bf) = $backing_store->findnodes('source');
        $source_bf = $backing_store->addNewChild(undef,'source') if !$source_bf;
        $source_bf->setAttribute('file' => $backing_file);

        my $next_backing_file = $vol_backing_file->backing_file();
        $self->_set_backing_store($backing_store, $next_backing_file);
    } else {
        $disk->removeChild($backing_store) if $backing_store;
        $backing_store = $disk->addNewChild(undef,'backingStore') if !$backing_store;
    }

}

sub _set_volumes_backing_store($self) {
    my $doc = XML::LibXML->load_xml(string
            => $self->xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    my @volumes_info = grep { defined($_) && $_->file } $self->list_volumes_info;
    my %vol = map { $_->file => $_ } @volumes_info;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';
        for my $source( $disk->findnodes('source')) {
            my $file = $source->getAttribute('file');
            my $backing_file = $vol{$file}->backing_file();

            $self->_set_backing_store($disk, $backing_file);

        }
    }
    $self->reload_config($doc);
}


sub _store_xml($self) {
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

sub _post_remove_base_domain($self, $remove=0) {
    my $sth = $self->_dbh->prepare(
        "DELETE FROM base_xml WHERE id_domain=?"
    );
    $sth->execute($self->id);

    if (!$remove) {
        $self->_set_volumes_backing_store();
        $self->_detect_disks_driver();
    }
}

sub _detect_disks_driver($self) {
    my $doc = XML::LibXML->load_xml(string
        => $self->xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    my @img;

    my @vols = $self->list_volumes_info();

    my $n_order = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';
        my ( $driver ) = $disk->findnodes('driver');
        my ( $source ) = $disk->findnodes('source');

        my $file = $source->getAttribute('file');
        next if $file =~ /iso$/;
        next unless $self->_vm->file_exists($file);

        my ($vol) = grep { defined $_->file && $_->file eq $file } @vols;
        my $format = $vol->_qemu_info('file format');
        confess "Error: wrong format ".Dumper($format)." for file $file"
        unless !$format || $format =~ /^\w+$/;

        $driver->setAttribute(type => $format) if defined $format;
    }

    $self->reload_config($doc);
}

sub post_resume_aux($self, %args) {
    my $set_time = delete $args{set_time};
    $set_time = 1 if !defined $set_time;
    eval {
        $self->set_time() if $set_time;
    };
    # 55: domain is not running
    # 74: not configured
    # 86: no agent
    die "$@\n" if $@ && $@ !~ /libvirt error code: (55|74|86),/;
}

sub set_time($self) {
    my $time = time();
    $self->domain->set_time($time, 0, 0);
}

=head2 display_info

Returns the display information as a hashref. The display URI is in the display entry

=cut

sub display_info($self, $user) {

    my $xml = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_SECURE));
    my @graph = $xml->findnodes('/domain/devices/graphics')
        or return;

    my $n_order = 0;
    my @display;
    for my $graph ( @graph ) {
        my ($type) = $graph->getAttribute('type');
        my $display;
        if ($type eq 'spice') {
            $display = _display_info_spice($graph);
        } elsif ($type eq 'vnc' ) {
            $display= _display_info_vnc($graph);
        } else {
            confess "I don't know how to check info for $type display";
        }

        $display->{port} = undef if $display->{port} && $display->{port}==-1;
        $display->{is_secondary} = 0;
        my $display_tls;
        if (exists $display->{tls_port} && $display->{tls_port} && $self->_vm->tls_ca) {
            my %display_tls = %$display;
            $display_tls{port} = delete $display_tls{tls_port};
            $display_tls{port} = undef if $display_tls{port} && $display_tls{port}==-1;
            $display_tls{driver} .= "-tls";
            $display_tls{n_order} = ++$n_order;
            $display_tls{is_secondary} = 1;
            lock_hash(%display_tls);
            $display_tls = \%display_tls;
        }
        delete $display->{tls_port} if exists $display->{tls_port};
        $display->{n_order} = ++$n_order;
        lock_hash(%$display);
        push @display,($display_tls) if $display_tls;
        push @display,($display);
    }
    return $display[0] if !wantarray;
    return @display;
}

sub _display_info_vnc($graph) {
    my ($type) = $graph->getAttribute('type');
    my ($port) = $graph->getAttribute('port');
    my ($tls_port) = $graph->getAttribute('tlsPort');
    my ($address) = $graph->getAttribute('listen');

    my ($password) = $graph->getAttribute('passwd');

    my %display = (
              driver => $type
               ,port => $port
                 ,ip => $address
         ,is_builtin => 1
    );
    $display{tls_port} = $tls_port if defined $tls_port && $tls_port;
    $display{password} = $password;
    $port = '' if !defined $port;

    for my $item ( $graph->findnodes("*")) {
        next if $item->getName eq 'listen';
        for my $attr ( $item->getAttributes()) {
            my $value = $attr->toString();
            $value =~ s/^\s+//;
            $display{$item->getName()} = $value;
        }
    }
    return \%display;
}


sub _display_info_spice($graph) {
    my ($type) = $graph->getAttribute('type');
    my ($port) = $graph->getAttribute('port');
    my ($tls_port) = $graph->getAttribute('tlsPort');
    my ($address) = $graph->getAttribute('listen');

    my ($password) = $graph->getAttribute('passwd');

    my %display = (
              driver => $type
               ,port => $port
                 ,ip => $address
         ,is_builtin => 1
    );
    $display{tls_port} = $tls_port if defined $tls_port;
    $display{password} = $password;
    $port = '' if !defined $port;

    for my $item ( $graph->findnodes("*")) {
        next if $item->getName eq 'listen';
        for my $attr ( $item->getAttributes()) {
            my $value = $attr->toString();
            $value =~ s/^\s+//;
            $display{$item->getName()} = $value;
        }
    }

    return \%display;
}

sub _has_builtin_display($self) {
    my $xml = XML::LibXML->load_xml(string => $self->xml_description());
    my ($graph) = $xml->findnodes('/domain/devices/graphics');
    return 1 if $graph;
    return 0;
}

sub _is_display_builtin($self, $index=undef, $data=undef) {
    if ( defined $index && $index !~ /^\d+$/ ) {
        return 1 if $index =~ /spice|vnc/i;
        return 0;
    }
    return 1 if defined $data && $data->{driver} =~ /spice|vnc/i;

    my $xml = XML::LibXML->load_xml(string => $self->xml_description());
    my @graph = $xml->findnodes('/domain/devices/graphics');

    return 1 if defined $index && exists $graph[$index];

    return 0;
}


=head2 is_active

Returns whether the domain is running or not

=cut

sub is_active {
    my $self = shift;
    return 0 if $self->is_removed;
    my $is_active = 0;
    eval { $is_active = $self->domain->is_active };
    return 0 if $@ && (    $@->code == 1    # client socket is closed
                        || $@->code == 38   # broken pipe
                    );
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

    my $remote_ip = delete $arg{remote_ip};
    my $request = delete $arg{request};
    my $listen_ip = ( delete $arg{listen_ip} or $self->_listen_ip);
    my $set_password = delete $arg{set_password};


    my $is_active = 0;
    eval { $is_active = $self->domain->is_active };
    warn $@ if $@;
    if (!$is_active && !$self->is_hibernated) {
        $self->_check_qcow_format($request);
        $self->_set_volumes_backing_store();
        $self->_detect_disks_driver();
        $self->_set_displays_ip($set_password, $listen_ip);
    }

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
        die "Error starting ".$self->name." on ".$self->_vm->name
            ."\n$error";
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

sub _check_qcow_format($self, $request) {
    return if $self->is_active;
    for my $vol ( $self->list_volumes_info ) {
        next if !$vol->file || $vol->file =~ /iso$/;
        next if !$vol->backing_file;

        next if $vol->_qemu_info('backing file format') eq 'qcow2';

        $request->status("rebasing","rebasing to release 0.8 "
            .$vol->file."\n".$vol->backing_file) if $request;
        $vol->rebase($vol->backing_file);
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

=head2 reboot

Stops the domain

=cut

sub reboot {
    my $self = shift;
    my %args = @_;
    my $req = $args{req};

    if (!$self->is_active) {
        $req->status("done")           if $req;
        $req->error("Domain is down")  if $req;
        return;
    }

    return $self->_do_force_shutdown() if $args{force};
    return $self->_do_reboot();

}

sub force_reboot {
    my $self = shift;
    return $self->_do_force_reboot()  if $self->is_active;
}

sub _do_force_reboot {
    my $self = shift;
    return if !$self->domain->is_active;
    eval { $self->domain->reset() };
    warn $@ if $@;
}

sub _do_reboot {
    my $self = shift;
    return if !$self->domain->is_active;
    eval { $self->domain->reboot() };
    die $@ if $@;
}

=head2 reboot_now

Reboots uncleanly the domain

=cut

sub reboot_now {
    my $self = shift;
    return $self->_do_reboot()  if $self->is_active;
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
    confess $@ if $@ && $@ !~ /libvirt error code: 55/;
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
    my $format = delete $args{format};
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

    my ($machine_type) = $self->_os_type_machine();
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
        ,format => $format
        ,allocation => ($args{allocation} or undef)
        ,target => $target_dev
    )   if !$path && $device ne 'cdrom';
    ($name) = $path =~ m{.*/(.*)} if !$name;

# TODO check if <target dev="/dev/vda" bus='virtio'/> widhout dev works it out
# change dev=vd*  , slot=*
#
    my $driver_type = ( $format or 'qcow2');
    my $cache = 'default';

    if ( $args{swap} || $device eq 'cdrom' ) {
        $cache = 'none';
        $driver_type = 'raw'    if !defined $format;
    }

    if ( !defined $bus ) {
        if  ($device eq 'cdrom') {
            $bus = 'ide';
            $bus = 'sata' if $machine_type =~ /^pc-(i440fx|q35)/;
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
    return ( $path or $name);
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

sub _get_boot_order($self, $index) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));
    my $count = 0;
    for my $device ($doc->findnodes('/domain/devices/disk')) {
        if ( $count++ == $index ) {
            my ($boot) = $device->findnodes('boot');
            if ($boot) {
                return $boot->getAttribute('order');
            }
            return;
        }
    }
}

sub _cmd_boot_order($self, $set, $index=undef, $order=1) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));
    my $count = 0;

    # if index is not numeric is the file, search the real index
    $index = $self->_search_volume_index($index) if defined $index && $index !~ /^\d+$/;

    if ( $set ) {
        my $current_order = $self->_get_boot_order($index);
        return $doc if defined $current_order && $current_order == $order;
    }

    my %used_order;
    my $changed = 0;
    for my $device ($doc->findnodes('/domain/devices/disk')) {
        my ($boot) = $device->findnodes('boot');
        if ( defined $index && $count++ != $index) {
            next if !$set || !$boot;
            my $this_order = $boot->getAttribute('order');
            next if !defined $this_order || $this_order < $order;
            $boot->setAttribute( order => $this_order+1);
            $used_order{$this_order+1}++;
            $changed++;
            next;
        }
        if (!$set) {
            next if !$boot;
            $device->removeChild($boot);
        } else {
            my $old_order;
            $old_order = $boot->getAttribute('order') if $boot;
            return $doc if defined $old_order && $old_order == $order;

            $boot = $device->addNewChild(undef,'boot')  if !$boot;
            $boot->setAttribute( order => $order );
            $used_order{$order}++;
            $changed++;
        }
    }
    $self->_bump_boot_order_interfaces($doc,\%used_order) if $changed;
    return $doc;
}

sub _bump_boot_order_interfaces($self, $doc, $used_order) {
    for my $boot ($doc->findnodes('/domain/devices/interface/boot')) {
        my $current_order = $boot->getAttribute('order');
        next if !defined $current_order || !$used_order->{$current_order};
        my $free_order = $current_order;
        for (;;) {
            last if !$used_order->{$free_order};
            $free_order++;
        }
        $boot->setAttribute('order' => $free_order);
    }
}

sub _search_volume_index($self, $file) {
    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE));
    my $index = 0;
    for my $device ($doc->findnodes('/domain/devices/disk')) {
        my ($source) = $device->findnodes('source');
        return $index if $source && $source->getAttribute('file') eq $file;
        $index++;
    }
    confess "I can't find file $file in ".$self->name;
}

sub _xml_new_device($self , %arg) {
    my $bus = delete $arg{bus} or confess "Missing bus.";
    my $file = ( delete $arg{file} or '');
    my $boot = delete $arg{boot};
    my $device = delete $arg{device};

    my $xml = <<EOT;
    <disk type='file' device='$device'>
      <driver name='qemu' type='$arg{type}' cache='$arg{cache}'/>
      <source file='$file'/>
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

    for my $name (qw(disk controller interface graphics sound video memballoon * )) {
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
    for my $dec ( 2 .. 99) {
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

    if ( $self->is_active() ) {
        $info->{ip} = $self->ip();
        my @interfaces;
        eval { @interfaces = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_LEASE) };
        my @interfaces2;
        eval { @interfaces2 = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_AGENT) };
        @interfaces = @interfaces2 if !scalar(@interfaces);
        $info->{interfaces} = \@interfaces;
    }

    lock_keys(%$info);
    return $info;
}

sub _ip_agent($self) {
    my @ip;
    eval { @ip = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_AGENT) };
    return if $@ && $@ =~ /^libvirt error code: (74|86),/;
    warn $@ if $@;

    my $found;
    for my $if (@ip) {
        next if $if->{name} =~ /^lo/;
        for my $addr ( @{$if->{addrs}} ) {

            next unless $addr->{type} == 0 && $addr->{addr} !~ /^127\./;

            $found = $addr->{addr} if !$found;

            return $addr->{addr}
            if $self->_vm->_is_ip_nat($addr->{addr});
        }
    }
    return $found;
}

#sub _ip_arp($self) {
#    my @sys_virt_version = split('\.', $Sys::Virt::VERSION);
#    return undef if ($sys_virt_version[0] < 5);
#    my @ip;
#    eval " @ip = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_ARP); ";
#    return @ip;
#}

sub ip($self) {
    my ($ip) = $self->_ip_agent();
    return $ip if $ip;

    my @ip;
    eval { @ip = $self->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_LEASE) };
    warn $@ if $@;
    return $ip[0]->{addrs}->[0]->{addr} if $ip[0];

#    @ip = $self->_ip_arp();
#    return $ip[0]->{addrs}->[0]->{addr} if $ip[0];

    return;
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

sub _set_displays_ip($self, $set_password, $ip=undef) {
    return $self->_set_spice_ip($set_password, $ip);
}

sub _set_spice_ip($self, $set_password, $ip=undef) {

    return if $self->is_hibernated() || $self->domain->is_active;

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
        $self->domain->update_device($graphics, Sys::Virt::Domain::DEVICE_MODIFY_CONFIG);

        $self->domain->update_device($graphics, Sys::Virt::Domain::DEVICE_MODIFY_LIVE)
        if $self->domain->is_active;

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
            confess "I can't find name=value in '$item'";
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

sub _update_device_graphics($self, $driver, $data) {
    my $doc = XML::LibXML->load_xml(string
        => $self->domain->get_xml_description());
    $driver =~ s/-tls$//;
    my $path = "/domain/devices/graphics\[\@type='$driver']";
    my ($device ) = $doc->findnodes($path);
    die "$path not found ".$self->name if !$device;

    my $port = delete $data->{port};
    $device->setAttribute(port => $port);
    $device->removeAttribute('autoport');
    $self->domain->update_device($device,Sys::Virt::Domain::DEVICE_MODIFY_LIVE);
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

    $self->reload_config($doc) if $changed;

}

sub _add_driver($self, $xml_path, $attributes=undef) {

    my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);

    my @nodes = $doc->findnodes($xml_path);
    return if @nodes;

    my ($xml_parent, $new_node) = $xml_path =~ m{(.*)/(.*)};
    my @parent = $doc->findnodes($xml_parent);

    confess "Expecting one parent, I don't know what to do with ".scalar @parent
        if scalar@parent > 1;

    @parent = _add_driver($self, $xml_parent)  if !@parent;

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

sub _set_driver_video($self,$value) {
    $value = "type=$value" unless $value =~ /=/;
    return $self->_set_driver_generic('/domain/devices/video',$value);
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

sub _set_driver_cpu($self, $value) {
    return $self->change_hardware('cpu',0,{cpu => { mode => $value}});
}

sub _set_driver_usb_controller($self, $value) {
    return $self->change_hardware('usb controller',0,{ model => $value});
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
sub _set_hw_usb($self,$numero, $data={}) {

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
        my @usb_ctrl = $devices->findnodes('./controller[@type="usb"]');
        if ($numero > scalar(@usb_ctrl)*4) {
            $self->_set_hw_usb_controller(undef);
            $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
            ($devices) = $doc->findnodes('/domain/devices');
        }
        my $missing = $numero-$count;
        for my $i (1..$missing) {
            my $controller = $devices->addNewChild(undef,"redirdev");
            $controller->setAttribute(bus => 'usb');
            $controller->setAttribute(type => $tipo );
        }
    }
    $self->reload_config($doc);
}

sub _set_hw_usb_controller($self, $number=undef, $data={model => 'qemu-xhci'}) {

    confess "Error: I can't add a negative number of usb controllers"
    if defined $number && $number <1;

    $data->{model} = 'qemu-xhci' if !exists $data->{model};
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);

    my ($devices) = $doc->findnodes("/domain/devices");
    my @usb_ctrl = $devices->findnodes('./controller[@type="usb"]');

    $number = scalar(@usb_ctrl)+1 if !$number;
    for my $n( scalar(@usb_ctrl)+1 .. $number ) {
        my $device = $devices->addNewChild(undef,'controller');
        $device->setAttribute('type' => 'usb');
        for my $field (keys %$data) {
            confess Dumper($data->{$field}) if ref($data->{$field});
            $device->setAttribute($field,$data->{$field});
        }
    }
    $self->reload_config($doc);

}

sub _has_usb_hub($self) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    for my $hub ( $doc->findnodes("/domain/devices/hub") ) {
        return 1 if $hub->getAttribute('type') eq 'usb';
    }
    return 0;
}

sub _add_usb_hub($self) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    my @n = $doc->findnodes("/domain/devices/redirdev");
    my ($devices) = $doc->findnodes('/domain/devices');
    my $n = 0;
    my $type;
    for my $redirdev ($devices->findnodes("redirdev")) {
        if ( $n==scalar(@n)-1 ) {
            $type = $redirdev->getAttribute('type');
            $devices->removeChild($redirdev);
            last;
        }
        $n++;
    }
    my $hub = $devices->addNewChild(undef,"hub");
    $hub->setAttribute(type => "usb");
    $self->reload_config($doc);
    my $controller = $devices->addNewChild(undef,"redirdev");
    $controller->setAttribute(bus => 'usb');
    $controller->setAttribute(type => $type);

    return $doc;
}


sub _set_controller_disk($self, $number, $data) {
    $self->add_volume(%$data);
}

sub _set_controller_sound($self, $number , $data={ model => 'ich6' } ) {
    $data->{model} = 'ich6' if !exists $data->{model};
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    my ($devices) = $doc->findnodes("/domain/devices");
    my $sound = $devices->addNewChild(undef,'sound');
    for my $field (keys %$data) {
        confess Dumper($data->{$field}) if ref($data->{$field});
        $sound->setAttribute($field,$data->{$field});
    }

    $self->reload_config($doc);
}

sub _set_shared_memory($self, $doc) {
    my ($mem) = $doc->findnodes("/domain/memoryBacking");
    if (!$mem) {
        my ($domain) = $doc->findnodes("/domain");
        $mem = $domain->addNewChild(undef, "memoryBacking");
    }
    my ($source) = $mem->findnodes("source");
    $source = $mem->addNewChild(undef,"source") if !$source;
    $source->setAttribute('type' => 'memfd');

    my ($access) = $mem->findnodes("access");
    $access = $mem->addNewChild(undef,"access") if !$access;
    $access->setAttribute('mode' => 'shared');
}

sub _set_controller_filesystem($self, $number, $data) {
    die "Error: missing source in ".Dumper($data) if !exists $data->{source};
    die "Error: missing source->{dir} in ".Dumper($data) if !ref($data->{source}) || !exists $data->{source}->{dir};

    my $source = delete $data->{source}->{dir} or die "Error: missing source";

    die "Error: source '$source' doesn't exist"
    if !$self->_vm->file_exists($source);

    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);

    $self->_set_shared_memory($doc);

    my ($devices) = $doc->findnodes("/domain/devices");

    my $fs = $devices->addNewChild(undef,'filesystem');
    $fs->setAttribute( 'type' => 'mount' );
    $fs->setAttribute( 'accessmode' => 'passthrough' );
    my $driver = $fs->addNewChild(undef,'driver');
    $driver->setAttribute('type' => 'virtiofs');
    my $source_xml = $fs->addNewChild(undef,'source');
    $source_xml->setAttribute('dir' => $source);

    my $target = $source;
    $target =~ s{^/}{};
    $target =~ s{/$}{};
    $target =~ s{/}{_}g;

    my $target_xml = $fs->addNewChild(undef,'target');
    $target_xml->setAttribute('dir' => $target);

    $self->reload_config($doc);
}

sub _set_controller_video($self, $number, $data={type => 'qxl'}) {
    $data->{type} = 'qxl' if !exists $data->{type};
    $data->{type} = lc(delete $data->{driver}) if exists $data->{driver};
    my $pci_slot = $self->_new_pci_slot();

    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    my ($devices) = $doc->findnodes("/domain/devices");
    if (exists $data->{primary} && $data->{primary} =~ /yes/) {
        _remove_all_video_primary($devices);
    }
    my $video = $devices->addNewChild(undef,'video');
    my $model = $video->addNewChild(undef,'model');
    for my $field (keys %$data) {
        confess Dumper($data->{$field}) if ref($data->{$field});
        $model->setAttribute($field,$data->{$field});
    }
    if ( $model->getAttribute('type') =~ /cirrus|vga/i ) {
        if ( !$model->getAttribute('primary')
            || $model->getAttribute('primary') !~ /yes/i) {
            _remove_all_video_primary($devices);
            $model->setAttribute('primary','yes')
        }
    }
    $self->reload_config($doc);
}

sub _remove_all_video_primary($devices) {
    for my $video ($devices->findnodes("video")) {
        for my $model ($video->findnodes('model')) {
            $model->removeAttribute('primary');
        }
    }
}

sub _set_controller_network($self, $number, $data) {

    my $driver = (delete $data->{driver} or 'virtio');
    my $type = ( delete $data->{type} or 'NAT' );
    my $network =(delete $data->{network} or 'default');
    my $bridge = (delete $data->{bridge}  or '');

    confess "Error: unkonwn fields in data ".Dumper($data) if keys %$data;

    my $pci_slot = $self->_new_pci_slot();

    my $device = "<interface type='network'>
        <mac address='".$self->_vm->_new_mac()."'/>";
    if ($type eq 'NAT') {
        $device .= "<source network='$network'/>"
    } elsif ($type eq 'bridge') {
        $device .= "<source bridge='$bridge'/>"
    } else {
        die "Error adding network, unknown type '$type'";
    }

    $device .=
        "<model type='$driver'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='$pci_slot' function='0x0'/>
      </interface>";

      $self->domain->attach_device($device, Sys::Virt::Domain::DEVICE_MODIFY_CONFIG);
}

sub _set_controller_display_spice($self, $number, $data) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    for my $graphic ( $doc->findnodes("/domain/devices/graphics")) {
        next if $graphic->getAttribute('type') ne 'spice';
        die "Changing ".$graphic->toString()." ".Dumper($data);
    }
    my ($devices) = $doc->findnodes("/domain/devices");
    my $graphic = $devices->addNewChild(undef,'graphics');
    $graphic->setAttribute(type => 'spice');

    my $port = ( delete $data->{port} or 'auto');
    $graphic->setAttribute( port => $port )     if $port ne 'auto';
    $graphic->setAttribute( autoport => 'yes')  if $port eq 'auto';

    my $ip = (delete $data->{ip} or $self->_vm->listen_ip);

    $graphic->setAttribute(listen => $ip);
    my $listen = $graphic->addNewChild(undef,'listen');
    $listen->setAttribute(type => 'address');
    $listen->setAttribute(address => $ip);

    my %defaults = (
        image => "compression=auto_glz"
        ,jpeg => "compression=auto"
        ,zlib => "compression=auto"
        ,playback => "compression=on"
        ,streaming => "mode=filter"
    );
    for my $name (keys %defaults ) {
        my ($attrib,$value) = $defaults{$name} =~ m{(.*)=(.*)};
        die "Error in $defaults{$name} " if !defined $attrib || !defined $value;

        my $item = $graphic->addNewChild(undef, $name);
        $item->setAttribute($attrib => $value);
    }
    $self->reload_config($doc);
}

sub _set_controller_display_vnc($self, $number, $data) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    for my $graphic ( $doc->findnodes("/domain/devices/graphics")) {
        next if $graphic->getAttribute('type') ne 'vnc';
        die "Changing ".$graphic->toString()." ".Dumper($data);
    }
    my ($devices) = $doc->findnodes("/domain/devices");
    my $graphic = $devices->addNewChild(undef,'graphics');
    $graphic->setAttribute(type => 'vnc');

    my $port = ( delete $data->{port} or 'auto');
    $graphic->setAttribute( port => $port )     if $port ne 'auto';
    $graphic->setAttribute( autoport => 'yes')  if $port eq 'auto';

    my $ip = (delete $data->{ip} or $self->_vm->listen_ip);

    my $listen = $graphic->addNewChild(undef,'listen');
    $listen->setAttribute(type => 'address');
    $listen->setAttribute(address => $ip);

    my %defaults = (
    );
    for my $name (keys %defaults ) {
        my ($attrib,$value) = $defaults{$name} =~ m{(.*)=(.*)};
        die "Error in $defaults{$name} " if !defined $attrib || !defined $value;

        my $item = $graphic->addNewChild(undef, $name);
        $item->setAttribute($attrib => $value);
    }
    $self->reload_config($doc);
}


sub _set_controller_display($self, $number, $data) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);

    return $self->_set_controller_display_spice($number, $data)
    if defined $data && $data->{driver} eq 'spice';

    return $self->_set_controller_display_vnc($number, $data)
    if defined $data && $data->{driver} eq 'vnc';

    my @graphics = $doc->findnodes("/domain/devices/graphics");
    return $self->_set_controller_display_spice($number, $data)
    if exists $graphics[$number] && $graphics[$number]->getAttribute('type') eq 'spice';

    confess "I don't know how to set controller_display ".Dumper($number, $data);
}


sub remove_controller($self, $name, $index=0,$attribute_name=undef, $attribute_value=undef) {
    my $sub = $REMOVE_CONTROLLER_SUB{$name};
    
    die "I can't get controller $name for domain ".$self->name
        ." ".$self->type
        ."\n".Dumper(\%REMOVE_CONTROLLER_SUB)
        if !$sub;

    my $ret;

    #some hardware can be removed searching by attribute
    if($name eq 'display' || defined $attribute_name ) {
        $ret = $sub->($self, undef, $attribute_name, $attribute_value);
    } else {
        $ret = $sub->($self, $index);
    }
    $self->xml_description_inactive();
    return $ret;
}

sub _find_child($controller, $name) {
    return ($controller,$name) if !defined $name || $name !~ m{(.*?)/(.*)};

    my ($child_name, $attribute) = ($1,$2);
    my ($item) = $controller->findnodes($child_name);
    return ($controller,$name) if !$item;

    return _find_child($item, $attribute);
}

sub _remove_device($self, $index, $device, $attribute_name0=undef, $attribute_value=undef) {
    confess "Error: I need index defined or attribute name=value"
    if !defined $index && !defined $attribute_name0;

    confess "Error: I attribute value to search must be defined"
    if defined $attribute_name0 && !defined $attribute_value;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description_inactive);
    my ($devices) = $doc->findnodes('/domain/devices');
    my $ind=0;
    my @found;
    for my $controller ($devices->findnodes($device)) {
        my ($item, $attr_name)= _find_child($controller, $attribute_name0);

        my $found = 0;
        if ( defined $attr_name ) {
            my $found_value = $item->getAttribute($attr_name);
            push @found,($found_value or '');

            if ( $found_value =~ $attribute_value ) {
                $found=1 if !defined $index || $ind == $index;
                $ind++;
            }

        } else {
            $found = 1 if defined $index && $ind == $index;
            $ind++;
        }

        if($found ){
            my ($source ) = $controller->findnodes("source");
            my $file;
            $file = $source->getAttribute('file') if $source;

            $devices->removeChild($controller);
            $self->_vm->connect if !$self->_vm->vm;
            $self->reload_config($doc);

            return $file;
        }
    }

    my $msg = "";
    $msg = " $attribute_name0=$attribute_value ".join(",",@found)
    if defined $attribute_name0;

    confess "ERROR: $device $msg ".($index or '<UNDEF>')
        ." not removed, only ".($ind)." found in ".$self->name."\n";
}

sub _remove_controller_display($self, $index, $attribute_name=undef, $attribute_value=undef) {
    $self->_remove_device($index,'graphics', $attribute_name,$attribute_value );
}


sub _remove_controller_usb($self, $index) {
    $self->_remove_device($index,'redirdev', bus => 'usb');
}

sub _remove_hw_usb_controller($self, $index) {
    $self->_remove_device($index,'controller', type => 'usb');
}

sub _remove_controller_disk($self, $index,  $attribute_name=undef, $attribute_value=undef) {
    my @volumes = $self->list_volumes_info();
    confess "Error: domain ".$self->name
        ." trying to remove $index"
        ." has only ".scalar(@volumes)
        if defined $index && $index >= scalar(@volumes);

    confess "Error: undefined volume $index ".Dumper(\@volumes)
        if defined $index && !defined $volumes[$index];

    confess "Error: undefined index and attribute"
        if !defined $index && !defined $attribute_name;

    my $file;
    if ($attribute_name) {
        $file = $self->_remove_device($index,'disk',$attribute_name => $attribute_value);
    } else {
        $file = $self->_remove_device($index,'disk');
    }

    $self->remove_volume( $file );
    $self->info(Ravada::Utils::user_daemon);
}

sub _remove_controller_filesystem($self, $index) {
    $self->_remove_device($index,'filesystem');
}

sub _remove_controller_sound($self, $index) {
    $self->_remove_device($index,'sound');
}

sub _remove_controller_video($self, $index) {
    $self->_remove_device($index,'video');
}

sub _remove_controller_network($self, $index) {
    $self->_remove_device($index,'interface' );
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

sub _check_machine($self,$doc, $node) {
    my ($os_type) = $doc->findnodes('/domain/os/type');
    my $machine = $os_type->getAttribute('machine');

    my ($machine_bare) = $machine =~ /(.*)-\d+\.\d+$/;
    my %machine_types = $node->list_machine_types;
    my $new_machine = $machine;

    my $arch = $os_type->getAttribute('arch');
    for my $try ( @{$machine_types{$arch}} ) {
        if ($try eq $machine) {
            $new_machine = $try;
            last;
        }
        $new_machine = $try if $try =~ /^$machine_bare/;
    }
    $os_type->setAttribute( machine => $new_machine);
}

sub migrate($self, $node, $request=undef) {
    my $dom;
    eval { $dom = $node->vm->get_domain_by_name($self->name) };
    die $@ if $@ && $@ !~ /libvirt error code: 42/;

    if ($dom) {
        #dom already in remote node
        $self->domain($dom);
    } else {
        $self->_set_displays_ip(1, $node->ip);
        my $xml = $self->domain->get_xml_description();

        my $doc = XML::LibXML->load_xml(string => $xml);
        $self->_check_machine($doc, $node);
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
    $self->_set_displays_ip(1, $node->ip);

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
    return if $@ && ($@->code == 38  # cannot recv data
                    || $@->code == 1 # client socket is closed
    );
    die $@ if $@;
    return $is_removed;
}

sub internal_id($self) {
    confess "ERROR: Missing internal domain"    if !$self->domain;
    return $self->domain->get_id();
}

sub autostart { return _internal_autostart(@_) }

sub _internal_autostart($self, $value=undef, $user=undef) {
    $self->domain->set_autostart($value) if defined $value;
    return $self->domain->get_autostart();
}

sub change_hardware($self, $hardware, @args) {
    my $sub =$CHANGE_HARDWARE_SUB{$hardware}
        or confess "Error: I don't know how to change hardware '$hardware'";

    return $sub->($self, @args);
}

sub _fix_hw_disk_args($data) {
    delete $data->{capacity}
    if ( exists $data->{device} && $data->{device} eq 'cdrom')
    || ( exists $data->{file} && $data->{file} =~ /\.iso$/)
    ;


    for (qw( allocation backing bus device driver_cache driver_name driver_type name target type )) {
        delete $data->{$_} if exists $data->{$_};
    }
}

sub _change_hardware_disk($self, $index, $data) {
    my @volumes = $self->list_volumes_info();
    confess "Error: Unknown volume $index, only ".(scalar(@volumes)-1)." found"
        .Dumper(\@volumes)
        if $index>=scalar(@volumes);

    _fix_hw_disk_args($data);

    my $driver = delete $data->{driver};
    my $boot = delete $data->{boot};

    $self->_change_hardware_disk_bus($index, $driver)   if $driver;
    $self->_set_boot_order($index, $boot)               if $boot;

    if ( exists $data->{'capacity'} ) {
        my $capacity = delete $data->{'capacity'};
        $self->_change_hardware_disk_capacity($index,$capacity)
            if $capacity;
    }

    if ( exists $data->{'file'}) {
        my $file_new = delete $data->{'file'};
        $self->_change_hardware_disk_file($index, $file_new)
            if defined $file_new;
    }

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

    $self->reload_config($doc);
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

    $self->reload_config($doc);
}

sub _change_hardware_display($self, $index, $data) {
    my $type = delete $data->{driver};
    $type =~ s/-tls$//;
    my $port = delete $data->{port};
    confess if $port;
    for my $item (keys %$data) {
        $self->_set_driver_generic_simple("/domain/devices/graphics\[\@type='$type']/$item",$data->{$item});
    }
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
    $self->reload_config($doc);

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

sub _fix_hw_video_args($data) {
    $data->{type} = lc(delete $data->{driver})
    if exists $data->{driver};

    my $driver = $data->{type};

    delete $data->{ram} if $driver ne 'qxl';
    delete $data->{vgamem} if $driver ne 'qxl';

    if ($driver eq 'cirrus' or $driver eq 'vga') {
        delete $data->{vgamem};
        $data->{primary} = "yes";
    }

    delete $data->{acceleration} unless $driver eq 'virtio';

    if (exists $data->{primary}) {
        if ($data->{primary}) {
            $data->{primary} = 'yes'
        } else {
            delete $data->{primary};
        }
    }
}

sub _change_hardware_features($self, $index, $data) {
    $data = { 'acpi' => 1, 'apic' => 1, 'kvm' => undef, 'hap' => 0 }
    if !keys %$data;

    $data->{kvm} = {hidden=> { state => 'off'}} if exists $data->{kvm} && $data->{kvm} == 1;

    lock_hash(%$data);

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my $count = 0;
    my $changed = 0;


    my ($features) = $doc->findnodes('/domain/features');
    if (!$features) {
        my ($domain) = $doc->findnodes("/domain");
        $features = $domain->addNewChild(undef,'features');
    }
    for my $field (keys %$data) {
        next if $field =~ /^_/;
        my ($item) = $features->findnodes($field);
        next if !$item && !$data->{$field};
        if (ref($data->{$field})) {
            if (!$item) {
                $item = $features->addNewChild(undef,$field);
                $changed++;
            }
            _change_xml($features,$field,$data->{$field});
            $changed++;
        }
        if (!$item) {
            $item = $features->addNewChild(undef,$field);
            $changed++;
        } elsif (!$data->{$field}) {
            $features->removeChild($item);
            $changed++;
        }
    }
    $self->reload_config($doc) if $changed;
}

sub _change_hardware_filesystem($self, $index, $data) {
    confess "Error: nothing to change ".Dumper($data)
    if !keys %$data;

    die "Error: missing source ".Dumper($data)
    if !exists $data->{source};

    $data->{source} = {dir => $data->{source}}
    if !ref($data->{source});

    confess "Error: missing source->{dir} ".Dumper($data)
    if !ref($data->{source}) || !exists $data->{source}->{dir}
    || !defined $data->{source}->{dir};

    my $source = delete $data->{source}->{dir};
    my $target;
    $target = delete $data->{target}->{dir} if exists $data->{target};

    delete $data->{source}
    if !keys %{$data->{source}};
    delete $data->{target}
    if !keys %{$data->{target}};

    confess "Error: extra arguments ".Dumper($data)
    if keys %$data;

    if (!$target) {
        $target = $source;
        $target =~ s{^/}{};
        $target =~ s{/$}{};
        $target =~ s{/}{_}g;
    }

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my $count = 0;
    my $changed = 0;

    my ($devices) = $doc->findnodes('/domain/devices');
    for my $fs ($devices->findnodes('filesystem')) {
        next if $count++ != $index;
        my ($xml_source) = $fs->findnodes("source");
        my ($xml_target) = $fs->findnodes("target");
        $xml_source->setAttribute(dir => $source);
        $xml_target->setAttribute(dir => $target) if $target;
        $changed++;
    }

    $self->reload_config($doc) if $changed;
}

sub _default_cpu($self) {

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my ($type) = $doc->findnodes("/domain/os/type");

    my $data = {
        'vcpu'=> {'#text' => 1 , 'placement' => 'static'}
        ,'cpu' => { 'model' => { '#text' => 'qemu64' }
        }
    };

    my ($x86) = $type->getAttribute('arch') =~ /^x86_(\d+)/;
    if ($x86) {
        $data->{cpu} = { 'mode' =>'custom'
            , 'model' => { '#text' => 'qemu'.$x86 } };
    } else {
        warn "I don't know default CPU for arch ".$type->getAttribute()
        ." in domain ".$self->name;
        $data->{cpu} = { 'mode' => 'host-model' };
    }

    return $data;

}

sub _fix_vcpu_from_topology($self, $data) {
    if (!exists $data->{cpu}->{topology}
        || !defined($data->{cpu}->{topology})) {

        return;
    }

    if (!keys %{$data->{cpu}->{topology}}) {
        $data->{cpu}->{topology} = undef;
        return;
    }
    for (qw(dies sockets cores threads)) {
        $data->{cpu}->{topology}->{$_} = 1
        if !$data->{cpu}->{topology}->{$_};
    }
    my $dies = $data->{cpu}->{topology}->{dies} or 1;
    my $sockets = $data->{cpu}->{topology}->{sockets} or 1;
    my $cores = $data->{cpu}->{topology}->{cores} or 1;
    my $threads = $data->{cpu}->{topology}->{threads} or 1;

    delete $data->{cpu}->{topology}->{dies} if $self->_vm->_data('version') < 8000000;

    $data->{vcpu}->{'#text'} = $dies * $sockets * $cores * $threads ;
}

sub _change_hardware_cpu($self, $index, $data) {
    $data = $self->_default_cpu()
    if !keys %$data;

    $data->{'cpu'}->{'model'}->{'#text'} = 'qemu64'
    if !$data->{cpu}->{'model'}->{'#text'};

    delete $data->{cpu}->{model}->{'$$hashKey'};

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my $count = 0;
    my $changed = 0;

    my ($n_vcpu) = $doc->findnodes('/domain/vcpu/text()');

    $self->_fix_vcpu_from_topology($data);
    lock_hash(%$data);

    my ($vcpu) = $doc->findnodes('/domain/vcpu');
    if (exists $data->{vcpu} && $n_vcpu ne $data->{vcpu}->{'#text'}) {
        $vcpu->removeChildNodes();
        $vcpu->appendText($data->{vcpu}->{'#text'});
    }
    my ($domain) = $doc->findnodes('/domain');
    my ($cpu) = $doc->findnodes('/domain/cpu');
    if (!$cpu) {
        $cpu = $domain->addNewChild(undef,'cpu');
    }
    my $feature = delete $data->{cpu}->{feature};

    $changed += _change_xml($domain, 'cpu', $data->{cpu});

    if ( $feature ) {
        _change_xml_list($cpu, 'feature', $feature, 'name');
        $changed++;
    }

    $self->reload_config($doc) if $changed;
}


sub _change_hardware_sound($self, $index, $data) {
    confess "Error: nothing to change ".Dumper($data)
    if !keys %$data;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my $count = 0;
    my $changed = 0;

    my ($devices) = $doc->findnodes('/domain/devices');
    for my $device ($devices->findnodes('sound')) {
        next if $count++ != $index;
        for my $field (keys %$data) {
            if (ref($data->{$field})) {
                _change_xml($device, $field, $data->{$field});
                $changed++;
                next;
            }
            if ( !defined $device->getAttribute($field)
                || $device->getAttribute($field) ne $data->{$field}) {
                    $device->setAttribute($field, $data->{$field});
                    $changed++;
            }

        }
        last;
    }

    $self->reload_config($doc) if $changed;
}

sub _change_hardware_video($self, $index, $data) {
    if (!keys %$data) {
        $data = { 'type' => 'qxl'
                  ,'ram' => 65536
                 ,'vram' => 65536
                ,'heads' => 1
        };
    }

    _fix_hw_video_args($data);

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my $count = 0;
    my $changed = 0;

    my ($devices) = $doc->findnodes('/domain/devices');
    for my $interface ($devices->findnodes('video')) {
        next if $count++ != $index;

        my ($model) = $interface->findnodes('model') or die "No model";

        for my $field (keys %$data) {
            if (ref($data->{$field})) {
                _change_xml($model, $field, $data->{$field});
                $changed++;
                next;
            }
            if ( !defined $model->getAttribute($field)
                || $model->getAttribute($field) ne $data->{$field}) {

                if ($field eq 'type' && $data->{$field} =~ /vga|cirrus/) {
                    _remove_all_video_primary($devices);
                    _remove_acceleration($model);
                    $model->setAttribute('primary' => 'yes');
                }
                if ($field eq 'primary' && $data->{$field}) {
                    _remove_all_video_primary($devices);
                    $changed++;
                }
                $model->setAttribute($field,$data->{$field});
                $changed++;
                if ($field eq 'type' && $data->{$field} ne 'qxl') {
                    $model->removeAttribute('ram');
                    $model->removeAttribute('vgamem');
                    #$model->removeAttribute('heads');
                }
            }
        }
        last;

    }
    $self->reload_config($doc) if $changed;
}

sub _change_hardware_usb_controller($self, $index, $data) {
    confess "Error: nothing to change ".Dumper($data)
    if !keys %$data;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    my $count = 0;
    my $changed = 0;

    my ($devices) = $doc->findnodes('/domain/devices');

    my $changed_piix3_uhci=0;

    for my $device ($devices->findnodes('controller')) {
        next if $device->getAttribute('type') ne 'usb';
        next if $count++ != $index;
        for my $field (keys %$data) {
            if (ref($data->{$field})) {
                _change_xml($device, $field, $data->{$field});
                $changed++;

                next;
            }
            if ( !defined $device->getAttribute($field)
                || $device->getAttribute($field) ne $data->{$field}) {
                $device->setAttribute($field, $data->{$field});
                $changed++;

                $changed_piix3_uhci++
                if $field eq 'model' && $data->{$field} eq 'piix3-uhci';

                _change_xml($device,'address', {
                        slot => '0x01'
                        ,function => '0x2'
                    });
            }

        }
        last;
    }


    $self->reload_config($doc) if $changed;
}


sub _remove_acceleration($video) {
    my ($acceleration) = $video->findnodes("acceleration");
    $video->removeChild($acceleration) if $acceleration;
}

sub _change_xml_list($xml,$name, $data, $field='name') {
    my %keep;
    for my $entry (@$data) {
        next if !defined $entry ||!$entry;
        $keep{$entry->{$field}}++;
        my $node;
        for my $curr ($xml->findnodes($name)) {
            $node = $curr if $curr->getAttribute($field) eq $entry->{$field};
        }
        $node = $xml->addNewChild(undef, $name) if !$node;
        for my $field (keys %$entry) {
            next if $field eq '$$hashKey';
            $node->setAttribute($field, $entry->{$field});
        }
    }

    for my $curr ($xml->findnodes($name)) {
        my $curr_name = $curr->getAttribute($field);
        $xml->removeChild($curr) if !$keep{$curr_name};
    }
}

sub _change_xml($xml, $name, $data) {
    confess Dumper([$name, $data])
    if !ref($data) || ( ref($data) ne 'HASH' && ref($data) ne 'ARRAY');

    my $changed = 0;

    my ($node) = $xml->findnodes($name);
    if (!$node) {
        $node = $xml->addNewChild(undef,$name);
        $changed++;
    }

    for my $field (keys %$data) {
        if ($field eq '#text') {
            my $text = $data->{$field};
            if ($node->textContent ne $text) {
                $node->setText($text);
            }
            next;
        }
        if (!defined $data->{$field}) {
            my ($child) = $node->findnodes($field);
            $node->removeChild($child) if $child;
            next;
        }
        if (ref($data->{$field})) {
            $changed += _change_xml($node,$field,$data->{$field});
        } else {
            next if defined $node->getAttribute($field)
            && $node->getAttribute($field) eq $data->{$field};

            $node->setAttribute($field, $data->{$field});
            $changed++;
        }
    }
    for my $child ( $node->childNodes() ) {
        my $name = $child->nodeName();
        if (!exists $data->{$name} || !defined $data->{$name} ) {
            $node->removeChild($child);
            $changed++;
        }
    }

    return $changed;
}

sub _change_hardware_network($self, $index, $data) {
    die "Error: index number si required.\n" if !defined $index;

    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    if (!keys %$data) {
        $data = {
            driver => 'virtio'
            ,type => 'nat'
            ,network => 'default'
        }
    }

       my $type = delete $data->{type};
     my $driver = lc(delete $data->{driver} or '');
     my $bridge = delete $data->{bridge};
    my $network = delete $data->{network};

    die "Error: Unknown arguments ".Dumper($data) if keys %$data;

    $type = lc($type) if defined $type;

    die "Error: Unknown type '$type' . Known: bridge, NAT"
        if $type && $type !~ /^(bridge|nat)$/;

    die "Error: Bridged type requires bridge.\n"
        if $type && $type eq 'bridge' && !$bridge;

    die "Error: NAT type requires network.\n"
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

    $self->reload_config($doc);
}



sub _validate_xml($self, $doc) {
    my $in = $doc->toString();
    my ($out, $err);
    run3(["virt-xml-validate","-"],\$in,\$out,\$err);
    if ( $? ){
        warn $out if $out;
        my $file_out = "/var/tmp/".$self->name().".xml";
        open my $out1,">",$file_out or die $!;
        print $out1 $self->xml_description();
        close $out1;
        my $file_new = "/var/tmp/".$self->name().".new.xml";
        open my $out2,">",$file_new or die $!;
        my $doc_string = $doc->toString();
        $doc_string =~ s/^<.xml.*//;
        $doc_string =~ s/"/'/g;
        print $out2 $doc_string;
        close $out2;

        confess "\$?=$? $err\ncheck $file_new" if $?;
    }
}

sub reload_config($self, $doc) {
    $self->_validate_xml($doc) if $self->_vm->vm->get_major_version >= 4;
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
}

sub copy_config($self, $domain) {
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description(Sys::Virt::Domain::XML_INACTIVE));
    my ($uuid) = $doc->findnodes("/domain/uuid/text()");
    confess "I cant'find /domain/uuid in ".$self->name if !$uuid;

    $uuid->setData($self->domain->get_uuid_string);
    my $new_domain = $self->_vm->vm->define_domain($doc->toString);
    $self->domain($new_domain);
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

    for (qw(controller unit target domain slot function)) {
        $address->removeAttribute($_);
    }

=pod

    $address->setAttribute(unit => $self->_new_address_xml(
            match => 'usb'
       ,attribute => 'port'
        )
    );

=cut

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

sub _remove_backingstore($self, $file) {

    my $doc = XML::LibXML->load_xml(string
            => $self->xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    my $n_order = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        my ($source_node) = $disk->findnodes('source');
        next if !$source_node;
        my $file_found = $source_node->getAttribute('file');
        next if !$file_found || $file_found ne $file;

        my ($backingstore) = $disk->findnodes('backingStore');
        $disk->removeChild($backingstore) if $backingstore;
    }
    $self->reload_config($doc);
}

sub has_nat_interfaces($self) {
    my $doc = XML::LibXML->load_xml(string
            => $self->xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    for my $if ($doc->findnodes('/domain/devices/interface/source')) {
        return 1 if $if->getAttribute('network');
    }
    return 0;
}

1;
