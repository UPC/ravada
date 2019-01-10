package Ravada::Domain::Void;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use Fcntl qw(:flock SEEK_END);
use File::Copy;
use File::Path qw(make_path);
use File::Rsync;
use Hash::Util qw(lock_keys);
use IPC::Run3 qw(run3);
use Moose;
use YAML qw(Load Dump  LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

extends 'Ravada::Front::Domain::Void';
with 'Ravada::Domain';

has 'domain' => (
    is => 'rw'
    ,isa => 'Str'
    ,required => 1
);

has '_ip' => (
    is => 'rw'
    ,isa => 'Str'
    ,default => sub { return '1.1.1.'.int rand(255)}
);

our %CHANGE_HARDWARE_SUB = (
    disk => \&_change_hardware_disk
);

our $CONVERT = `which convert`;
chomp $CONVERT;
#######################################3

sub BUILD {
    my $self = shift;

    my $args = $_[0];

    my $drivers = {};
    if ($args->{id_base}) {
        my $base = Ravada::Domain->open($args->{id_base});

        confess "ERROR: Wrong base ".ref($base)." ".$base->type
                ."for domain in vm ".$self->_vm->type
            if $base->type ne $self->_vm->type;
        $drivers = $base->_value('drivers');
    }
    if ( ! -e $self->_config_file ) {
        $self->_set_default_info();
        $self->_store( autostart => 0 );
        $self->_store( drivers => $drivers );
    }
    $self->set_memory($args->{memory}) if $args->{memory};
}

sub name { 
    my $self = shift;
    return $self->domain;
};

sub display_info {
    my $self = shift;

    my $ip = ($self->_vm->nat_ip or $self->_vm->ip());
    my $display="void://$ip:5990/";
    return { display => $display , type => 'void', address => $ip, port => 5990 };
}

sub is_active {
    my $self = shift;
    return ($self->_value('is_active') or 0);
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
    $self->_vm->run_command("/bin/rm",$self->_config_file());
    $self->_vm->run_command("/bin/rm",$self->_config_file().".lock");
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

sub _store {
    my $self = shift;

    return $self->_store_remote(@_) if !$self->_vm->is_local;

    my ($var, $value) = @_;

    my $data = $self->_load();
    $data->{$var} = $value;

    make_path($self->_config_dir()) if !-e $self->_config_dir;
    eval { DumpFile($self->_config_file(), $data) };
    chomp $@;
    confess $@ if $@;

}

sub _load($self) {
    return $self->_load_remote()    if !$self->is_local();
    my $data = {};

    my $disk = $self->_config_file();
    eval {
        $data = LoadFile($disk)   if -e $disk;
    };
    confess $@ if $@;

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

sub _lock {
    my ($fh) = @_;
    flock($fh, LOCK_EX) or die "Cannot lock - $!\n";
}

sub _unlock {
    my ($fh) = @_;
    flock($fh, LOCK_UN) or die "Cannot unlock - $!\n";
}

sub shutdown {
    my $self = shift;
    $self->_store(is_active => 0);
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

sub start {
    my $self = shift;
    $self->_store(is_active => 1);
}

sub prepare_base {
    my $self = shift;

    for my $file_qcow ($self->list_volumes) {;
        my $file_base = $file_qcow.".qcow";

        if ( $file_qcow =~ /.SWAP.img$/ ) {
            $file_base = $file_qcow;
            $file_base =~ s/(\.SWAP.img$)/base-$1/;
        }
        open my $out,'>',$file_base or die "$! $file_base";
        print $out "$file_qcow\n";
        close $out;
        $self->_prepare_base_db($file_base);
    }
}

sub list_disks {
    return disk_device(@_);
}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    if ($self->is_local) {
        unlink $file or die "$! $file"
            if -e $file;
    } else {
        my ($out, $err) = $self->_vm->run_command('ls',$file,'&&','rm',$file);
        warn $err if $err;
    }
}

sub remove_disks {
    my $self = shift;
    my @files = $self->list_disks;
    for my $file (@files) {
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

    my $suffix = ".img";
    $suffix = '.SWAP.img' if $args{swap};

    $args{name} = Ravada::Utils::random_name(4) if !$args{name};
    $args{file} = $self->_config_dir."/".$self->name.".$args{name}$suffix"
        if !$args{file};

    confess "Volume path must be absolute , it is '$args{file}'"
        if $args{file} !~ m{^/};

    $args{capacity} = delete $args{size} if exists $args{size} && ! exists $args{capacity};
    $args{capacity} = 1024 if !exists $args{capacity};

    my %valid_arg = map { $_ => 1 } ( qw( name capacity file vm type swap target allocation
        driver
    ));

    for my $arg_name (keys %args) {
        confess "Unknown arg $arg_name"
            if !$valid_arg{$arg_name};
    }

    $args{type} = 'file' if !$args{type};
    delete $args{vm}   if defined $args{vm};

    my $data = $self->_load();
    $args{target} = _new_target($data) if !$args{target};
    $args{driver} = 'foo' if !exists $args{driver};

    my $hardware = $data->{hardware};
    my $device = $hardware->{device};
    my $file = delete $args{file};
    push @$device, {
        name => $args{name}
        ,file => $file
        ,type => $args{type}
        ,target => $args{target}
        ,driver => $args{driver}
    };
    $hardware->{device} = $device;
    $self->_store(hardware => $hardware);

    delete @args{'name', 'target', 'driver'};
    $args{a} = 'a'x400;
    $self->_vm->write_file($file, Dump(\%args)),

    return $file;
}

sub remove_volume($self, $file) {
    confess "Missing file" if ! defined $file || !length($file);
    return if ! -e $file;
    unlink $file or die "$! $file";

    my $data = $self->_load();
    my $hardware = $data->{hardware};

    my @devices_new;
    for my $info (@{$hardware->{device}}) {
        next if $info->{file} eq $file;
        push @devices_new,($info);
    }
    $hardware->{device} = \@devices_new;
    $self->_store(hardware => $hardware);
}

sub _new_target {
    my $data = shift;
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

sub list_volumes {
    my $self = shift;
    my $all_data = $self->_load();
    my $data = $all_data->{hardware};

    return () if !exists $data->{device};
    my @vol;
    confess "Error in ".Dumper($self->name
        ,$data->{device}) if !ref($data->{device}) || ref($data->{device}) ne 'ARRAY';
    for my $dev (@{$data->{device}}) {
        push @vol,($dev->{file})
            if ! exists $dev->{type}
                || $dev->{type} ne 'base';
    }
    die Dumper($data) if !@vol;
    return @vol;
}

sub list_volumes_info {
    my $self = shift;
    my $data = $self->_load();

    return () if !exists $data->{hardware}->{device};
    my @vol;
    for my $dev (@{$data->{hardware}->{device}}) {
        next if exists $dev->{type}
                && $dev->{type} eq 'base';

        my $info;
        eval { $info = LoadFile($dev->{file}) };
        confess "Error loading $dev->{file} ".$@ if $@;
        $info = {} if !defined $info;
        push @vol,({%$dev,%$info})
    }
    return @vol;

}

sub screenshot {
    my $self = shift;
    my $file = (shift or $self->_file_screenshot);

    my @cmd =($CONVERT,'-size', '400x300', 'xc:white'
        ,$file
    );
    my ($in,$out,$err);
    run3(\@cmd, \$in, \$out, \$err);
}

sub _file_screenshot {
    my $self = shift;
    return $self->_config_dir."/".$self->name.".png";
}

sub can_screenshot { return $CONVERT; }

sub get_info {
    my $self = shift;
    my $info = $self->_value('info');
    if (!$info->{memory}) {
        $info = $self->_set_default_info();
    }
    lock_keys(%$info);
    return $info;
}

sub _set_default_info {
    my $self = shift;
    my $info = {
            max_mem => 512*1024
            ,memory => 512*1024,
            ,cpu_time => 1
            ,n_virt_cpu => 1
            ,state => 'UNKNOWN'
            ,ip => $self->ip
    };
    $self->_store(info => $info);
    my %controllers = $self->list_controllers;
    for my $name ( sort keys %controllers) {
        next if $name eq 'disk';
        $self->set_controller($name,2);
    }
    return $info;
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

sub spinoff_volumes {
    return;
}

sub ip {
    my $self = shift;
    return $self->_ip;
}

sub clean_swap_volumes {
    my $self = shift;
    for my $file ($self->list_volumes) {
        next if $file !~ /SWAP.img$/;
        open my $out,'>',$file or die "$! $file";
        close $out;
    }
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
    $self->rsync(
           node => $node
        , files => [$self->_config_file ]
       ,request => $request
    );
    $self->rsync($node);

}

sub is_removed {
    my $self = shift;
    return !-e $self->_config_file();
}

sub autostart {
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

    my $list = ( $hardware->{$name} or [] );

    $number = $#$list if !defined $number;

    if ($number > $#$list) {
        for ( $#$list+1 .. $number-1 ) {
            push @$list,("foo ".($_+1));
        }
    } else {
        $#$list = $number-1;
    }

    $hardware->{$name} = $list;
    $self->_store(hardware => $hardware );
}

sub _set_controller_disk($self, $data) {
    return $self->add_volume(%$data);
}

sub _remove_disk {
    my ($self, $index) = @_;
    confess "Index is '$index' not number" if !defined $index || $index !~ /^\d+$/;
    my @volumes = $self->list_volumes();
    $self->remove_volume($volumes[$index]);
}

sub remove_controller {
    my ($self, $name, $index) = @_;

    return $self->_remove_disk($index) if $name eq 'disk';

    my $hardware = $self->_value('hardware');
    my $list = ( $hardware->{$name} or [] );

    my @list2 ;
    for my $count ( 0 .. $#$list ) {
        if ( $count == $index ) {
            next;
        }
        push @list2, ( $list->[$count]);
    }
    $hardware->{$name} = \@list2;
    $self->_store(hardware => $hardware );
}

sub _change_driver_disk($self, $index, $driver) {
    my $hardware = $self->_value('hardware');
    $hardware->{device}->[$index]->{driver} = $driver;

    $self->_store(hardware => $hardware);
}

sub _change_hardware_disk($self, $index, $data_new) {
    my @volumes = $self->list_volumes();

    my $driver = delete $data_new->{driver};
    return $self->_change_driver_disk($index, $driver) if $driver;

    my $file = $volumes[$index]
        or die "Error: volume $index not found, only ".scalar(@volumes)." found.";

    my $data;
    if ($self->is_local) {
        $data = LoadFile($file);
    } else {
        my ($lines, $err) = $self->_vm->run_command("cat $file");
        $data = Load($lines);
    }

    for (keys %$data_new) {
        $data->{$_} = $data_new->{$_};
    }
    $self->_vm->write_file($file, Dump($data));
}

sub change_hardware($self, $hardware, $index, $data) {
    my $sub = $CHANGE_HARDWARE_SUB{$hardware};
    return $sub->($self, $index, $data) if $sub;

    my $hardware_def = $self->_value('hardware');

    my $devices = $hardware_def->{$hardware};

    die "Error: Missing hardware $hardware\[$index], only ".scalar(@$devices)." found"
        if $index > scalar(@$devices);

    for (keys %$data) {
        $hardware_def->{$hardware}->[$index]->{$_} = $data->{$_};
    }
    $self->_store(hardware => $hardware_def );
}

1;
