package Ravada::Domain::Void;

use warnings;
use strict;

use Carp qw(carp cluck croak);
use Data::Dumper;
use Fcntl qw(:flock SEEK_END);
use File::Copy;
use File::Path qw(make_path);
use File::Rsync;
use Hash::Util qw(lock_keys lock_hash unlock_hash);
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json);
use Moose;
use YAML qw(Load Dump  LoadFile DumpFile);
use Image::Magick;
use MIME::Base64;

use Ravada::Volume;

no warnings "experimental::signatures";
use feature qw(signatures);

extends 'Ravada::Front::Domain::Void';
with 'Ravada::Domain';

has 'domain' => (
    is => 'rw'
    ,isa => 'Str'
    ,required => 1
);

our %CHANGE_HARDWARE_SUB = (
    disk => \&_change_hardware_disk
    ,vcpus => \&_change_hardware_vcpus
    ,memory => \&_change_hardware_memory
);

our $FREE_PORT = 5900;
#######################################3

sub name {
    my $self = shift;
    return $self->domain;
};

sub display_info {
    my $self = shift;

    my $hardware = $self->_value('hardware');
    return if !exists $hardware->{display} || !exists $hardware->{display}->[0];

    my @display;
    for my $graph ( @{$hardware->{display}} ) {
        $graph->{extra} = {};
        eval {
        $graph->{extra} = decode_json($graph->{extra})
        if exists $graph->{extra} && $graph->{extra};
        };

        $graph->{is_builtin} = 1;
        $graph->{port} = undef if $graph->{port} && $graph->{port} eq 'auto';
        push @display,($graph);
    }

    return $display[0] if !wantarray;
    return @display;
}

sub _has_builtin_display($self) {
    my $hardware = $self->_value('hardware');

    return 1 if exists $hardware->{display} && exists $hardware->{display}->[0]
    && defined $hardware->{display}->[0];

    return 0;
}

sub _is_display_builtin($self, $index=undef, $data=undef) {
    confess if defined $index && $index =~ /\./;
    if (defined $index && $index !~ /^\d+$/i) {
        return 1 if $index =~ /spice|void/;
        return 0;
    }
    my $hardware = $self->_value('hardware');

    return 1 if defined $data && exists $data->{driver} && $data->{driver} =~ /void|spice/;
    return 1 if defined $index
    && ( exists $hardware->{display} && exists $hardware->{display}->[$index]);

    return 0;
}

sub _file_free_port() {
    my $user = $<;
    $user = "root" if !$<;

    my $dir_fp  = "/run/user/$user";
    mkdir $dir_fp if ! -e $dir_fp;
    return "/$dir_fp/void_free_port.txt";

}

sub  _reset_free_port(@) {
    my $file_fp = _file_free_port();
    unlink $file_fp or die $! if -e $file_fp;
}

sub _new_free_port($self, $used={} ) {
    my $file_fp  = _file_free_port();

    my $n = $FREE_PORT;
    my $fh;
    open $fh,"<",$file_fp and do {
        $n = <$fh>;
        $n = $FREE_PORT if !$n;
    };
    close $fh;
    open $fh,">",$file_fp or die "$! $file_fp";
    _lock($fh);

    for ( 0 .. 1000 ) {
        for my $domain ( $self->_vm->list_domains()) {
            my $hardware = $domain->_value('hardware');
            for my $display (@{$hardware->{display}}) {
                my $port = $display->{port};
                $used->{$port}=$domain->name.".$display->{driver}" if $port;
                my $port_tls = $display->{extra}->{tls_port};
                $used->{$port_tls}=$domain->name if $port_tls;
            }
        }
        my $sth = $self->_dbh->prepare("SELECT d.name,dd.port,extra,driver FROM domain_displays dd,domains d WHERE d.id=dd.id_domain AND is_builtin=1  ");
        $sth->execute;
        while ( my ($name,$port, $extra, $driver) = $sth->fetchrow ) {
            next if !$port;
            my $extra_json = {};
            eval { $extra_json = decode_json($extra) } if $extra;
            $used->{$port}=$name.".dd.$driver";
            my $tls_port = $extra_json->{tls_port};
            $used->{$tls_port}=$name if defined $tls_port;
        }

        last if !$used->{$n};
        $n++;
    }
    print $fh $n;
    _unlock($fh);
    close $fh;
    return $n;
}

sub _set_display($self, $listen_ip=$self->_vm->listen_ip) {
    $listen_ip=$self->_vm->listen_ip if !$listen_ip;
    #    my $ip = ($self->_vm->nat_ip or $self->_vm->ip());
    my $port = 'auto';
    $port = $self->_new_free_port() if $self->is_active();
    my $display_data = { driver => 'void', ip => $listen_ip, port =>$port
        , is_builtin => 1
        , xistorra => 1
    };
    my $hardware = $self->_value('hardware');
    $hardware->{display}->[0] = $display_data;
    $self->_store( hardware => $hardware);
    return $display_data;
}

sub _set_displays_ip($self, $password=undef, $listen_ip=$self->_vm->listen_ip) {
    my $hardware = $self->_value('hardware');
    my $is_active = $self->is_active();
    my %used_ports;
    for my $display (@{$hardware->{'display'}}) {
        next unless exists $display->{port} && $display->{port} && $display->{port} ne 'auto';
        my $port = $display->{port};
        $used_ports{$port}++;
    }
    for my $display (@{$hardware->{'display'}}) {
        $display->{ip} = $listen_ip;

        $display->{port} = $self->_new_free_port(\%used_ports)
        if $is_active && ( !$display->{port} || $display->{port} eq 'auto' );

        $display->{password} = $password if defined $password;
        $used_ports{$display->{port}}++;
    }
    $self->_store( hardware => $hardware );
}

sub is_active {
    my $self = shift;
    my $ret = 0;
    eval {
        $ret = $self->_value('is_active') ;
        $ret = 0 if !defined $ret;
    };
    return $ret if !$@;
    return 0 if $@ =~ /Error connecting|can't connect/;
    warn $@;
    die $@;
}

sub pause {
    my $self = shift;
    $self->_store(is_paused => 1);
}

sub resume {
    my $self = shift;
    return $self->_store(is_paused => 0 );
}

sub remove {
    my $self = shift;

    $self->remove_disks();

    my $config_file = $self->_config_file;
    if ($self->_vm->file_exists($config_file)) {
        my ($out, $err) = $self->_vm->run_command("/bin/rm",$config_file);
        warn $err if $err;
    }
    if ($self->_vm->file_exists($config_file.".lock")) {
        $self->_vm->run_command("/bin/rm",$config_file.".lock");
    }
}

sub can_hibernate { return 1; }
sub can_hybernate { return 1; }

sub is_hibernated {
    my $self = shift;
    return $self->_value('is_hibernated');
}

sub is_paused {
    my $self = shift;

    return $self->_value('is_paused');
}

sub _check_value_disk($self, $value)  {
    return if !exists $value->{device};

    my %target;
    my %file;

    confess "Not hash ".ref($value)."\n".Dumper($value) if ref($value) ne 'HASH';

    for my $device (@{$value->{device}}) {
        confess "Error: device without target ".$self->name." ".Dumper($device)
        if !exists $device->{target};

        confess "Duplicated target ".Dumper($value)
            if $target{$device->{target}}++;

        confess "Duplicated file" .Dumper($value)
            if exists $device->{file} && $file{$device->{file}}++;
    }
}

sub _store {
    my $self = shift;

    return $self->_store_remote(@_) if !$self->_vm->is_local;

    my ($var, $value) = @_;

    $self->_check_value_disk($value) if $var eq 'hardware';

    my $file_lock = $self->_config_file().".lock";

    my ($path) = $file_lock =~ m{(.*)/};
    make_path($path) or die "Error creating $path"
    if ! -e $path;

    open my $lock,">>",$file_lock or die "Can't open $file_lock";
    _lock($lock);

    my $data = $self->_load();
    $data->{$var} = $value;

    make_path($self->_config_dir()) if !-e $self->_config_dir;
    eval { DumpFile($self->_config_file(), $data) };
    chomp $@;
    _unlock($lock);
    confess $@ if $@;

}

sub _load($self) {
    return $self->_load_remote()    if !$self->is_local();
    my $data = {};

    my $disk = $self->_config_file();
    eval {
        $data = LoadFile($disk)   if -e $disk;
    };
    confess "Error in $disk: $@" if $@;

    return $data;
}


sub _load_remote($self) {
    my ($disk) = $self->_config_file();

    my ($lines, $err) = $self->_vm->run_command("cat $disk");

    return Load($lines);
}

sub _store_remote($self, $var, $value) {
    my ($disk) = $self->_config_file();

    my $data = $self->_load_remote();
    $data->{$var} = $value;

    open my $lock,">>","$disk.lock" or die "I can't open lock: $disk.lock: $!";
    _lock($lock);
    $self->_vm->run_command("mkdir","-p ".$self->_config_dir);
    $self->_vm->write_file($disk, Dump($data));

    _unlock($lock);
    unlink("$disk.lock");
    return $self->_value($var);
}

sub _value($self,$var){

    my $data = $self->_load();
    return $data->{$var};

}

sub _lock($fh) {
    flock($fh, LOCK_EX) or die "Cannot lock - $!\n";
}

sub _unlock($fh) {
    flock($fh, LOCK_UN) or die "Cannot unlock - $!\n";
}

sub shutdown {
    my $self = shift;
    $self->_store(is_active => 0);
    my $hardware = $self->_value('hardware');
    for my $display (@{$hardware->{'display'}}) {
        $display->{port} = 'auto';
    }
    $self->_store(hardware => $hardware);
}

sub force_shutdown {
    return shutdown_now(@_);
}

sub _do_force_shutdown {
    my $self = shift;
    return $self->_store(is_active => 0);
}

sub shutdown_now {
    my $self = shift;
    my $user = shift;
    return $self->shutdown(user => $user);
}

sub reboot {
    my $self = shift;
    $self->_store(is_active => 0);
}

sub force_reboot {
    return reboot_now(@_);
}

sub _do_force_reboot {
    my $self = shift;
    return $self->_store(is_active => 0);
}

sub reboot_now {
    my $self = shift;
    my $user = shift;
    return $self->reboot(user => $user);
}

sub start($self, @args) {
    my %args;
    %args = @args if scalar(@args) % 2 == 0;
    my $listen_ip = delete $args{listen_ip};
    my $remote_ip = delete $args{remote_ip};
    my $set_password = delete $args{set_password}; # unused
    my $user = delete $args{user};
    delete $args{'id_vm'};
    confess "Error: unknown args ".Dumper(\%args) if keys %args;

    $listen_ip = $self->_vm->listen_ip($remote_ip) if !$listen_ip;

    $self->_store(is_active => 1);
    $self->_store(is_hibernated => 0);
    my $password;
    $password = Ravada::Utils::random_name() if $set_password;
    $self->_set_displays_ip( $password, $listen_ip );
    $self->_set_ip_address();

}

sub _set_ip_address($self) {
    return if !$self->is_active;

    my $hardware = $self->_value('hardware');
    my $changed = 0;
    for my $net (@{$hardware->{network}}) {
        next if !ref($net);
        next if exists $net->{address} && $net->{address};
        next if $net->{type} ne 'nat';
        $net->{address} = '198.51.100.'.int(rand(253)+2);
        $changed++;
    }
    $self->_store('hardware' => $hardware) if $changed;

}

sub list_disks {
    my @disks;
    for my $disk ( list_volumes_info(@_)) {
        push @disks,( $disk->file) if $disk->type eq 'file';
    }
    return @disks;
}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    if ($self->is_local) {
        unlink $file or die "$! $file"
            if -e $file;
    } else {
        return if !$self->_vm->file_exists($file);
        my ($out, $err) = $self->_vm->run_command('ls',$file,'&&','rm',$file);
        warn $err if $err;
    }
}

sub remove_disks {
    my $self = shift;
    my @files = $self->list_volumes_info;
    for my $vol (@files) {
        my $file = $vol->{file};
        my $device = $vol->info->{device};
        next if $device eq 'cdrom';
        next if $file =~ /\.iso$/;
        $self->_vol_remove($file);
    }

}

sub remove_disk {
    my $self = shift;
    return $self->_vol_remove(@_);
}

=head2 add_volume

Adds a new volume to the domain

    $domain->add_volume(capacity => $capacity);

=cut

sub add_volume {
    my $self = shift;
    confess "Wrong arguments " if scalar@_ % 1;

    my %args = @_;

    my $device = ( delete $args{device} or 'disk' );
    my $type = ( delete $args{type} or '');
    my $format = delete $args{format};

    if (!$format) {
        if ( $args{file}) {
            ($format) = $args{file} =~ /\.(\w+)$/;
        } else {
            $format = 'void';
        }
    }

    $type = 'swap' if $args{swap};
    $type = '' if $type eq 'sys';
    $type = uc($type)."."   if $type;

    my $suffix = $format;

    if ( !$args{file} ) {
        my $path = ( delete $args{path} or $self->_vm->dir_img);
        my $vol_name = ($args{name} or Ravada::Utils::random_name(4) );
        $args{file} = "$path/$vol_name";
        $args{file} .= ".$type$suffix" if $args{file} !~ /\.\w+$/;
    }

    ($args{name}) = $args{file} =~ m{.*/(.*)};

    confess "Volume path must be absolute , it is '$args{file}'"
        if $args{file} !~ m{^/};

    $args{capacity} = delete $args{size} if exists $args{size} && ! exists $args{capacity};
    $args{capacity} = 1024 if !exists $args{capacity};

    my %valid_arg = map { $_ => 1 } ( qw( name capacity file vm type swap target allocation
        bus boot
    ));

    for my $arg_name (keys %args) {
        confess "Unknown arg $arg_name"
            if !$valid_arg{$arg_name};
    }

    $args{type} = 'file' if !$args{type};
    delete $args{vm}   if defined $args{vm};

    my $data = $self->_load();
    $args{target} = $self->_new_target() if !$args{target};
    $args{bus} = 'foo' if !exists $args{bus};

    my $hardware = $data->{hardware};
    my $device_list = $hardware->{device};
    my $file = delete $args{file};
    my $data_new = {
        name => $args{name}
        ,file => $file
        ,type => $args{type}
        ,target => $args{target}
        ,bus => $args{bus}
        ,device => $device
    };
    $data_new->{boot} = $args{boot} if $args{boot};
    push @$device_list, $data_new;
    $hardware->{device} = $device_list;
    $self->_store(hardware => $hardware);

    delete @args{'name', 'target', 'bus'};
    $self->_create_volume($file, $format, \%args) if ! -e $file;

    return $file;
}

sub _create_volume($self, $file, $format, $data=undef) {
    confess "Undefined format" if !defined $format;
    if ($format =~ /iso|raw|void/) {
        $data->{format} = $format;
        $self->_vm->write_file($file, Dump($data)),
    } elsif ($format eq 'qcow2') {
        my @cmd = ('qemu-img','create','-f','qcow2', $file, $data->{capacity});
        my ($out, $err) = $self->_vm->run_command(@cmd);
        confess $err if $err;
    } else {
        confess "Error: unknown format '$format'";
    }
}

sub remove_volume($self, $file) {
    confess "Missing file" if ! defined $file || !length($file);

    $self->_vol_remove($file);
}

sub _remove_controller_disk($self,$index) {
    return if ! $self->_vm->file_exists($self->_config_file);
    my $data = $self->_load();
    my $hardware = $data->{hardware};

    my @devices_new;
    my $n = 0;
    for my $info (@{$hardware->{device}}) {
        next if $n++ == $index;
        push @devices_new,($info);
    }
    $hardware->{device} = \@devices_new;
    $self->_store(hardware => $hardware);
}

sub _new_target_dev { return _new_target(@_) }

sub _new_target($self) {
    my $data = $self->_load();
    return 'vda'    if !$data or !keys %$data;
    my %targets;
    for my $dev ( @{$data->{hardware}->{device}}) {
        confess "Missing device ".Dumper($data) if !$dev;

        my $target = $dev->{target};
        confess "Missing target ".Dumper($data) if !$target || !length($target);

        $targets{$target}++
    }
    return 'vda'    if !keys %targets;

    my @targets = sort keys %targets;
    my ($prefix,$a) = $targets[-1] =~ /(.*)(.)/;
    confess "ERROR: Missing prefix ".Dumper($data)."\n"
        .Dumper(\%targets) if !$prefix;
    return $prefix.chr(ord($a)+1);
}

sub create_swap_disk {
    my $self = shift;
    my $path = shift;

    return if -e $path;

    open my $out,'>>',$path or die "$! $path";
    close $out;

}

sub _rename_path {
    my $self = shift;
    my $path = shift;

    my $new_name = $self->name;

    my $cnt = 0;
    my ($dir,$ext) = $path =~ m{(.*)/.*?\.(.*)};
    for (;;) {
        my $new_path = "$dir/$new_name.$ext";
        return $new_path if ! -e $new_path;

        $new_name = $self->name."-$cnt";
    }
}

sub disk_device {
    return list_volumes(@_);
}

sub list_volumes($self, $attribute=undef, $value=undef) {
    my $data = $self->_load();

    return () if !exists $data->{hardware}->{device};
    my @vol;
    my $n_order = 0;
    for my $dev (@{$data->{hardware}->{device}}) {
        next if exists $dev->{type}
                && $dev->{type} eq 'base';
        if (exists $dev->{file} ) {
            confess "Error loading $dev->{file} ".$@ if $@;
            next if defined $attribute
                && (!exists $dev->{$attribute} || $dev->{$attribute} ne $value);
        }
        push @vol,($dev->{file});
    }
    return @vol;

}

sub list_volumes_info($self, $attribute=undef, $value=undef) {
    my $data = $self->_load();

    return () if !exists $data->{hardware}->{device};
    my @vol;
    my $n_order = 0;
    for my $dev (@{$data->{hardware}->{device}}) {
        next if exists $dev->{type}
                && $dev->{type} eq 'base';

        if (exists $dev->{file} ) {
            confess "Error loading $dev->{file} ".$@ if $@;
            next if defined $attribute
                && (!exists $dev->{$attribute} || $dev->{$attribute} ne $value);
        }
        $dev->{n_order} = $n_order++;
        $dev->{driver}->{type} = 'void';
        my $vol = Ravada::Volume->new(
            file => $dev->{file}
            ,info => $dev
            ,domain => $self
        );
        push @vol,($vol);
    }
    return @vol;

}

sub screenshot {
    my $self = shift;
    my $DPI = 300; # 600;
    my $image = Image::Magick->new(density => $DPI,width=>250, height=>188);
    $image->Set(size=>'250x188');
    $image->ReadImage('canvas:#'.int(rand(10)).int(rand(10)).int(rand(10)));
    my @blobs = $image->ImageToBlob(magick => 'png');
    $self->_data(screenshot => encode_base64($blobs[0]));
}

sub _file_screenshot {
    my $self = shift;
    return $self->_config_dir."/".$self->name.".png";
}

sub can_screenshot { return 1 }

sub get_info {
    my $self = shift;
    my $info = $self->_value('info');
    if (!$info->{memory}) {
        $info = $self->_set_default_info();
    }
    $info->{ip} = $self->ip;
    lock_keys(%$info);
    return $info;
}

sub _new_mac($mac='ff:54:00:a7:49:71') {
    my $num =sprintf "%02X", rand(0xff);
    my @macparts = split/:/,$mac;
    $macparts[5] = $num;
    return join(":",@macparts);
}

sub _set_default_info($self, $listen_ip=undef) {
    my $info = {
            max_mem => 512*1024
            ,memory => 512*1024,
            ,cpu_time => 1
            ,n_virt_cpu => 1
            ,state => 'UNKNOWN'
            ,mac => _new_mac()
            ,time => time
    };

    $self->_store(info => $info);
    $self->_set_display($listen_ip);
    my $hardware = $self->_value('hardware');

    $hardware->{network}->[0] = {
        hwaddr => $info->{mac}
        ,address => $info->{ip}
        ,type => 'nat'
    };
    $self->_store(hardware => $hardware );

    my %controllers = $self->list_controllers;
    for my $name ( sort keys %controllers) {
        next if $name eq 'disk' || $name eq 'display';
        $self->set_controller($name, 1) unless exists $hardware->{$name}->[0];
    }
    return $info;
}

sub set_time($self) {
    $self->_set_info(time => time );
}

sub set_max_memory {
    my $self = shift;
    my $value = shift;

    $self->_set_info(max_mem => $value);

}

sub set_memory {
    my $self = shift;
    my $value = shift;
    
    $self->_set_info(memory => $value );
}



sub set_driver {
    my $self = shift;
    my $name = shift;
    my $value = shift or confess "Missing value for driver $name";

    my $drivers = $self->_value('drivers');
    $drivers->{$name}= $value;
    $self->_store(drivers => $drivers);
}

sub _set_default_drivers {
    my $self = shift;
    $self->_store( drivers => { video => 'value=void'});
}

sub set_max_mem {
    $_[0]->_set_info(max_mem => $_[1]);
}

sub _set_info {
    my $self = shift;
    my ($field, $value) = @_;
    my $info = $self->get_info();
    confess "Unknown field $field" if !exists $info->{$field};

    unlock_hash(%$info);
    $info->{$field} = $value;
    $self->_store(info => $info);
}

=head2 rename

    $domain->rename("new_name");

=cut

sub rename {
    my $self = shift;
    my %args = @_;
    my $new_name = $args{name};

    my $file_yml = $self->_config_file();

    my $file_yml_new = $self->_config_dir."/$new_name.yml";
    copy($file_yml, $file_yml_new) or die "$! $file_yml -> $file_yml_new";
    unlink($file_yml);

    $self->domain($new_name);
}

sub disk_size {
    my $self = shift;
    my ($disk) = $self->list_volumes();
    return -s $disk;
}

sub ip {
    my $self = shift;
    my $hardware = $self->_value('hardware');
    return if !exists $hardware->{network};
    for ( 1 .. 2 ) {
        for my $network(@{$hardware->{network}}) {
            return $network->{address}
            if ref($network) && $network->{address};
        }

        $self->_set_ip_address();
    }

    return;
}

sub clean_disk($self, $file) {
    open my $out,'>',$file or die "$! $file";
    close $out;
}

sub hybernate {
    my $self = shift;
    $self->_store(is_hibernated => 1);
    $self->_store(is_active => 0);
}

sub hibernate($self, $user) {
    $self->hybernate( $user );
}

sub type { 'Void' }

sub migrate($self, $node, $request=undef) {
    $self->_set_displays_ip(undef, $node->ip);
    my $config_remote;
    $config_remote = $self->_load();
    my $device = $config_remote->{hardware}->{device}
        or confess "Error: no device hardware in ".Dumper($config_remote);
    my @device_remote;
    for my $item (@$device) {
        push @device_remote,($item) if $item->{device} ne 'cdrom';
    }
    $config_remote->{hardware}->{device} = \@device_remote;
    $node->write_file($self->_config_file, Dump($config_remote));
    $self->rsync($node);

}

sub is_removed {
    my $self = shift;

    return !-e $self->_config_file()    if $self->is_local();

    my ($out, $err) = $self->_vm->run_command("/usr/bin/test",
         " -e ".$self->_config_file." && echo 1" );
    chomp $out;
    warn $self->name." ".$self->_vm->name." ".$err if $err;

    return 0 if $out;
    return 1;
}

sub autostart { return _internal_autostart(@_) }

sub _internal_autostart {
    my $self = shift;
    my $value = shift;

    if (defined $value) {
        $self->_store(autostart => $value);
    }
    return $self->_value('autostart');
}

sub set_controller($self, $name, $number=undef, $data=undef) {
    my $hardware = $self->_value('hardware');

    return $self->_set_controller_disk($data) if $name eq 'disk';

    $data->{listen_ip} = $self->_vm->listen_ip if $name eq 'display'&& !$data->{listen_ip};

    my $list = ( $hardware->{$name} or [] );

    confess "Error: hardware $number already added ".Dumper($list)
    if defined $number && $number < scalar(@$list);

    $#$list = $number-1 if defined $number && scalar @$list < $number;

    my @list2;
    if (!defined $number) {
        @list2 = @$list;
        push @list2,($data or " $name z 1");
    } else {
        my $count = 0;
        for my $item ( @$list ) {
            $count++;
            if ($number == $count) {
                my $data2 = ( $data or " $name a ".($count+1));
                $data2 = " $name b ".($count+1) if defined $data2 && ref($data2) && !keys %$data2;

                push @list2,($data2);
                next if !defined $item;
            }
            $item = { driver => 'spice' , port => 'auto' , listen_ip => $self->_vm->listen_ip }
            if $name eq 'display' && !defined $item;
            push @list2,($item or " $name b ".($count+1));
        }
    }
    $hardware->{$name} = \@list2;
    $self->_store(hardware => $hardware );
}

sub _set_controller_disk($self, $data) {
    return $self->add_volume(%$data);
}

sub _remove_disk {
    my ($self, $index) = @_;
    confess "Index is '$index' not number" if !defined $index || $index !~ /^\d+$/;
    my @volumes = $self->list_volumes();
    $self->remove_volume($volumes[$index])
        if $volumes[$index] && $volumes[$index] !~ /\.iso$/;
    $self->_remove_controller_disk($index);
}

sub remove_controller {
    my ($self, $name, $index) = @_;

    return $self->_remove_disk($index) if $name eq 'disk';

    my $hardware = $self->_value('hardware');
    my $list = ( $hardware->{$name} or [] );
    die "Error: $name $index not removed, only ".$#$list." found" if $index>$#$list;

    my @list2 ;
    my $found;
    for my $count ( 0 .. $#$list ) {
        if ( $count == $index ) {
            $found = $count;
            next;
        }
        push @list2, ( $list->[$count]);
    }
    $hardware->{$name} = \@list2;
    $self->_store(hardware => $hardware );
}

sub _change_driver_disk($self, $index, $driver) {
    my $hardware = $self->_value('hardware');
    $hardware->{device}->[$index]->{bus} = $driver;

    $self->_store(hardware => $hardware);
}

sub _change_disk_data($self, $index, $field, $value) {
    my $hardware = $self->_value('hardware');
    if (defined $value && length $value ) {
        $hardware->{device}->[$index]->{$field} = $value;
    } else {
        delete $hardware->{device}->[$index]->{$field};
    }

    $self->_store(hardware => $hardware);
}

sub _change_hardware_disk($self, $index, $data_new) {
    my @volumes = $self->list_volumes_info();

    unlock_hash(%$data_new);
    my $driver;
    $driver = delete $data_new->{bus} if exists $data_new->{bus};
    lock_hash(%$data_new);
    return $self->_change_driver_disk($index, $driver) if $driver;

    die "Error: volume $index not found, only ".scalar(@volumes)." found."
        if $index >= scalar(@volumes);

    my $file = $volumes[$index]->{file};
    my $new_file;
    $new_file = $data_new->{file} if exists $data_new->{file};
    return $self->_change_disk_data($index, file => $new_file) if defined $new_file;

    return if !$file;
    my $data;
    if ($self->is_local) {
        eval { $data = LoadFile($file) };
        confess "Error reading file $file : $@" if $@;
    } else {
        my ($lines, $err) = $self->_vm->run_command("cat $file");
        $data = Load($lines);
    }

    for (keys %$data_new) {
        $data->{$_} = $data_new->{$_};
    }
    $self->_vm->write_file($file, Dump($data));
}

sub _change_hardware_vcpus($self, $index, $data) {
    my $n = delete $data->{n_virt_cpu};
    confess "Error: unknown args ".Dumper($data) if keys %$data;

    my $info = $self->_value('info');
    $info->{n_virt_cpu} = $n;
    $self->_store(info => $info);
}

sub _change_hardware_memory($self, $index, $data) {
    unlock_hash(%$data);
    my $memory = delete $data->{memory};
    my $max_mem = delete $data->{max_mem};
    confess "Error: unknown args ".Dumper($data) if keys %$data;

    my $info = $self->_value('info');
    if (defined $memory && $info->{memory} != $memory) {
        $info->{memory} = $memory;
    }

    if (defined $max_mem && $info->{max_mem} != $max_mem) {
        $info->{max_mem} = $max_mem;
        $self->needs_restart(1);
    }

    $self->_store(info => $info);
}


sub change_hardware($self, $hardware, $index, $data) {
    my $sub = $CHANGE_HARDWARE_SUB{$hardware};
    return $sub->($self, $index, $data) if $sub;

    my $hardware_def = $self->_value('hardware');

    my $devices = $hardware_def->{$hardware};
    confess "Error: $hardware not found ".Dumper($hardware_def) if !$devices;

    die "Error: Missing hardware $hardware\[$index], only ".scalar(@$devices)." found"
        if $index > scalar(@$devices);

    for (keys %$data) {
        $hardware_def->{$hardware}->[$index]->{$_} = $data->{$_};
    }
    $self->_store(hardware => $hardware_def );
}

sub dettach($self,$user) {
    # no need to do anything to dettach mock volumes
}

sub _check_port($self,@args) {
    return 1 if $self->is_active;
    return 0;
}

sub copy_config($self, $domain) {
    my $config_new = $domain->_load();
    for my $field ( keys %$config_new ) {
        my $value = $config_new->{$field};
        $value = 0 if $field eq 'is_active';
        $self->_store($field, $value);
    }
}

sub add_config_node($self, $path, $content, $data) {
    my $content_hash;
    eval { $content_hash = Load($content) };
    confess $@."\n$content" if $@;

    $data->{hardware}->{host_devices} = []
    if $path eq "/hardware/host_devices" && !exists $data->{hardware}->{host_devices};

    my $found = $data;
    for my $item (split m{/}, $path ) {
        next if !$item;

        confess "Error, no $item in ".Dumper($found)
        if !exists $found->{$item};

        $found = $found->{$item};
    }
    if (ref($found) eq 'ARRAY') {
        push @$found, ( $content_hash );
    } else {
        my ($item) = keys %$content_hash;
        $found->{$item} = $content_hash->{$item};
    }
}

sub remove_config_node($self, $path, $content, $data) {
    my $content_hash;
    eval { $content_hash = Load($content) };
    confess $@."\n$content" if $@;

    my $found = $data;
    my $found_parent;
    my $found_item;
    for my $item (split m{/}, $path ) {
        next if !$item;

        return if !exists $found->{$item};

        $found_parent = $found;
        $found_item = $item;
        $found = $found->{$item};
    }
    return if !$found;
    if (ref($found) eq 'ARRAY') {
        my @new_list;
        for my $item (@$found) {
            push @new_list,($item) unless _equal_hash($content_hash, $item);
        }
        $found_parent->{$found_item} = [@new_list];
        delete $found_parent->{$found_item} if (scalar(@new_list) == 0 );
    } else {
        my ($item) = keys %$content_hash;
        delete $found->{$item};
    }

}

sub _equal_hash($a,$b) {
    return 0 if scalar(keys(%$a)) != scalar(keys %$b);
    for my $key ( keys %$a) {
        return 0 if !exists $b->{$key} || $b->{$key} ne $a->{$key};
    }
    return 1;
}

sub add_config_unique_node($self, $path, $content, $data) {
    my $content_hash;
    eval { $content_hash = Load($content) };
    confess $@."\n$content" if $@;

    $data->{hardware}->{host_devices} = []
    if $path eq "/hardware/host_devices" && !exists $data->{hardware}->{host_devices};

    my $found = $data;
    for my $item (split m{/}, $path ) {
        next if !$item;

        confess "Error, no $item in ".Dumper($found)
        if !exists $found->{$item};

        $found = $found->{$item};
    }
    if (ref($found) eq 'ARRAY') {
        push @$found, ( $content_hash );
    } else {
        my ($item) = keys %$content_hash;
        $found->{$item} = $content_hash->{$item};
    }
}


sub can_host_devices { return 1 }

sub remove_host_devices($self) {
    my $data = $self->_load();
    my $hardware = $data->{hardware};

    my @devices2;
    my $changed = delete $hardware->{host_devices};
    return if !$changed;
    $self->_store( hardware => $hardware );
}

sub get_config($self) {
    return $self->_load();
}

sub reload_config($self, $data) {
    eval { DumpFile($self->_config_file(), $data) };
    confess $@ if $@;
}

sub has_nat_interfaces($self) {
    my $config = $self->_load();
    for my $if (@{$config->{hardware}->{network}}) {
        return 1 if exists $if->{type} && $if->{type} eq 'nat';
    }
    return 0;
}

sub config_files($self) {
    return $self->_config_file();
}

1;
