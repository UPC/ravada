package Ravada;

use warnings;
use strict;

our $VERSION = '2.4.0';

use utf8;

use Carp qw(carp croak cluck);
use Data::Dumper;
use DBIx::Connector;
use File::Copy;
use Hash::Util qw(lock_hash unlock_hash);
use IPC::Run3 qw(run3);
use Mojo::JSON qw( encode_json decode_json );
use Moose;
use POSIX qw(WNOHANG);
use Proc::PID::File;
use Time::HiRes qw(gettimeofday tv_interval);
use YAML;
use MIME::Base64;
use Socket qw( inet_aton inet_ntoa );
use Image::Magick::Q16;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Auth;
use Ravada::Booking;
use Ravada::Request;
use Ravada::Repository::ISO;
use Ravada::VM::Void;

our %VALID_VM;
our %ERROR_VM;
our $TIMEOUT_STALE_PROCESS;
our $TIMEOUT_REFRESH_REQUESTS = 0;

eval {
    require Ravada::VM::KVM and do {
        Ravada::VM::KVM->import;
    };
    $VALID_VM{KVM} = 1;
};
$ERROR_VM{KVM} = $@;

eval {
    require Ravada::VM::Void and do {
        Ravada::VM::Void->import;
    };
    $VALID_VM{Void} = 1;
};
$ERROR_VM{Void} = $@;

no warnings "experimental::signatures";
use feature qw(signatures);

our %VALID_CONFIG = (
    vm => undef
    ,warn_error => undef
    ,db => {user => undef, password => undef,  hostname => undef, host => undef, db => undef}
    ,ldap => { admin_user => { dn => undef, password => undef }
        ,filter => undef
        ,base => undef
        ,auth => undef
        ,admin_group => undef
        ,ravada_posix_group => undef
        ,groups_base => undef
        ,field => undef
        ,server => undef
        ,port => undef
        ,size_limit => undef
        ,secure => undef
    }
    ,sso => {
        service => undef
        ,logout => undef
        ,url => undef
        ,cookie => {
            pub_key => undef
            ,priv_key => undef
            ,type => undef
            ,timeout => undef
        }
    }
    ,log => undef
);

=head1 NAME

Ravada - Remote Virtual Desktop Manager

=head1 SYNOPSIS

  use Ravada;

  my $ravada = Ravada->new()

=cut


our $FILE_CONFIG = "/etc/ravada.conf";
$FILE_CONFIG = undef if ! -e $FILE_CONFIG;

###########################################################################

our $CONNECTOR;
our $CONFIG = {};
our $FORCE_DEBUG = 0;
our $DEBUG;
our $VERBOSE;
our $CAN_FORK = 1;
our $CAN_LXC = 0;

# Seconds to wait for other long process
our $SECONDS_WAIT_CHILDREN = 5;

our $DIR_SQL = "sql/mysql";
$DIR_SQL = "/usr/share/ravada/sql/mysql" if ! -e $DIR_SQL;

our $USER_DAEMON;
our $USER_DAEMON_NAME = 'daemon';

our $FIRST_TIME_RUN = 1;
$FIRST_TIME_RUN = 0 if $0 =~ /\.t$/;

has 'connector' => (
        is => 'rw'
);

has 'config' => (
    is => 'ro'
    ,isa => 'Str'
);

has 'warn_error' => (
    is => 'rw'
    ,isa => 'Bool'
    ,default => sub { 1 }
);

has 'pid_name' => (
    is => 'ro'
    ,isa => 'Str'
    , default => sub { 'ravada_install' }
);

=head2 BUILD

Internal constructor

=cut


sub BUILD {
    my $self = shift;
    if ($self->config()) {
        _init_config($self->config);
    } else {
        _init_config($FILE_CONFIG) if $FILE_CONFIG && -e $FILE_CONFIG;
    }

    if ( $self->connector ) {
        $CONNECTOR = $self->connector
    } else {
        $CONNECTOR = $self->_connect_dbh();
        $self->connector($CONNECTOR);
    }
    Ravada::Auth::init($CONFIG);

}

sub _set_first_time_run($self) {
    my $sth = $CONNECTOR->dbh->table_info('%',undef,'domains','TABLE');
    my $info = $sth->fetchrow_hashref();
    $sth->finish;
    if  ( keys %$info ) {
        $FIRST_TIME_RUN = 0;
    } else {
        print "Installing " if $0 !~ /\.t$/;
    }
}

sub _clean_tls($self) {
    my $sth = $CONNECTOR->dbh->prepare("UPDATE vms set tls=NULL");
    $sth->execute();
}

sub _install($self) {
    my $pid = Proc::PID::File->new(name => $self->pid_name);
    $pid->file({dir => "/run/user/$>"}) if $>;
    if ( $pid->alive ) {
        print "Waiting for install process to finish" if $ENV{TERM};
        while ( $pid->alive ) {
            sleep 1;
            print "." if $ENV{TERM};
        }
        print "\n" if $ENV{TERM};
        return;
    }
    $pid->touch;
    $self->_set_first_time_run();

    $self->_create_tables();
    $self->_sql_create_tables();
    $self->_upgrade_tables();
    $self->_upgrade_timestamps();
    $self->_update_data();
    $self->_init_user_daemon();
    $self->_sql_insert_defaults();

    $self->_do_create_constraints();
    $self->_add_internal_network();

    $pid->release();

    print "\n" if $FIRST_TIME_RUN;

}

sub _add_internal_network($self) {

    my $sth = $CONNECTOR->dbh->prepare("SELECT count(*) FROM domains");
    $sth->execute();
    my ($found) = $sth->fetchrow;
    return if $found;

    $sth = $CONNECTOR->dbh->prepare("SELECT * FROM networks WHERE name like 'internal%'");
    $sth->execute();
    ($found) = $sth->fetchrow;
    return if $found;

    my @cmd = ("ip","route");
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);

    warn $err if $err;

    $sth = $CONNECTOR->dbh->prepare("INSERT INTO networks "
        ."(name, address, n_order, all_domains, requires_password)"
        ." VALUES(?,?,?,1,0)"
    );
    my $n=0;
    my %done;
    for my $net (split /\n/,$out) {
        next if $net =~ /dev virbr/;
        my ($address) = $net =~ m{(^[\d\.]+/\d+)};
        next if !$address || $done{address}++;
        $sth->execute("internal$n",$address, ++$n+1);

    }
}

sub _do_create_constraints($self) {
    return if !$self->{_constraints};

    if ($CAN_FORK) {

        my $pid = fork();
        die "Error: I cannot fork" if !defined $pid;
        if ($pid) {
            $self->_add_pid($pid);
            return;
        }
    }

    my $pid_file = Proc::PID::File->new(name => "ravada_constraint");
    $pid_file->file({dir => "/run/user/$>"}) if $>;
    if ( $pid_file->alive ) {
        exit if $CAN_FORK;
        return;
    }
    $pid_file->touch;
    my $dbh = $CONNECTOR->dbh;

    my $known_constraints;

    for my $constraint (@{$self->{_constraints}}) {
        my ($table,$name) = $constraint =~ /ALTER TABLE (.*?) .*?CONSTRAINT (\w+)\s/i;
        if ( !defined $table ) {
            cluck "Warning: I can't find the table in this constraint: $constraint";
            next;
        }
        if (!exists $known_constraints->{$table}) {
            my $current = $self->_get_constraints($table);
            $known_constraints->{$table} = $current;
        }
        next if exists $known_constraints->{$table}->{$name};

        warn "INFO: creating constraint $name \n"
        if $name && !$FIRST_TIME_RUN && $0 !~ /\.t$/;
        print "+" if $FIRST_TIME_RUN && !$CAN_FORK;

        $self->_clean_db_leftovers();

        my $sth = $dbh->do($constraint);
    }
    $pid_file->release;
    exit if $CAN_FORK;
}

sub _init_user_daemon {
    my $self = shift;
    return if $USER_DAEMON;

    $USER_DAEMON = Ravada::Auth::SQL->new(name => $USER_DAEMON_NAME);
    if (!$USER_DAEMON->id) {
        for (1 .. 120 ) {
            my @list = $self->_list_pids();
            last if !@list;
            sleep 1 if @list;
            $self->_wait_pids();
        }
        $USER_DAEMON = Ravada::Auth::SQL->new(name => $USER_DAEMON_NAME);
        return if $USER_DAEMON->id;
        $USER_DAEMON = Ravada::Auth::SQL::add_user(
            name => $USER_DAEMON_NAME,
            is_admin => 1
        );
        $USER_DAEMON = Ravada::Auth::SQL->new(name => $USER_DAEMON_NAME);
    }

}
sub _update_user_grants {
    my $self = shift;
    $self->_init_user_daemon();
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM users WHERE is_temporary=0");
    my $id;
    $sth->execute;
    $sth->bind_columns(\$id);
    while ($sth->fetch) {
        my $user = Ravada::Auth::SQL->search_by_id($id) or confess "Unknown user id = $id";
        next if $user->name() eq $USER_DAEMON_NAME;

        my %grants = $user->grants();

        for my $key (keys %grants) {
            delete $grants{$key} if !defined $grants{$key};
        }
        next if keys %grants;

        $USER_DAEMON->grant_user_permissions($user);
        $USER_DAEMON->grant_admin_permissions($user)    if $user->is_admin;
    }
    $sth->finish;
}

sub _update_isos {
    my $self = shift;
    my $table = 'iso_images';
    my $field = 'name';
    my @now = localtime(time);
    my $year = $now[5]+1900;
    $year-- if $now[4]<2;
    my %data = (
	    androidx86 => {
                    name => 'Android 8.1 x86'
            ,description => 'Android-x86 64 bits. Requires an user provided ISO image.'
                   ,arch => 'x86_64'
                    ,xml => 'android-amd64.xml'
             ,xml_volume => 'android-volume.xml'
	     ,min_disk_size => '4'
        },
        arch_1909 => {
                    name => 'Arch Linux 19.09'
            ,description => 'Arch Linux 19.09.01 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'https://archive.archlinux.org/iso/2019.09.01/'
                    ,file_re => 'archlinux-2019.09.01-x86_64.iso'
                    ,md5_url => ''
                    ,md5 => '1d6bdf5cbc6ca98c31f02d23e418dd96'
        },
	mate_noble => {
                    name => 'Ubuntu Mate 24.04 Noble Numbat 64 bits'
            ,description => 'Ubuntu Mate 24.04 Noble Nubat m64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/24.04.*/release/ubuntu-mate-24.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                ,min_ram => 3
        },
	mate_jammy=> {
                    name => 'Ubuntu Mate 22.04 Jammy Jellyfish 64 bits'
            ,description => 'Ubuntu Mate 22.04 Jammy Jellyfish 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/22.04.*/release/ubuntu-mate-22.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                ,min_ram => 1
        },

	mate_focal_fossa => {
                    name => 'Ubuntu Mate 20.04 Focal Fossa 64 bits'
            ,description => 'Ubuntu Mate 20.04 (Focal Fossa) 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/20.04.*/release/ubuntu-mate-20.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                ,min_ram => 1
        },
        mate_bionic => {
                    name => 'Ubuntu Mate 18.04 Bionic 64 bits'
            ,description => 'Ubuntu Mate 18.04 (Bionic Beaver) 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/18.04.*/release/ubuntu-mate-18.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
                ,min_ram => 1
        },
        mate_bionic_i386 => {
                    name => 'Ubuntu Mate 18.04 Bionic 32 bits'
            ,description => 'Ubuntu Mate 18.04 (Bionic Beaver) 32 bits'
                   ,arch => 'i686'
                    ,xml => 'bionic-i386.xml'
             ,xml_volume => 'bionic32-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/18.04.*/release/ubuntu-mate-18.04.*-desktop-i386.iso'
                ,sha256_url => '$url/SHA256SUMS'
                ,min_ram => 1
        },
	,focal_fossa=> {
                    name => 'Ubuntu 20.04 Focal Fossa'
            ,description => 'Ubuntu 20.04 Focal Fossa 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/20.04/'
                ,file_re => '^ubuntu-20.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
          ,min_disk_size => '9'
          ,min_ram => 1
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                   ,arch => 'x86_64'
        }
        ,jammy_jellyfish => {
                    name => 'Ubuntu 22.04 Jammy Jellyfish'
            ,description => 'Ubuntu 22.04 Jammy Jellyfish 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/22.04/'
                ,file_re => '^ubuntu-22.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
          ,min_disk_size => '14'
          ,min_ram => 4
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                   ,arch => 'x86_64'

        }

        ,bionic=> {
                    name => 'Ubuntu 18.04 Bionic Beaver'
            ,description => 'Ubuntu 18.04 Bionic Beaver 64 bits'
                   ,arch => 'x86_64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/18.04/'
                ,file_re => '^ubuntu-18.04.*desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
          ,min_disk_size => '9'
                ,min_ram => 1
            ,arch => 'x86_64'
        }
        ,ubuntu_noble => {
                    name => 'Ubuntu 24.04 Noble Nombat'
            ,description => 'Ubuntu 24.04 Noble Nombat 64 bits'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/24.04/'
                ,file_re => '^ubuntu-24.04.*-desktop-amd64.iso'
                ,sha256_url => '$url/SHA256SUMS'
          ,min_disk_size => '14'
          ,min_ram => 4
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                   ,arch => 'x86_64'

        }


        
        ,mint20_64 => {
            name => 'Mint 20 Mate 64 bits'
    ,description => 'Mint 20 Ulyana with Mate Desktop 64 bits'
           ,arch => 'x86_64'
            ,xml => 'xenial64-amd64.xml'
     ,xml_volume => 'xenial64-volume.xml'
            ,url => 'https://mirrors.edge.kernel.org/linuxmint/stable/20.*'
        ,file_re => 'linuxmint-20.2-mate-64bit.iso'
        ,sha256_url => '$url/sha256sum.txt'
            ,min_disk_size => '15'
        }
        ,mint22_64 => {
            name => 'Mint 22 Mate 64 bits'
    ,description => 'Mint 22 Wilma with Mate Desktop 64 bits'
           ,arch => 'x86_64'
            ,xml => 'xenial64-amd64.xml'
     ,xml_volume => 'xenial64-volume.xml'
            ,url => 'https://mirrors.edge.kernel.org/linuxmint/stable/22.*'
        ,file_re => 'linuxmint-22.*-mate-64bit.iso'
        ,sha256_url => '$url/sha256sum.txt'
            ,min_disk_size => '15'
            ,min_ram => 2
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
        }

        ,alpine381_64 => {
            name => 'Alpine 3.16 64 bits'
    ,description => 'Alpine Linux 3.16 64 bits ( Minimal Linux Distribution )'
           ,arch => 'x86_64'
            ,xml => 'alpine-amd64.xml'
     ,xml_volume => 'alpine381_64-volume.xml'
            ,url => 'http://dl-cdn.alpinelinux.org/alpine/v3.16/releases/x86_64/'
        ,file_re => 'alpine-standard-3.16.*-x86_64.iso'
        ,sha256_url => '$url/alpine-standard-3.16.*.iso.sha256'
            ,min_disk_size => '2'
            ,options => { machine => 'pc-q35', bios => 'UEFI'
            }
        }
        ,alpine381_32 => {
            name => 'Alpine 3.16 32 bits'
    ,description => 'Alpine Linux 3.16 32 bits ( Minimal Linux Distribution )'
           ,arch => 'i686'
            ,xml => 'alpine-i386.xml'
     ,xml_volume => 'alpine381_32-volume.xml'
            ,url => 'http://dl-cdn.alpinelinux.org/alpine/v3.16/releases/x86/'
            ,options => { machine => 'pc-i440fx' }
        ,file_re => 'alpine-standard-3.16.*-x86.iso'
        ,sha256_url => '$url/alpine-standard-3.16.*.iso.sha256'
            ,min_disk_size => '1'
        }
	      ,kubuntu_64_noble => {
            name => 'Kubuntu 24.04 Noble Nombat'
            ,description => 'Kubuntu 22.04 Noble Nombat 64 bits'
            ,arch => 'x86_64'
            ,xml => 'focal_fossa-amd64.xml'
            ,xml_volume => 'focal_fossa64-volume.xml'
            ,sha256_url => '$url/SHA256SUMS'
            ,url => 'http://cdimage.ubuntu.com/kubuntu/releases/24.04.*/release/'
            ,file_re => 'kubuntu-24.04.*-desktop-amd64.iso'
            ,rename_file => 'kubuntu_noble.iso'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
            ,min_ram => 3
            ,min_disk_size => 11
        }

	      ,kubuntu_64_jammy => {
            name => 'Kubuntu 22.04 Jammy Jellyfish'
            ,description => 'Kubuntu 22.04 Jammy Jellyfish 64 bits'
            ,arch => 'x86_64'
            ,xml => 'focal_fossa-amd64.xml'
            ,xml_volume => 'focal_fossa64-volume.xml'
            ,sha256_url => '$url/SHA256SUMS'
            ,url => 'http://cdimage.ubuntu.com/kubuntu/releases/22.04.*/release/'
            ,file_re => 'kubuntu-22.04.*-desktop-amd64.iso'
            ,rename_file => 'kubuntu_jammy.iso'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
            ,min_ram => 3
            ,min_disk_size => 11
        }
	      ,kubuntu_64_focal_fossa => {
            name => 'Kubuntu 20.04 Focal Fossa 64 bits'
            ,description => 'Kubuntu 20.04 Focal Fossa 64 bits'
            ,arch => 'x86_64'
            ,xml => 'focal_fossa-amd64.xml'
            ,xml_volume => 'focal_fossa64-volume.xml'
            ,sha256_url => '$url/SHA256SUMS'
            ,url => 'http://cdimage.ubuntu.com/kubuntu/releases/20.04.*/release/'
            ,file_re => 'kubuntu-20.04.*-desktop-amd64.iso'
            ,rename_file => 'kubuntu_focal_fossa_64.iso'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
                ,min_ram => 1
        }
        ,suse_15 => {
            name => "openSUSE Leap 15"
            ,description => "openSUSE Leap 15 64 bits"
            ,arch => 'x86_64'
            ,xml => 'bionic-amd64.xml'
            ,xml_volume => 'bionic64-volume.xml'
            ,url => 'https://download.opensuse.org/distribution/leap/15.4/iso/'
            ,file_re => 'openSUSE-Leap-15.\d-NET-x86_64-Current.iso'

        }
        ,xubuntu_noble => {
            name => 'Xubuntu 24.04 Noble Nombat 64 bits'
            ,description => 'Xubuntu 24.04 Noble Nombat 64 bits'
            ,arch => 'x86_64'
            ,xml => 'bionic-amd64.xml'
            ,xml_volume => 'bionic64-volume.xml'
            ,url => 'https://ftp.lysator.liu.se/ubuntu-dvd/xubuntu/releases/24.04.*/release/'
            ,file_re => 'xubuntu.*desktop.*.iso'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
        }
        ,xubuntu_bionic => {
            name => 'Xubuntu 18.04 Bionic Beaver 32 bits'
            ,description => 'Xubuntu 18.04 Bionic Beaver 32 bits'
            ,arch => 'i686'
            ,xml => 'bionic-i386.xml'
            ,xml_volume => 'bionic32-volume.xml'
            ,md5_url => '$url/../MD5SUMS'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-i386/current/images/netboot/'
            ,file_re => 'mini.iso'
            ,rename_file => 'xubuntu_bionic_32.iso'
        }
        ,lubuntu_noble => {
            name => 'Lubuntu 24.04 Noble Nombat'
            ,description => 'Xubuntu 24.04 Noble Nombat 64 bits (LTS)'
            ,url => 'http://cdimage.ubuntu.com/lubuntu/releases/24.04.*/release/'
            ,file_re => 'lubuntu-24.04.*-desktop-amd64.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,xml => 'yakkety64-amd64.xml'
            ,xml_volume => 'yakkety64-volume.xml'
            ,min_disk_size => '10'
            ,arch => 'x86_64'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
        }
        ,debian_jessie_32 => {
            name =>'Debian 8 Jessie 32 bits'
            ,description => 'Debian 8 Jessie 32 bits'
            ,url => 'http://cdimage.debian.org/cdimage/archive/^8\.1\d+\.\d$/i386/iso-cd/'
            ,file_re => 'debian-8.[\d\.]+-i386-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,arch => 'i686'
        }
        ,debian_jessie_64 => {
            name =>'Debian 8 Jessie 64 bits'
            ,description => 'Debian 8 Jessie 64 bits'
            ,url => 'http://cdimage.debian.org/cdimage/archive/^8\.1\d+.*\d$/amd64/iso-cd/'
            ,file_re => 'debian-8.[\d\.]+-amd64-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,arch => 'x86_64'
        }
       ,debian_stretch_32 => {
            name =>'Debian 9 Stretch 32 bits'
            ,description => 'Debian 9 Stretch 32 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/^9\.1\d.*\d$/i386/iso-cd/'
            ,file_re => 'debian-9.[\d\.]+-i386-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,arch => 'i686'
        }
        ,debian_buster_64=> {
            name =>'Debian 10 Buster 64 bits'
            ,description => 'Debian 10 Buster 64 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/^10\.1\d+.*\d$/amd64/iso-cd/'
            ,file_re => 'debian-10.[\d\.]+-amd64-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,arch => 'x86_64'
        }
        ,debian_buster_32=> {
            name =>'Debian 10 Buster 32 bits'
            ,description => 'Debian 10 Buster 32 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/^10\.1\d+.*\d$/i386/iso-cd/'
            ,file_re => 'debian-10.[\d\.]+-i386-(netinst|xfce-CD-1).iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,arch => 'i686'
        }
        ,debian_bullseye_64=> {
            name =>'Debian 11 Bullseye 64 bits'
            ,arch => 'x86_64'
            ,description => 'Debian 11 Bullseye 64 bits (netinst)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/11.[\d\.]+/amd64/iso-cd/'
            ,file_re => 'debian-11.[\d\.]+-amd64-netinst.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
        }
        ,debian_bullseye_32=> {
            name =>'Debian 11 Bullseye 32 bits'
            ,arch => 'i686'
            ,description => 'Debian 11 Bullseye 32 bits (netinst)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/11[\d\.]+/i386/iso-cd/'
            ,file_re => 'debian-11.[\d\.]+-i386-netinst.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,options => { machine => 'pc-i440fx' }
        }
        ,debian_bookworm_64 => {
            name =>'Debian 12 Bookworm 64 bits'
            ,arch => 'x86_64'
            ,description => 'Debian 12 Bookworm 64 bits (netinst)'
            ,url => 'https://cdimage.debian.org/debian-cd/12[\.\d]+/amd64/iso-cd/'
            ,file_re => 'debian-12.[\d\.]+-amd64-netinst.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '11'
            ,min_ram => 3
            ,options => { machine => 'pc-q35', bios => 'UEFI' }
        }
        ,debian_bookworm_32 => {
            name =>'Debian 12 Bookworm 32 bits'
            ,arch => 'i686'
            ,description => 'Debian 12 Bookworm 32 bits (netinst)'
            ,url => 'https://cdimage.debian.org/debian-cd/12[\.\d]+/i386/iso-cd/'
            ,file_re => 'debian-12.[\d\.]+-i386-netinst.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '11'
            ,min_ram => 3
            ,options => { machine => 'pc-i440fx'}
        }

        ,devuan_beowulf_amd64=> {
            name =>'Devuan 10 Beowulf 64 bits'
            ,description => 'Devuan Beowulf Desktop Live (amd64)'
            ,arch => 'x86_64'
            ,url => 'http://tw1.mirror.blendbyte.net/devuan-cd/devuan_beowulf/desktop-live/'
            ,file_re => 'devuan_beowulf_.*_amd64_desktop-live.iso'
            ,sha256_url => '$url/SHASUMS.txt'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,devuan_beowulf_i386=> {
            name =>'Devuan 10 Beowulf 32 bits'
            ,description => 'Devuan Beowulf Desktop Live (i386)'
            ,arch => 'i686'
            ,url => 'http://tw1.mirror.blendbyte.net/devuan-cd/devuan_beowulf/desktop-live/'
            ,file_re => 'devuan_beowulf_.*_i386_desktop-live.iso'
            ,sha256_url => '$url/SHASUMS.txt'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,devuan_daedalus_amd64=> {
            name =>'Devuan 12 Daedalus 64 bits'
            ,description => 'Devuan Daedalus Desktop Live (amd64)'
            ,arch => 'x86_64'
            ,url => 'http://tw1.mirror.blendbyte.net/devuan-cd/devuan_daedalus/desktop-live/'
            ,file_re => 'devuan_daedalus_.*_amd64_desktop-live.iso'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
            ,options => { machine => 'pc-q35'}
        }
        ,devuan_daedalus_i386=> {
            name =>'Devuan 12 Daedalus 32 bits'
            ,description => 'Devuan Daedalus Desktop Live (i386)'
            ,arch => 'i686'
            ,url => 'http://tw1.mirror.blendbyte.net/devuan-cd/devuan_daedalus/desktop-live/'
            ,file_re => 'devuan_daedalus_.*_i386_desktop-live.iso'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }

        ,parrot_xfce_amd64 => {
            name => 'Parrot Home Edition XFCE'
            ,description => 'Parrot Home Edition XFCE 64 Bits'
            ,arch => 'x86_64'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,url => 'https://download.parrot.sh/parrot/iso/6.*/'
            ,file_re => 'Parrot-home-6.*_amd64.iso'
            ,sha256_url => ''
            ,min_disk_size => '11'
        }
        ,kali_64 => {
            name => "Kali Linux $year"
            ,description => "Kali Linux $year 64 Bits"
            ,arch => 'x86_64'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,url => "https://cdimage.kali.org/kali-$year".'.\d+.*/'
            ,file_re => "kali-linux-$year.".'\d+.*-installer-amd64.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,min_disk_size => '10'
        }
        ,kali_64_netinst => {
            name => "Kali Linux $year (NetInstaller)"
            ,description => "Kali Linux $year 64 Bits (light NetInstall)"
            ,arch => 'x86_64'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,url => "https://cdimage.kali.org/kali-$year".'.\d+.*/'
            ,file_re => "kali-linux-$year.".'\d+.*-installer-netinst-amd64.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,min_disk_size => '10'
        }
        ,windows_7 => {
          name => 'Windows 7'
          ,description => 'Windows 7 64 bits. Requires an user provided ISO image.'
            .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_7.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '21'
          ,arch => 'x86_64'
        }
        ,windows_10 => {
          name => 'Windows 10'
          ,description => 'Windows 10 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_10.xml'
          ,xml_volume => 'windows10-volume.xml'
          ,min_disk_size => '21'
          ,min_swap_size => '2'
          ,arch => 'x86_64'
          ,extra_iso => 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.215-\d+/virtio-win-0.1.\d+.iso'
        }
        ,windows_xp => {
          name => 'Windows XP'
          ,description => 'Windows XP 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_xp.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '3'
          ,arch => 'x86_64'
        }
        ,windows_12 => {
          name => 'Windows 2012'
          ,description => 'Windows 2012 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_12.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '21'
          ,arch => 'x86_64'
        }
        ,windows_8 => {
          name => 'Windows 8.1'
          ,description => 'Windows 8.1 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_8.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '21'
          ,arch => 'x86_64'
        }
        ,windows_11 => {
          name => 'Windows 11'
          ,description => 'Windows 11 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_11.xml'
          ,xml_volume => 'windows11-volume.xml'
          ,min_disk_size => '64'
          ,min_swap_size => '2'
          ,min_ram => 4
          ,arch => 'x86_64'
          ,extra_iso => 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.2\d+-\d+/virtio-win-0.1.2\d+.iso'
            ,options => { machine => 'pc-q35', bios => 'UEFI'
                ,hardware => { cpu => { cpu => { topology => { threads => 2, cores => 2}}}}
            }
        }
       ,empty_32bits => {
          name => 'Empty Machine 32 bits'
          ,description => 'Empty Machine 32 bits Boot PXE'
          ,xml => 'empty-i386.xml'
          ,xml_volume => 'jessie-volume.xml'
          ,min_disk_size => '0'
          ,has_cd => 0
        }
       ,empty_64bits => {
          name => 'Empty Machine 64 bits'
          ,description => 'Empty Machine 64 bits Boot PXE'
          ,xml => 'empty-amd64.xml'
          ,xml_volume => 'jessie-volume.xml'
          ,min_disk_size => '0'
          ,arch => 'x86_64'
          ,has_cd => 0
        }
    );
    $self->_update_table($table, $field, \%data);
    $self->_update_table_isos_url(\%data);

    $self->_scheduled_fedora_releases(\%data) if $0 !~ /\.t$/;
    $self->_update_table($table, $field, \%data);

    # old entries to remove
    $data{parrot_mate_amd64} = {
		  name => 'Parrot Security Edition MATE'
    };
    $self->_update_table_isos_url(\%data);

}

sub _cmd_update_iso_urls($self, $request) {

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    die "Error: ".$user->name." not authorized\n"
    unless $user->is_admin;

    $self->_update_isos();
}

sub _update_table_isos_url($self, $data) {
    my $sth_delete = $CONNECTOR->dbh->prepare("DELETE FROM iso_images WHERE id=?");
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM iso_images WHERE name=?");
    for my $release (sort keys %$data) {
        my $entry = $data->{$release};
        if (exists $entry->{options} && $entry->{options} 
            && ref($entry->{options})
        ) {
            unlock_hash(%$entry);
            $entry->{options} = encode_json($entry->{options});
            lock_hash(%$entry);
        }
        $sth->execute($entry->{name});
        my $row = $sth->fetchrow_hashref();
        if (keys %$entry == 1) {
            if ($row->{id} && !$row->{device}) {
                warn "INFO: removing old $entry->{name}\n";
                $sth_delete->execute($row->{id});
            }
            next;
        }
        for my $field (keys %$entry) {
            next if defined $row->{$field} && $row->{$field} eq $entry->{$field};
            my $sth_update = $CONNECTOR->dbh->prepare(
                "UPDATE iso_images SET $field=?"
                ." WHERE id=?"
            );
            $sth_update->execute($entry->{$field}, $row->{id});
            warn("INFO: updating $release $field ".Dumper($row->{$field})." -> "
                .Dumper($entry->{$field})."\n")
            if !$FIRST_TIME_RUN && $0 !~ /\.t$/;
        }
    }
}

sub _scheduled_fedora_releases($self,$data) {

    return if !exists $VALID_VM{KVM} ||!$VALID_VM{KVM} || $>;
    my $vm = $self->search_vm('KVM') or return; # TODO move ISO downloads off KVM

    my @now = localtime(time);
    my $year = $now[5]+1900;
    my $month = $now[4]+1;

    my $url_archive
    = 'https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/';

    my $url_current
    = 'http://ftp.halifax.rwth-aachen.de/fedora/linux/releases/';

    my $release = 27;

    for my $y ( 2018 .. $year ) {
        for my $m ( 5, 11 ) {
            return if $y == $year && $m>$month;
            $release++;
            my $name = "fedora_".$release;
            next if exists $data->{$name};

            my $url = $url_archive;
            $url = $url_current if $y>=$year-1;

            my $url_file = $url.$release
                    .'/Workstation/x86_64/iso/Fedora-Workstation-.*-x86_64-'.$release
                    .'-.*\.iso';
            my @found;
            eval { @found = $vm->_search_url_file($url_file) };
            if ( $@ && $@ !~ /Not Found/i ) {
                warn $@;
                return;
            }
            if(!@found) {
                next if $url =~ m{//archives};

                $url_file = $url_archive.$release
                    .'/Workstation/x86_64/iso/Fedora-Workstation-.*-x86_64-'.$release
                    .'-.*\.iso';
                @found = $vm->_search_url_file($url_file);
                next if !scalar(@found);
            }

            $data->{$name} = {
            name => 'Fedora '.$release
            ,description => "RedHat Fedora $release Workstation 64 bits"
            ,arch => 'x86_64'
            ,url => $url_file
            ,xml => 'xenial64-amd64.xml'
            ,xml_volume => 'xenial64-volume.xml'
            ,sha256_url => '$url/Fedora-Workstation-'.$release.'-.*-x86_64-CHECKSUM'
            ,min_disk_size => 10 + $release-27
            };
        }
    }
}

sub _add_domain_drivers_display($self) {
    my $port_rdp = 3389;
    my %data = (
        'KVM' => [
            'spice'
            ,'vnc'
            ,{name => 'x2go', data => 22 }
            ,{name => 'Windows RDP', value => 'rdp', data => $port_rdp}
        ]
        ,'Void' => [
            'void'
            ,'spice'
            ,{name => 'x2go', data => 22 }
            ,{name => 'Windows RDP', value => 'rdp' , data => $port_rdp }
        ]
    );

    my $id_type = Ravada::Utils::max_id($CONNECTOR->dbh, 'domain_drivers_types')+1;
    my $id_option = Ravada::Utils::max_id($CONNECTOR->dbh, 'domain_drivers_options');
    for my $vm ( keys %data) {
        my $type = {
            id => $id_type
            ,name => 'display'
            ,description => 'Display'
            ,vm => $vm
        };

        $self->_update_table('domain_drivers_types','name,vm',$type)
            and do {
            for my $option ( @{$data{$vm}} ) {
                if (!ref($option)) {
                    $option = { name => $option
                        ,value => $option
                    };
                }
                $option->{value} = $option->{name} if !exists $option->{value};
                $option->{id_driver_type} = $id_type;
                $option->{id} = ++$id_option;
                $self->_update_table('domain_drivers_options','id_driver_type,name',$option)
            }
            $id_type++;
        };
    }
}

sub _add_domain_drivers_generic($self, $type, $data) {
    my $id_type = Ravada::Utils::max_id($CONNECTOR->dbh, 'domain_drivers_types')+1;
    my $id_option = Ravada::Utils::max_id($CONNECTOR->dbh, 'domain_drivers_options');
    for my $vm ( keys %$data) {
        $type->{id} = $id_type;
        $type->{vm} = $vm;
        $self->_update_table('domain_drivers_types','name,vm',$type)
            and do {
            for my $option ( @{$data->{$vm}} ) {
                if (!ref($option)) {
                    $option = { name => $option
                        ,value => $option
                    };
                }
                $option->{value} = $option->{name} if !exists $option->{value};
                $option->{id_driver_type} = $id_type;
                $option->{id} = ++$id_option;
                $self->_update_table('domain_drivers_options','id_driver_type,name',$option)
            }
            $id_type++;
        };
    }

}

sub _add_domain_drivers_cpu($self) {
    my %data = (
        'KVM' => [
            'custom'
            ,'host-model'
            ,'host-passthrough'
        ]
    );
    my $type = {
        name => 'cpu'
        ,description => 'CPU'
    };
    $self->_add_domain_drivers_generic($type, \%data);
}

sub _add_domain_drivers_usb_controller($self) {
    my %data = (
        'KVM' => [
            'nec-xhci'
            ,'piix3-uhci'
            ,'qemu-xhci'
        ]
    );
    my $type = {
        name => 'usb controller'
        ,description => 'USB Controller'
    };
    $self->_add_domain_drivers_generic($type, \%data);

}

sub _update_domain_drivers_types($self) {

    my $data = {
        image => {
            id => 4,
            ,name => 'image'
           ,description => 'Graphics Options'
           ,vm => 'KVM'
        },
        jpeg => {
            id => 5,
            ,name => 'jpeg'
           ,description => 'Graphics Options'
           ,vm => 'KVM'
        },
        zlib => {
            id => 6,
            ,name => 'zlib'
           ,description => 'Graphics Options'
           ,vm => 'KVM'
        },
        playback => {
            id => 7,
            ,name => 'playback'
           ,description => 'Graphics Options'
           ,vm => 'KVM'

        },
        streaming => {
            id => 8,
            ,name => 'streaming'
           ,description => 'Graphics Options'
           ,vm => 'KVM'

        }
        ,disk => {
            id => 9
            ,name => 'disk'
            ,vm => 'KVM'
        }

    };
    $self->_update_table('domain_drivers_types','id',$data);
    my $id = Ravada::Utils::max_id($CONNECTOR->dbh, 'domain_drivers_types');
    my $id_option = Ravada::Utils::max_id($CONNECTOR->dbh, 'domain_drivers_options');
    my $data_options;
    for my $item (keys %$data) {
        unlock_hash(%{$data->{$item}});
        $data->{$item}->{id} = ++$id;
        $data->{$item}->{vm} = 'Void';

        next if $item eq 'disk';

        $id_option++;
        $data_options->{"$item.on"} = {
            id => $id_option
            ,id_driver_type => $id
            ,name => "$item.on"
            ,value => "compression=on"
        };
        $id_option++;
        $data_options->{"$item.off"} = {
            id => $id_option
            ,id_driver_type => $id
            ,name => "$item.off"
            ,value => "compression=off"
        };

    }
    $self->_update_table('domain_drivers_types','name,vm',$data)
        and $self->_update_table('domain_drivers_options','id_driver_type,name',$data_options);

    my $sth = $CONNECTOR->dbh->prepare(
        "UPDATE domain_drivers_types SET vm='KVM' WHERE vm='qemu'"
    );
    $sth->execute;
    $sth->finish;
}

sub _update_domain_drivers_options($self) {

    my $data = {
        qxl => {
            id => 1,
            ,id_driver_type => 1,
            ,name => 'QXL'
           ,value => 'qxl'
        },
        vmvga => {
            id => 2,
            ,id_driver_type => 1,
            ,name => 'VMVGA'
           ,value => 'vmvga'
        },
        cirrus => {
            id => 3,
            ,id_driver_type => 1,
            ,name => 'Cirrus'
           ,value => 'cirrus'
        },
        vga => {
            id => 4,
            ,id_driver_type => 1,
            ,name => 'VGA'
           ,value => 'vga'
        },
        none => {
            id => 5
            ,id_driver_type => 1,
            ,name => 'None'
           ,value => 'none'
        },

        ich6 => {
            id => 6,
            ,id_driver_type => 2,
            ,name => 'ich6'
           ,value => 'model="ich6"'
        },
        ac97 => {
            id => 7,
            ,id_driver_type => 2,
            ,name => 'ac97'
           ,value => 'model="ac97"'
        },
        virtio => {
            id => 8,
            ,id_driver_type => 3,
            ,name => 'virtio'
           ,value => 'type="virtio"'
        },
        e1000 => {
            id => 9,
            ,id_driver_type => 3,
            ,name => 'e1000'
           ,value => 'type="e1000"'
        },
        rtl8139 => {
            id => 10,
            ,id_driver_type => 3,
            ,name => 'rtl8139'
           ,value => 'type="rtl8139"'
        },
        auto_glz => {
            id => 11,
            ,id_driver_type => 4,
            ,name => 'auto_glz'
           ,value => 'compression="auto_glz"'
        },
        auto_lz => {
            id => 12,
            ,id_driver_type => 4,
            ,name => 'auto_lz'
           ,value => 'compression="auto_lz"'
        },
        quic => {
            id => 13,
            ,id_driver_type => 4,
            ,name => 'quic'
           ,value => 'compression="quic"'
        },
        glz => {
            id => 14,
            ,id_driver_type => 4,
            ,name => 'glz'
           ,value => 'compression="glz"'
        },
        lz => {
            id => 15,
            ,id_driver_type => 4,
            ,name => 'lz'
           ,value => 'compression="lz"'
        },
        off => {
            id => 16,
            ,id_driver_type => 4,
            ,name => 'off'
           ,value => 'compression="off"'
        },
        auto => {
            id => 17,
            ,id_driver_type => 5,
            ,name => 'auto'
           ,value => 'compression="auto"'
        },
        never => {
            id => 18,
            ,id_driver_type => 5,
            ,name => 'never'
           ,value => 'compression="never"'
        },
        always => {
            id => 19,
            ,id_driver_type => 5,
            ,name => 'always'
           ,value => 'compression="always"'
        },
        auto1 => {
            id => 20,
            ,id_driver_type => 6,
            ,name => 'auto'
           ,value => 'compression="auto"'
        },
        never1 => {
            id => 21,
            ,id_driver_type => 6,
            ,name => 'never'
           ,value => 'compression="never"'
        },
        always1 => {
            id => 22,
            ,id_driver_type => 6,
            ,name => 'always'
           ,value => 'compression="always"'
        },
        on => {
            id => 23,
            ,id_driver_type => 7,
            ,name => 'on'
           ,value => 'compression="on"'
        },
        off1 => {
            id => 24,
            ,id_driver_type => 7,
            ,name => 'off'
           ,value => 'compression="off"'
        },
        filter => {
            id => 25,
            ,id_driver_type => 8,
            ,name => 'filter'
           ,value => 'mode="filter"'
        },
        all => {
            id => 26,
            ,id_driver_type => 8,
            ,name => 'all'
           ,value => 'mode="all"'
        },
        off2 => {
            id => 27,
            ,id_driver_type => 8,
            ,name => 'off'
           ,value => 'mode="off"'
        }
    };
    $self->_update_table('domain_drivers_options','id',$data);
}

sub _update_domain_drivers_options_disk($self) {

    my @options = ('virtio', 'usb','ide', 'sata', 'scsi');

    my $id = 28;
    my %data = map {
        $_ => {
            id => $id++
            ,id_driver_type => 9,
            ,name => $_
            ,value => $_
        }
    } @options;

    $self->_update_table('domain_drivers_options','id',\%data);
    return $id;
}

sub _update_domain_drivers_options_video($self, $id) {
    my @options_video = ('virtio');

    my %data = map {
        $_ => {
            id => $id++
            ,id_driver_type => 1,
            ,name => $_
            ,value => $_
        }
    } @options_video;

    $self->_update_table('domain_drivers_options','id',\%data);
}

sub _sth_search($table, $field) {
    my $sth_search;
    if ($field =~ /,/) {
        my $where = join( ' AND ', map { "$_=?" } split /,/,$field);
        $sth_search = $CONNECTOR->dbh->prepare("SELECT id FROM $table WHERE $where");
    } else {
        $sth_search = $CONNECTOR->dbh->prepare("SELECT id FROM $table WHERE $field = ?");
    }
    return $sth_search;
}

sub _sth_values($row, $field) {
    lock_hash(%$row);
    my @ret;
    for my $item (split /,/,$field) {
        push @ret,($row->{$item})
    }
    return @ret;
}

sub _update_table($self, $table, $field, $data, $verbose=0) {
    my ($first) = %$data;
    $data = { entry => $data } if !ref($data->{$first});

    my $changed = 0;
    my $sth_search = _sth_search($table,$field);
    for my $name (sort keys %$data) {
        my $row = $data->{$name};
        $sth_search->execute(_sth_values($row,$field));
        my ($id) = $sth_search->fetchrow;
        if ( $id ) {
            warn("INFO: $table : $row->{$field} already added.\n") if $verbose;
            next;
        }
        warn("INFO: updating $table [ $name ] : ".Dumper($data->{$name})."\n")
        if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

        my $sql =
            "INSERT INTO $table "
            ."("
            .join(" , ", sort keys %{$data->{$name}})
            .")"
            ." VALUES ( "
            .join(" , ", map { "?" } keys %{$data->{$name}})
            ." )"
        ;
        my $sth = $CONNECTOR->dbh->prepare($sql);
        $sth->execute(map { $data->{$name}->{$_} } sort keys %{$data->{$name}});
        $sth->finish;
        $changed++;
    }
    return $changed;
}

sub _remove_old_isos {
    my $self = shift;
    for my $sql (
        "DELETE FROM iso_images "
            ."  WHERE url like '%debian-9.0%iso'"
        ,"DELETE FROM iso_images"
            ."  WHERE name like 'Debian%' "
            ."      AND NOT ( url  like '%*%' OR url like '%+%') "
        ,"DELETE FROM iso_images "
            ."  WHERE name like 'Lubuntu Artful%'"
            ."      AND url NOT LIKE '%*%' "
        ,"DELETE FROM iso_images "
            ."  WHERE name like 'Lubuntu Zesty%'"
        ,"DELETE FROM iso_images "
            ."  WHERE name like 'Debian Buster 32%'"
            ."  AND file_re like '%xfce-CD-1.iso'"
        ,"DELETE FROM iso_images "
            ."  WHERE (name LIKE 'Ubuntu Focal%' OR name LIKE 'Ubuntu Bionic%' ) "
            ."  AND ( md5 IS NOT NULL OR md5_url IS NOT NULL) "
        ,"DELETE FROM iso_images "
            ."WHERE name like 'Ubuntu Focal%' "
            ."  AND ( file_re like '%20.04.1%' OR file_re like '%20.04.%d+%')"
        ,"DELETE FROM iso_images "
            ." WHERE name like 'Astra Linux 2%'"
            ." AND ( url like '%current%' OR url like '%orel%')"

        ,"DELETE FROM iso_images "
            ." WHERE name like 'Alpine%3.8%'"
	,"DELETE FROM iso_images "
	    ." WHERE name like 'Mint 18.1 Mate 64 bits'"
    ) {
        my $sth = $CONNECTOR->dbh->prepare($sql);
        $sth->execute();
        $sth->finish;
    }
}

sub _update_data {
    my $self = shift;

    $self->_remove_old_isos();

    $self->_install_grants();
    $self->_remove_old_indexes();
    $self->_update_domain_drivers_types();
    $self->_update_domain_drivers_options();
    my $id = $self->_update_domain_drivers_options_disk();
    $self->_update_domain_drivers_options_video($id);
    $self->_update_old_qemus();

    $self->_add_domain_drivers_display();
    $self->_add_domain_drivers_cpu();
    $self->_add_domain_drivers_usb_controller();

    $self->_add_indexes();
}

sub _install_grants($self) {
    if ($CAN_FORK) {
        my $pid = fork();
        die "Error: I cannot fork" if !defined $pid;
        if ($pid) {
            $self->_add_pid($pid);
            return;
        }
    }
    $self->_rename_grants();
    $self->_alias_grants();
    $self->_add_grants();
    $self->_enable_grants();
    $self->_update_user_grants();
    exit if $CAN_FORK;
}

sub _add_indexes($self) {
    $self->_add_indexes_generic();
}

sub _remove_old_indexes($self) {

    my $table = 'domain_drivers_types';
    my $index = 'name';
    my $n_fields = 1;
    my $known = $self->_get_indexes($table);
    my $name = $known->{$index};
    if ($name && scalar (@$name) == $n_fields ) {
        my $sql = "alter table $table drop index $index";
        my $sth = $CONNECTOR->dbh->prepare($sql);
        $sth->execute;
    }
}

sub _add_indexes_generic($self) {
    my %index = (
        domains => [
            "index(date_changed)"
            ,"index(id_base):id_base_index"
            ,"unique(id_base,name):id_base"
            ,"unique(name)"
            ,"key(is_base)"
            ,"key(is_volatile)"
        ]
        ,domain_displays => [
            "unique(id_domain,n_order)"
            ,"unique(id_domain,driver)"
            ,"unique(id_vm,port)"
            ,"index(id_domain)"
        ]
        ,domain_filesystems => [
            "unique(id_domain,source)"
        ]
        ,domain_ports => [
            "unique (id_domain,internal_port):domain_port"
            ,"unique (id_domain,name):name"
            ,"unique(id_vm,public_port)"
        ]
        ,domains_kvm => [
            "unique (id_domain)"
        ]
        ,group_access => [
            "unique (id_domain,name,id_group)"
            ,"index(id_domain)"
            ,"index(id_group)"
        ]
        ,iso_images => [
            "unique (name)"
        ]
        ,requests => [
            "index(status,at_time)"
            ,"index(id,date_changed,status,at_time)"
            ,"index(date_changed)"
            ,"index(start_time,command,status,pid)"
            ,"index(id_domain,status):domain_status"
        ]
        ,grants_user => [
            "index(id_user,id_grant)"
            ,'unique(id_grant,id_user):id_grant'
            ,"index(id_user)"
        ]
        ,iptables => [
            "index(id_domain,time_deleted,time_req)"
        ]
        ,host_devices => [
            "unique(name, id_vm)"
            ,"index(id_vm)"
        ]
        ,host_device_templates => [
            "unique(id_host_device,path)"
        ]
        ,host_devices_domain => [
            "unique(id_host_device, id_domain)"
            ,"index(id_domain)"
        ]
        ,host_devices_domain_locked => [
            "unique(id_vm,name)"
            ,"index(id_domain)"
        ],
        ,messages => [
             "index(id_user)"
             ,"index(date_changed)"
             ,"KEY(id_request,date_send)"

        ]
        ,settings => [
            "index(id_parent,name)"
        ]
        ,booking_entries => [
            "index(id_booking)"
        ]
        ,booking_entry_ldap_groups => [
            "index(id_booking_entry,ldap_group)"
            ,"index(id_booking_entry)"
        ]
        ,booking_entry_local_groups => [
            "unique(id_booking_entry,id_group)"
            ,"index(id_booking_entry)"
        ]

        ,booking_entry_users => [
            "index(id_booking_entry,id_user)"
            ,"index(id_booking_entry)"
            ,"index(id_user)"
        ]
        ,booking_entry_bases => [
            "index(id_booking_entry,id_base)"
            ,"index(id_base)"
            ,"index(id_booking_entry)"
        ]
        ,groups_local => [
            'UNIQUE (name)'
        ]
        ,users_group => [
            'UNIQUE(id_user, id_group)'
        ]

        ,volumes => [
            "index(id_domain)"
            ,'UNIQUE (id_domain,name):id_domain_name'
            ,'UNIQUE (id_domain,n_order):id_domain2'
        ]

        ,vms=> [
            "unique(hostname, vm_type): hostname_type"
            ,"UNIQUE (name,vm_type)"

        ]
        ,domain_share => [
            "index(id_domain)"
            ,"unique(id_user, id_domain)"
        ]
        ,virtual_networks => [
            "unique(id_vm,internal_id)"
            ,"unique(id_vm,name)"
            ,"index(date_changed)"
            ,"index(id_owner)"
        ]
        ,bundles => [
            "unique (name)"
        ]
        ,domains_bundle => [
            "index(id_domain)"
            ,"unique (id_bundle, id_domain)"
        ]
        ,vm_which => [
            "index(id_vm)"
            ,"unique(id_vm,command,path)"
        ]
    );
    my $if_not_exists = '';
    $if_not_exists = ' IF NOT EXISTS ' if $CONNECTOR->dbh->{Driver}{Name} =~ /sqlite|mariadb/i;
    for my $table (sort keys %index ) {
        my $known;
        $known = $self->_get_indexes($table) if !defined $known;
        my $checked_index={};
        for my $change (@{$index{$table}} ) {
            my ($type,$fields ) =$change =~ /(\w+)\s*\((.*)\)/;
            my ($name) = $change =~ /:(.*)/;
            $name = $fields if !$name;
            $name =~ s/,/_/g;
            $name =~ s/ //g;
            $checked_index->{$name}++;
            $known = $self->_get_indexes($table) if !defined $known;
            next if $self->_index_already_created($table, $name, $fields, $known->{$name});

            $type .=" INDEX " if $type=~ /^unique/i;
            $type = "INDEX" if $type =~ /^KEY$/i;

            my $sql = "CREATE $type $if_not_exists $name on $table ($fields)";

            warn "INFO: Adding index to $table: $name\n"
            if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

            $self->_clean_index_conflicts($table, $name);

            print "+" if $FIRST_TIME_RUN;
            if ($table eq 'domain_displays' && $name =~ /port/) {
                my $sth_clean=$CONNECTOR->dbh->prepare(
                    "UPDATE domain_displays set port=NULL"
                );
                $sth_clean->execute;
            }
            my $sth = $CONNECTOR->dbh->prepare($sql);
            $sth->execute();
        }
        for my $name ( sort keys %$known) {
            my $known2 = $self->_get_indexes($table);
            next if !exists $known2->{$name};
            next if $name eq 'PRIMARY' || $name =~ /^constraint_/i || $checked_index->{$name};
            warn "INFO: Removing index from $table $name\n"
            if !$FIRST_TIME_RUN && $0 !~ /\.t$/;
            confess "$table -> $name" if $FIRST_TIME_RUN;
            my $sql = "alter table $table drop index $name";
            warn Dumper($known2);
            $CONNECTOR->dbh->do($sql);
        }
    }
}

sub _index_already_created($self, $table, $index, $fields, $new) {
    return if !$new;
    $fields =~ s/ //g;
    my $fields_new = join(",",@$new);
    return 1 if $fields eq $fields_new;

    if (length($fields)) {
            warn "INFO: removing old index $index";
        $CONNECTOR->dbh->do("alter table $table drop index $index");
    }
    return 0;
}

sub _clean_index_conflicts($self, $table, $name) {
    my $sth_clean;
    if ($table eq 'domain_displays' && $name eq 'port') {
        $sth_clean=$CONNECTOR->dbh->prepare(
            "UPDATE domain_displays set port=NULL"
        );
    }
    $sth_clean->execute if $sth_clean;
}


sub _get_indexes($self,$table) {

    return {} if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/;

    my $sth = $CONNECTOR->dbh->prepare("show index from $table");
    $sth->execute;
    my %index;
    while (my @row = $sth->fetchrow) {
        my $name = $row[2];
        my $seq = $row[3];
        my $column = $row[4];
        $index{$name}->[$seq-1] = $column;
    }
    return \%index;
}

sub _get_constraints($self, $table) {
    return {} if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/;

    my $sth = $CONNECTOR->dbh->prepare("show create table $table");
    $sth->execute;
    my %index;
    my ($table2,$create) = $sth->fetchrow;
    for my $row (split /\n/,$create) {
        my ($name, $definition) = $row =~ /^\s+CONSTRAINT `(.*?)` (.*)/;
        next if !$name;
        $definition =~ s/,$//;
        $index{$name} = $definition;
    }
    return \%index;

}

sub _rename_grants($self) {

    my %rename = (
        create_domain => 'create_machine'
    );
    my $sth_old = $CONNECTOR->dbh->prepare("SELECT id FROM grant_types"
            ." WHERE name=?"
    );
    for my $old ( keys %rename ) {
        $sth_old->execute($rename{$old});
        next if $sth_old->fetchrow;

        my $sth = $CONNECTOR->dbh->prepare(
                 "UPDATE grant_types"
                ." SET name=? "
                ." WHERE name = ?"
        );
        $sth->execute($rename{$old}, $old);
        warn "INFO: renaming grant $old to $rename{$old}\n";
    }
}

sub _alias_grants($self) {

    my %alias= (
        remove_clone => 'remove_clones'
        ,shutdown_clone => 'shutdown_clones'
        ,reboot_clone => 'reboot_clones'
    );

    my $sth_old = $CONNECTOR->dbh->prepare("SELECT id FROM grant_types_alias"
            ." WHERE name=? AND alias=?"
    );
    while (my ($old, $new) =  each(%alias)) {
        $sth_old->execute($old, $new);
        return if $sth_old->fetch;
        my $sth = $CONNECTOR->dbh->prepare(
                 "INSERT INTO grant_types_alias (name,alias)"
                 ." VALUES(?,?) "
        );
        $sth->execute($old, $new);
    }
}

sub _add_grants($self) {
    $self->_add_grant('rename', 0,"can rename any virtual machine owned by the user.");
    $self->_add_grant('rename_all', 0,"can rename any virtual machine.");
    $self->_add_grant('rename_clones', 0,"can rename clones from virtual machines owned by the user.");
    $self->_add_grant('shutdown', 1,"can shutdown own virtual machines.");
    $self->_add_grant('reboot', 1,"can reboot own virtual machines.");
    $self->_add_grant('reboot_all', 0,"can reboot all virtual machines.");
    $self->_add_grant('reboot_clones', 0,"can reboot clones own virtual machines.");
    $self->_add_grant('screenshot', 1,"can get a screenshot of own virtual machines.");
    $self->_add_grant('start_many',0,"can have an unlimited amount of machines started.");
    $self->_add_grant('expose_ports',0,"can expose virtual machine ports.");
    $self->_add_grant('expose_ports_clones',0,"Can expose ports from clones of own virtual machines.");
    $self->_add_grant('expose_ports_all',0,"Can expose ports from any virtual machine.");
    $self->_add_grant('view_groups',0,'can view groups.');
    $self->_add_grant('manage_groups',0,'can manage groups.');
    $self->_add_grant('start_limit',0,"can have their own limit on started machines.", 1, 0);
    $self->_add_grant('view_all',0,"The user can start and access the screen of any virtual machine");
    $self->_add_grant('create_disk',0,'can create disk volumes');
    $self->_add_grant('quota_disk',0,'disk space limit',1);
    $self->_add_grant('create_networks',0,'can create virtual networks.');
    $self->_add_grant('manage_all_networks',0,'can manage all the virtual networks.');
}

sub _add_grant($self, $grant, $allowed, $description, $is_int = 0, $default_admin=1) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, description,is_int FROM grant_types WHERE name=?"
    );
    $sth->execute($grant);
    my ($id, $current_description, $current_int) = $sth->fetchrow();
    $sth->finish;
    $current_int = 0 if !$current_int;

    if ($id && ( $current_description ne $description || $current_int != $is_int) ) {
        my $sth = $CONNECTOR->dbh->prepare(
            "UPDATE grant_types SET description = ?,is_int=? WHERE id = ?;"
        );
        $sth->execute($description, $is_int, $id);
        $sth->finish;
    }
    return if $id;

    $sth = $CONNECTOR->dbh->prepare("INSERT INTO grant_types (name, description, is_int, default_admin)"
        ." VALUES (?,?,?,?)");
    $sth->execute($grant, $description, $is_int, $default_admin);
    $sth->finish;

    $sth = $CONNECTOR->dbh->prepare("SELECT id FROM grant_types WHERE name=?");
    $sth->execute($grant);
    my ($id_grant) = $sth->fetchrow;
    $sth->finish;

    my $sth_insert = $CONNECTOR->dbh->prepare(
        "INSERT INTO grants_user (id_user, id_grant, allowed) VALUES(?,?,?) ");

    $sth = $CONNECTOR->dbh->prepare("SELECT id,name,is_admin FROM users WHERE is_temporary = 0");
    $sth->execute;

    while (my ($id_user, $name, $is_admin) = $sth->fetchrow ) {
        my $allowed_current = $allowed;
        $allowed_current = 1 if $is_admin;
        $allowed_current = $default_admin if $is_admin && defined $default_admin;
        eval { $sth_insert->execute($id_user, $id_grant, $allowed_current ) };
        die $@ if $@ && $@ !~/Duplicate entry /;
    }
}

sub _null_grants($self) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT count(*) FROM grant_types "
            ." WHERE enabled = NULL "
        );
    $sth->execute;
    my ($count) = $sth->fetchrow;

    warn "No null grants found" if !$count && $self->{_null_grants}++;
    return $count;
}

sub _enable_grants($self) {

    return if $self->_null_grants();

    my @grants = (
        'change_settings',  'change_settings_all',  'change_settings_clones'
        ,'clone',           'clone_all',            'create_base', 'create_machine'
        ,'expose_ports','expose_ports_clones','expose_ports_all'
        ,'grant'
        ,'manage_users'
        ,'rename', 'rename_all', 'rename_clones'
        ,'remove',          'remove_all',   'remove_clone',     'remove_clone_all'
        ,'screenshot'
        ,'shutdown',        'shutdown_all',    'shutdown_clone'
        ,'reboot',          'reboot_all',      'reboot_clones'
        ,'screenshot'
        ,'start_many'
        ,'view_groups',     'manage_groups'
        ,'start_limit',     'start_many'
        ,'view_all'
        ,'create_disk', 'quota_disk'
        ,'create_networks','manage_all_networks'
    );

    my $sth = $CONNECTOR->dbh->prepare("SELECT id,name FROM grant_types");
    $sth->execute;
    my %grant_exists;
    while (my ($id, $name) = $sth->fetchrow ) {
        $grant_exists{$name} = $id;
    }

    $sth = $CONNECTOR->dbh->prepare(
        "UPDATE grant_types set enabled=1 WHERE name=?"
    );
    my %done;
    for my $name ( sort @grants ) {
        die "Duplicate grant $name "    if $done{$name};
        confess "Permission $name doesn't exist at table grant_types"
                ."\n".Dumper(\%grant_exists)
            if !$grant_exists{$name};

        $sth->execute($name);

    }
    $self->_disable_other_grants(@grants);
}

sub _disable_other_grants($self, @grants) {
    my $query = "UPDATE grant_types set enabled=0 WHERE  enabled=1 AND "
    .join(" AND ",map { "name <> ? " } @grants );
    my $sth = $CONNECTOR->dbh->prepare($query);
    $sth->execute(@grants);
}

sub _update_old_qemus($self) {
    my $sth = $CONNECTOR->dbh->prepare("UPDATE vms SET vm_type='KVM'"
        ." WHERE vm_type='qemu' AND name ='KVM_localhost'"
    );
    $sth->execute;

}

sub _set_url_isos($self, $new_url='http://localhost/iso/') {
    $new_url .= '/' if $new_url !~ m{/$};
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,url FROM iso_images "
        ."WHERE url is NOT NULL"
    );
    my $sth_update = $CONNECTOR->dbh->prepare(
        "UPDATE iso_images set url=? WHERE id=?"
    );
    $sth->execute();
    while ( my ($id, $url) = $sth->fetchrow) {
        $url =~ s{\w+://(.*?)/(.*)}{$new_url$2};
        $sth_update->execute($url, $id);
    }
    $sth->finish;

}

sub _get_column_info
{
    my $self = shift;
    my ($table, $field) = @_;
    my $dbh = $CONNECTOR->dbh;
    my $sth = $dbh->column_info(undef,undef,$table,$field);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    return $row;
}

sub _upgrade_table_fields($self, $table, $fields ) {
    for my $field ( keys %$fields ) {
        my $definition = $fields->{$field};
        $definition =~ s/^integer /INT /;
        $self->_upgrade_table($table, $field, $definition);
    }
}

sub _upgrade_table($self, $table, $field, $definition) {
    my $dbh = $CONNECTOR->dbh;

    my ($new_type) = $definition =~ m{(\w+)};
    my ($new_size) = $definition =~ m{$new_type\s*\((\d+)};
    $new_type = 'INT' if lc($new_type) eq lc('INTEGER');

    my ($constraint) = $definition =~ /references\s+(.*)/;

    my $sth = $dbh->column_info(undef,undef,$table,$field);
    my $row = $sth->fetchrow_hashref;
    $row->{TYPE_NAME} = 'INT' if exists $row->{TYPE_NAME} && $row->{TYPE_NAME} eq 'INTEGER';
    $sth->finish;
    if ( $dbh->{Driver}{Name} =~ /mysql/
        && keys %$row
        && (
            (defined $row->{COLUMN_SIZE}
            && defined $new_size
            && $new_size != $row->{COLUMN_SIZE}
            ) || ( exists $row->{TYPE_NAME} &&
                lc($row->{TYPE_NAME}) ne lc($new_type)
            )
        )
    ){

        warn "INFO: changing $field\n"
            ." $row->{COLUMN_SIZE} to ".($new_size or '')."\n"
            ." $row->{TYPE_NAME} -> $new_type \n"
            ." in $table\n$definition\n"  if !$FIRST_TIME_RUN && $0 !~ /\.t$/;
        print "-" if $FIRST_TIME_RUN;
        $dbh->do("alter table $table change $field $field $definition");

        $self->_create_constraints($table, [$field, $constraint]) if $constraint;

        return;
    }

    if (keys %$row ) {
        $self->_create_constraints($table, [$field, $constraint]) if $constraint;
        return;
    }

    my $sqlite_trigger;
    if ($dbh->{Driver}{Name} =~ /sqlite/i) {
        $definition =~ s/DEFAULT.*ON UPDATE(.*)//i;
        $sqlite_trigger = $1;
    }
    warn "INFO: adding $field $definition to $table\n"
    if!$FIRST_TIME_RUN && $0 !~ /\.t$/;

    $dbh->do("alter table $table add $field $definition");
    if ( $sqlite_trigger && !$self->_exists_trigger($dbh, "Update$field") ) {
        $self->_sqlite_trigger($dbh,$table, $field, $sqlite_trigger);
    }
    print "-" if $FIRST_TIME_RUN;
    return 1;
}

sub _exists_trigger($self, $dbh, $name) {
    my $sth = $dbh->prepare("select name from sqlite_master where type = 'trigger'"
        ." AND name=?"
    );
    $sth->execute($name);
    my ($found) = $sth->fetchrow;
    return $found;
}

sub _sqlite_trigger($self, $dbh, $table,$field, $trigger) {
    my $sql =
    "CREATE TRIGGER Update$field
    AFTER UPDATE
    ON $table
    FOR EACH ROW
    WHEN NEW.$field < OLD.$field
    BEGIN
    UPDATE $table SET $field=$trigger WHERE id=OLD.id;
    END;
    ";
    $dbh->do($sql);
}

sub _remove_field($self, $table, $field) {

    my $dbh = $CONNECTOR->dbh;
    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/i;

    my $sth = $dbh->column_info(undef,undef,$table,$field);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    return if !$row;

    warn "INFO: removing $field from $table\n"
    if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

    $dbh->do("alter table $table drop column $field");
    return 1;

}

sub _create_table {
    my $self = shift;
    my $table = shift;

    my $sth = $CONNECTOR->dbh->table_info('%',undef,$table,'TABLE');
    my $info = $sth->fetchrow_hashref();
    $sth->finish;
    return if keys %$info;

    warn "INFO: creating table $table\n"
    if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

    print "." if $FIRST_TIME_RUN;

    my $file_sql = "$DIR_SQL/$table.sql";
    open my $in,'<',$file_sql or die "$! $file_sql";
    my $sql = join " ",<$in>;
    close $in;

    $CONNECTOR->dbh->do($sql);
    return 1;
}

sub _insert_data {
    my $self = shift;
    my $table = shift;

    my $file_sql =  "$DIR_SQL/../data/insert_$table.sql";
    return if ! -e $file_sql;

    warn "INFO: inserting data for $table\n"
    if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

    open my $in,'<',$file_sql or die "$! $file_sql";
    my $sql = '';
    while (my $line = <$in>) {
        $line =~ s{/\*.*?\*/}{};
        $sql .= $line;
        next if $sql !~ /\w/ || $sql !~ /;\s*$/;
        $CONNECTOR->dbh->do($sql);
        $sql = '';
    }
    close $in;

}

sub _create_tables {
    my $self = shift;
#    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/i;

    my $driver = lc($CONNECTOR->dbh->{Driver}{Name});
    $driver = 'mysql' if $driver =~ /mariadb/i;

    $DIR_SQL =~ s{(.*)/.*}{$1/$driver};

    opendir my $ls,$DIR_SQL or die "$! $DIR_SQL";
    while (my $file = readdir $ls) {
        my ($table) = $file =~ m{(.*)\.sql$};
        next if !$table;
        next if $table =~ /^insert/;
        $self->_insert_data($table)     if $self->_create_table($table);
    }
    closedir $ls;
}

sub _sql_create_tables($self) {
    my $created = 0;
    my $driver = lc($CONNECTOR->dbh->{Driver}{Name});
    my @tables = (
        [
        domain_displays => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
            ,id_vm => 'int default null'
            ,port => 'char(5) DEFAULT NULL'
            ,ip => 'varchar(254)'
            ,listen_ip => 'varchar(254)'
            ,driver => 'char(40) not null'
            ,is_active => 'integer NOT NULL default 0'
            ,is_builtin => 'integer NOT NULL default 0'
            ,is_secondary => 'integer NOT NULL default 0'
            ,id_domain_port => 'integer DEFAULT NULL'
            ,n_order => 'integer NOT NULL'
            ,password => 'char(40)'
            ,extra => 'TEXT'
        }
        ]
        ,[
        domain_backups => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
            ,file => 'char(200) not null'
            ,date_created => 'date not null'
        }
        ]
        ,[
     domain_filesystems => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
            ,source => 'char(120) NOT NULL'
            ,chroot => 'integer(4) not null default 0'
            ,subdir_uid => 'integer not null default 1000'

            }
        ]
        ,[
            domain_ports => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
            ,'id_domain' => 'int(11) NOT NULL'
            ,'public_port' => 'int(11) DEFAULT NULL'
            ,'internal_port' => 'int(11) DEFAULT NULL'
            ,'name' => 'varchar(32) DEFAULT NULL'
            ,'restricted' => 'int(1) DEFAULT 0'
            ,'internal_ip' => 'char(200) DEFAULT NULL'
            ,'is_active' => 'int(1) DEFAULT 0'
            ,'is_secondary' => 'int(1) DEFAULT 0'
            ,'id_vm' => 'int(11) DEFAULT NULL'
            }
        ]
        ,[
            domains_kvm => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
            ,xml => 'TEXT'
            }
        ]
        ,
        [   groups_local => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                ,name => 'char(255) NOT NULL'
                ,is_external => 'int NOT NULL default(0)'
                ,external_auth => 'varchar(64) default NULL'
            }
        ]
        ,[
            group_access => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
            ,id_group => 'integer references `groups_local` (`id`) ON DELETE CASCADE'
            ,name => 'char(80) DEFAULT NULL'
            ,type => 'char(40)'
            }
        ]
        ,
        [
            host_devices => {
                id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
                ,name => 'char(80) not null'
                ,id_vm => 'integer NOT NULL references `vms`(`id`) ON DELETE CASCADE'
                ,list_command => 'varchar(128) not null'
                ,list_filter => 'varchar(128) not null'
                ,template_args => 'varchar(255) not null'
                ,devices_node => 'TEXT'
                ,enabled => "integer NOT NULL default 1"
                ,'date_changed'
                    => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
            }
        ]
        ,
        [
            host_device_templates=> {
                id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
                ,id_host_device => 'integer NOT NULL references `host_devices`(`id`) ON DELETE CASCADE'
                ,path => 'varchar(255)'
                ,type => 'char(40)'
                ,template=> 'TEXT'
            }
        ]
        ,
        [
            host_devices_domain => {
                id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
                ,id_host_device => 'integer NOT NULL references `host_devices`(`id`) ON DELETE CASCADE'
                ,id_domain => 'integer NOT NULL references `domains`(`id`) ON DELETE CASCADE'
                ,name => 'varchar(255)'
            }
        ]
        ,[
            host_devices_domain_locked => {
                id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
                ,id_vm => 'integer NOT NULL references `vms`(`id`) ON DELETE CASCADE'
                ,id_domain => 'integer NOT NULL references `domains`(`id`) ON DELETE CASCADE'
                ,name => 'varchar(255)'
                ,'time_changed' => 'integer'
            }
        ]
        ,[
            log_active_domains => {
            'id' => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,'active','integer not null default 0'
            ,'date_changed'
                    => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'

            }
        ]
        ,[
            iso_images => {
            'id' => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            ,'file_re' => 'char(64) DEFAULT NULL'
            ,'name' => 'char(64) NOT NULL'
            ,'description' => 'varchar(255) DEFAULT NULL'
            ,'arch' => 'char(8) DEFAULT NULL'
            ,'xml' => 'varchar(64) DEFAULT NULL'
            ,'xml_volume' => 'varchar(64) DEFAULT NULL'
            ,'url' => 'varchar(255) DEFAULT NULL'
            ,'md5' => 'varchar(32) DEFAULT NULL'
            ,'md5_url' => 'varchar(255) DEFAULT NULL'
            ,'sha256_url' => 'varchar(255) DEFAULT NULL'
            ,'device' => 'varchar(255) DEFAULT NULL'
            ,'min_disk_size' => 'int(11) DEFAULT NULL'
            ,'rename_file' => 'varchar(80) DEFAULT NULL'
            ,'sha256' => 'varchar(255) DEFAULT NULL'
            ,'options' => 'varchar(255) DEFAULT NULL'
            ,'has_cd' => 'int(1) DEFAULT 1'
            ,'downloading' => 'int(1) DEFAULT 0'
            ,'extra_iso'=> 'varchar(255) DEFAULT NULL'
            ,'min_swap_size'=> 'int(11) DEFAULT NULL'
            ,'min_ram'=> 'float DEFAULT 0.2'
            }
        ],
        [
        settings => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            , id_parent => 'INT NOT NULL'
            , name => 'varchar(64) NOT NULL'
            , value => 'varchar(128) DEFAULT NULL'
        }
        ]
        ,
        [ domain_share => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE',
            ,id_user => 'int not null references `users` (`id`) ON DELETE CASCADE'
            }
        ],
        [
        bookings => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,title => 'varchar(80)'
            ,description => 'varchar(255)'
            ,date_start => 'date not null'
            ,date_end => 'date not null'
            ,id_owner => 'int not null'
            ,background_color => 'varchar(20)'
            ,date_created => 'datetime DEFAULT CURRENT_TIMESTAMP'
            ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
        }
        ]
        ,
        [
        booking_entries => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,title => 'varchar(80)'
            ,description => 'varchar(255)'
            ,id_booking => 'int not null references `bookings` (`id`) ON DELETE CASCADE'
            ,time_start => 'time not null'
            ,time_end => 'time not null'
            ,date_booking => 'date'
            ,visibility => "enum ('private','public') default 'public'"
            ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
            ,options => 'varchar(100)'
        }
        ]
        ,
        [
        booking_entry_ldap_groups => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,id_booking_entry
                => 'int not null references `booking_entries` (`id`) ON DELETE CASCADE'
            ,ldap_group => 'varchar(255) not null'
            ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
        }
        ]
        ,
        [
        booking_entry_local_groups => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,id_booking_entry
                => 'int not null references `booking_entries` (`id`) ON DELETE CASCADE'
            ,id_group => 'int not null'
            ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
        }
        ]
        ,

        [
        booking_entry_users => {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,id_booking_entry
                => 'int not null references `booking_entries` (`id`) ON DELETE CASCADE'
            ,id_user => 'int not null references `users` (`id`) ON DELETE CASCADE'
            ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
        }
        ]
        ,
        [
        booking_entry_bases=> {
            id => 'INTEGER PRIMARY KEY AUTO_INCREMENT'
            ,id_booking_entry
                => 'int not null references `booking_entries` (`id`) ON DELETE CASCADE'
            ,id_base => 'int not null references `domains` (`id`) ON DELETE CASCADE'
            ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
        }
        ]
        ,
        [
            file_base_images => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT'
                ,id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE'
                ,file_base_img => ' varchar(255) DEFAULT NULL'
                ,target =>  'varchar(64) DEFAULT NULL'
            }
        ]
        ,
        [   users_group => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                ,id_user => 'integer NOT NULL'
                ,id_group =>'integer NOT NULL'
            }
        ],
        [
            volumes => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE',
                name => 'char(255) NOT NULL',
                file => 'varchar(255) NOT NULL',
                n_order => 'integer NOT NULL',
                info => 'TEXT',

            }
        ]
        ,
        [
            bundles => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                name => 'char(255) NOT NULL',
                private_network => 'integer NOT NULL default 0',
                isolated => 'integer NOT NULL default 0'
            }
        ],
        [
            domains_bundle => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                id_bundle => 'integer NOT NULL references `bundles` (`id`) ON DELETE CASCADE',
                id_domain => 'integer NOT NULL references `domains` (`id`) ON DELETE CASCADE',
            }
        ]
        ,
        [virtual_networks => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                ,id_vm => 'integer NOT NULL references `vms` (`id`) ON DELETE CASCADE',
                ,name => 'varchar(200)'
                ,id_owner => 'integer NOT NULL references `users` (`id`) ON DELETE CASCADE',
                ,internal_id => 'char(80) not null'
                ,autostart => 'integer not null'
                ,bridge => 'char(80)'
                ,'ip_address' => 'char(20)'
                ,'ip_netmask' => 'char(20)'
                ,'dhcp_start' => 'char(15)'
                ,'dhcp_end' => 'char(15)'
                ,'is_active' => 'integer not null default 1'
                ,'is_public' => 'integer not null default 0'
                ,'forward_mode' => 'char(20)'
                ,date_changed => 'timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
            }
        ]
        ,
        [vm_which => {
                id => 'integer PRIMARY KEY AUTO_INCREMENT',
                ,id_vm => 'integer NOT NULL references `vms` (`id`) ON DELETE CASCADE',
                ,command => 'char(40)'
                ,path => 'varchar(255)'
            }
        ]

    );
    for my $new_table (@tables ) {
        my ($table, $contents) = @$new_table;
        my $sth = $CONNECTOR->dbh->table_info('%',undef,$table,'TABLE');
        my $info = $sth->fetchrow_hashref();
        $sth->finish;
        if  ( keys %$info ) {
            $self->_upgrade_table_fields($table, $contents);
            next;
        }

        warn "INFO: creating table $table\n"
        if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

        my @constraints;
        my $sql_fields;
        for my $field (sort keys %$contents ) {
            my $definition = _port_definition($driver, $contents->{$field});
            $sql_fields .= ", " if $sql_fields;
            $sql_fields .= " $field $definition";

            my ($constraint) = $definition =~ /references\s+(.*)/;
            push @constraints , [$field,$constraint] if $constraint;
        }

        my $sql = "CREATE TABLE $table ( $sql_fields )";

        $CONNECTOR->dbh->do($sql);
        $self->_create_constraints($table, @constraints);
        $created++;
    }
    return $created;
}

sub _clean_db_leftovers($self) {
    return if $self->{_cleaned_db_leftovers}++;
    my $dbh = $CONNECTOR->dbh;
    for my $table (
        'access_ldap_attribute','domain_access'
        ,'domain_displays' , 'domain_ports', 'volumes', 'domains_void', 'domains_kvm', 'domain_instances', 'bases_vm', 'domain_access', 'base_xml', 'file_base_images', 'iptables', 'domains_network') {
        my $sth2 = $CONNECTOR->dbh->table_info('%',undef, $table,'TABLE');
        my $info = $sth2->fetchrow_hashref();
        $sth2->finish;
        next if !keys %$info;

        $self->_delete_limit("FROM $table WHERE id_domain NOT IN "
            ." ( SELECT id FROM domains ) ");
        ;
    }
    for my $table ('bases_vm' ,'domain_instances') {
        $self->_delete_limit("FROM $table WHERE id_vm NOT IN "
            ." ( SELECT id FROM vms) ");
        ;
    }
    for my $table ('grants_user') {
        my $sth_select = $dbh->prepare("SELECT count(*) FROM $table WHERE id_user NOT IN "
            ." ( SELECT id FROM users ) ");

        $self->_delete_limit("FROM $table WHERE id_user NOT IN "
            ." ( SELECT id FROM users ORDER BY id) "
        );
    }
}

sub _delete_limit($self, $query) {
    my $dbh = $CONNECTOR->dbh;
    my $sth_select = $dbh->prepare("SELECT count(*) $query");
    $query .= " LIMIT 1000";
    my $sth_delete = $dbh->prepare("DELETE $query");
    for ( ;; ) {
        $sth_select->execute();
        my ($n) = $sth_select->fetchrow();
        last if !$n;
        $sth_delete->execute();
        sleep 1;
    }

}

sub _fix_constraint($self, $definition) {
    my ($table,$post) = $$definition =~ /^\s*`(\w+)`\s*(\(.*)/;
    if ( !$table ) {
        my $field;
        ($table,$field,$post) = $$definition =~ /^\s*(\w+)\s*\((.*)\)\s+(.*)/;
        confess "Error: constraint $$definition without ON DELETE" if !$post;
        $$definition = "`$table` (`$field`) $post";
        return;
    }

    $$definition = "`$table` $post";
}

sub _create_constraints($self, $table, @constraints) {
    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/i;


    my $known = $self->_get_constraints($table);
    for my $constraint ( @constraints ) {
        my ($field, $definition) = @$constraint;
        #my $sql = "alter table $table add CONSTRAINT constraint_${table}_$field FOREIGN KEY ($field) references $definition";
        $self->_fix_constraint(\$definition);
        my $sql = "FOREIGN KEY (`$field`) REFERENCES $definition";
        my $name = "constraint_${table}_$field";
        next if $known->{$name} && $known->{$name} eq $sql;

        if ($known->{$name}) {
           push @{$self->{_constraints}}
           ,"alter table $table DROP constraint $name";
        }


        $sql = "alter table $table add CONSTRAINT $name $sql";
        #        $CONNECTOR->dbh->do($sql);
        push @{$self->{_constraints}},($sql);

    }
}

sub _sql_insert_defaults($self){
    require Mojolicious::Plugin::Config;
    my $plugin = Mojolicious::Plugin::Config->new();
    my $conf = {
        fallback => 0
        ,session_timeout => 10*60
        ,admin_session_timeout => 30*60
		,debug => 0
        ,auto_view => 1
    };
    if ( -e "/etc/rvd_front.conf" ){
        $conf = $plugin->load("/etc/rvd_front.conf");
    }
    my $id_frontend = 1;
    my $id_backend = 2;
    my %values = (
        settings => [
            {
                id => $id_frontend
                ,id_parent => 0
                ,name => 'frontend'
            }
            ,{
                id => $id_backend
                ,id_parent => 0
                ,name => 'backend'
            }
            ,{
                id_parent => $id_frontend
                ,name => 'fallback'
                ,value => $conf->{fallback}
            }
            ,{
                id_parent => $id_frontend
                ,name => 'maintenance'
                ,value => 0
            }
            ,{
                id_parent => $id_frontend
                ,name => 'maintenance_start'
                ,value => ''
            }
            ,{
                id_parent => $id_frontend
                ,name => 'maintenance_end'
                ,value => ''
            }

            ,{
                id_parent => $id_frontend
                ,name => 'session_timeout'
                ,value => $conf->{session_timeout}
            }
            ,{
                id_parent => $id_frontend
                ,name => 'session_timeout_admin'
                ,value => $conf->{session_timeout_admin}
            }
            ,{
                id_parent => $id_frontend
                ,name => 'auto_view'
                ,value => $conf->{auto_view}
            }
            ,{  id_parent => $id_frontend
                ,name => "widget"
                ,value => $conf->{widget}
            }
            ,{
                id_parent => $id_frontend
                ,name => 'content_security_policy'
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "all"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "default-src"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "style-src"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "script-src"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "object-src"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "frame-src"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "font-src"
                ,value => ''
            }

            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "connect-src"
                ,value => ''
            }
            ,{
                id_parent => "/frontend/content_security_policy"
                ,name => "media-src"
                ,value => ''
            }
            ,{
                id_parent => $id_frontend
                ,name => 'auto_create_users'
                ,value => 1
            }
            ,{
                id_parent => $id_frontend
                ,name => 'openid'
            }
            ,{
                id_parent => "/frontend/openid"
                ,name => "enabled"
                ,value => 0
            }
            ,{
                id_parent => "/frontend/openid"
                ,name => "logout_url"
                ,value => ''
            }
            ,{
                id_parent => $id_backend
                ,name => 'start_limit'
                ,value => 1
            }
            ,{
                id_parent => $id_backend
                ,name => 'time_zone'
                ,value => Ravada::Utils::default_time_zone()
            }
            ,{
                id_parent => $id_backend
                ,name => 'bookings'
                ,value => 1
            }
            ,{
                id_parent => $id_backend
                ,name => 'debug'
                ,value => 0
            }
            ,{
                id_parent => $id_backend
                ,name => 'delay_migrate_back'
                ,value => 60 * 60 * 24
            }
            ,{
                id_parent => $id_backend
                ,name => 'display_password'
                ,value => 1
            }
            ,{
                id_parent => $id_backend
                ,name => "debug_ports"
                ,value => 0
            }
            ,{
                id_parent => $id_backend
                ,name => 'expose_port_min'
                ,value => '60000'
            }
            ,{
                id_parent => $id_backend
                ,name => 'wait_retry'
                ,value => '10'

            }
            ,{
                id_parent => $id_backend
                ,name => 'auto_compact'
                ,value => '0'
            }
            ,{
                id_parent => '/backend/auto_compact'
                ,name => 'time'
                ,value => '21:00'
            }
            ,{
                id_parent => '/backend'
                ,name => 'limits'
                ,value => undef
            }
            ,{
                id_parent => '/backend/limits'
                ,name => 'startup_ram'
                ,value => 1
            }


        ]
    );
    my %field = ( settings => 'name' );
    for my $table (sort keys %values) {
        my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM $table "
            ." WHERE $field{$table} = ? "
        );
        for my $entry (@{$values{$table}}) {
            $sth->execute($entry->{$field{$table}});
            my ($found) = $sth->fetchrow;
            next if $found;

            warn "INFO: adding default $table ".Dumper($entry)
            if !$FIRST_TIME_RUN && $0 !~ /\.t$/;

            if ($entry->{id_parent} !~ /^\d+$/) {
                my $parent = $self->_setting_data($entry->{id_parent});
                die "Error not found setting $entry->{id_parent}"
                if !$parent;

                $entry->{id_parent} = $parent->{id};
            }
            $self->_sql_insert_values($table, $entry);
        }
    }
}

sub _sql_insert_values($self, $table, $entry) {
    my $sql = "INSERT INTO $table "
    ."( "
        .join(" , ",sort keys %$entry)
    .") "
    ." VALUES ( "
        .join(" , ", map { '? ' } keys %$entry)
    ." ) ";

    my $sth = $CONNECTOR->dbh->prepare($sql);
    $sth->execute(map { $entry->{$_} } sort keys %$entry);

}

sub _port_definition($driver, $definition0){
    return $definition0 if $driver =~ /mysql|mariadb/i;
    if ($driver eq 'sqlite') {
        $definition0 =~ s/(.*) AUTO_INCREMENT$/$1 AUTOINCREMENT/i;
        return $definition0 if $definition0 =~ /^(int|integer|char|varchar) /i;

        if ($definition0 =~ /^enum /) {
            my ($default) = $definition0 =~ / (default.*)/i;
            $default = '' if !defined $default;

            my @found = $definition0 =~ /'(.*?)'/g;
            my ($size) = sort map { length($_) } @found;
            return " varchar($size) $default";
        }
        elsif ($definition0 =~ /^timestamp /) {
            $definition0 = 'timestamp';
        }
    }
    return $definition0;
}

sub _clean_iso_mini {
    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM iso_images WHERE device like ?");
    $sth->execute('%/mini.iso');
    $sth->finish;

    $sth = $CONNECTOR->dbh->prepare("DELETE FROM iso_images WHERE url like ? AND rename_file = NULL");
    $sth->execute('%/mini.iso');
    $sth->finish;
}

sub _upgrade_users_table {
    my $self = shift;

    my $data = $self->_get_column_info('users', 'change_password');
    if ($data->{'COLUMN_DEF'} == 1) {
        my $sth = $CONNECTOR->dbh->prepare("UPDATE users set change_password=0");
        $sth->execute;
        $sth = $CONNECTOR->dbh->prepare("ALTER TABLE users ALTER change_password SET DEFAULT 0");
        $sth->execute;
    }
}

sub _upgrade_tables {
    my $self = shift;
#    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/i;

    $self->_upgrade_table("base_xml",'xml','TEXT');

    $self->_upgrade_table('vms','vm_type',"char(20) NOT NULL DEFAULT 'KVM'");
    $self->_upgrade_table('vms','connection_args',"text DEFAULT NULL");
    $self->_upgrade_table('vms','cached_active_time',"int DEFAULT 0");
    $self->_upgrade_table('vms','public_ip',"varchar(128) DEFAULT NULL");
    $self->_upgrade_table('vms','is_active',"int DEFAULT 0");
    $self->_upgrade_table('vms','enabled',"int DEFAULT 1");
    $self->_upgrade_table('vms','display_ip',"varchar(128) DEFAULT NULL");
    $self->_upgrade_table('vms','nat_ip',"varchar(128) DEFAULT NULL");

    $self->_upgrade_table('vms','min_free_memory',"int DEFAULT 600000");
    $self->_upgrade_table('vms', 'max_load', 'int not null default 10');
    $self->_upgrade_table('vms', 'active_limit','int DEFAULT NULL');
    $self->_upgrade_table('vms', 'base_storage','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('vms', 'clone_storage','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('vms','dir_backup','varchar(128) DEFAULT NULL');
    $self->_upgrade_table('vms','version','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('vms','cached_down','int DEFAULT 0');

    $self->_upgrade_table('requests','at_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','pid','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','start_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','output','text DEFAULT NULL');
    $self->_upgrade_table('requests','after_request','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','after_request_ok','int(11) DEFAULT NULL');

    $self->_upgrade_table('requests','at_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','run_time','float DEFAULT NULL');
    $self->_upgrade_table('requests','retry','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','args','TEXT');
    $self->_upgrade_table('domains','date_changed','timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');

    $self->_upgrade_table('users','language','char(40) DEFAULT NULL');
    if ( $self->_upgrade_table('users','is_external','int(11) DEFAULT 0')) {
        my $sth = $CONNECTOR->dbh->prepare(
            "UPDATE users set is_external=1 WHERE password='*LK* no pss'"
        );
        $sth->execute;
    }
    $self->_upgrade_table('users','external_auth','char(32) DEFAULT NULL');
    $self->_upgrade_table('users','date_created','timestamp DEFAULT CURRENT_TIMESTAMP');

    $self->_upgrade_table('networks','requires_password','int(11)');
    $self->_upgrade_table('networks','n_order','int(11) not null default 0');

    $self->_upgrade_table('domains','alias','varchar(255) DEFAULT NULL');
    $self->_upgrade_table('domains','spice_password','varchar(20) DEFAULT NULL');
    $self->_upgrade_table('domains','name','VARCHAR(255) NOT NULL');
    $self->_upgrade_table('domains','description','text DEFAULT NULL');
    $self->_upgrade_table('domains','run_timeout','int DEFAULT NULL');
    $self->_upgrade_table('domains','id_vm','int DEFAULT NULL');
    $self->_upgrade_table('domains','start_time','int DEFAULT 0');
    $self->_upgrade_table('domains','is_volatile','int NOT NULL DEFAULT 0');
    $self->_upgrade_table('domains','autostart','int NOT NULL DEFAULT 0');

    $self->_upgrade_table('domains','status','varchar(32) DEFAULT "shutdown"');
    #$self->_upgrade_table('domains','display_file','text DEFAULT NULL');
    $self->_remove_field('domains','display_file');
    $self->_upgrade_table('domains','info','TEXT DEFAULT NULL');
    $self->_upgrade_table('domains','internal_id','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('domains','volatile_clones','int NOT NULL default 0');
    $self->_upgrade_table('domains','comment',"varchar(80) DEFAULT ''");

    $self->_upgrade_table('domains','client_status','varchar(64)');
    $self->_upgrade_table('domains','client_status_time_checked','int NOT NULL default 0');
    $self->_upgrade_table('domains','pools','int NOT NULL default 0');
    $self->_upgrade_table('domains','pool_clones','int NOT NULL default 0');
    $self->_upgrade_table('domains','pool_start','int NOT NULL default 0');
    $self->_upgrade_table('domains','is_pool','int NOT NULL default 0');

    $self->_upgrade_table('domains','needs_restart','int not null default 0');
    $self->_upgrade_table('domains','shutdown_disconnected','int not null default 0');
    $self->_upgrade_table('domains','shutdown_grace_time','int not null default 10');
    $self->_upgrade_table('domains','shutdown_timeout','int default null');
    $self->_upgrade_table('domains','date_changed','timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');
    $self->_upgrade_table('domains','balance_policy','int default 0');

    if ($self->_upgrade_table('domains','screenshot','MEDIUMBLOB')) {

    $self->_upgrade_screenshots();

    }
    $self->_upgrade_table('domains','shared_storage','varchar(254)');
    $self->_upgrade_table('domains','post_shutdown','int not null default 0');
    $self->_upgrade_table('domains','post_hibernated','int not null default 0');
    $self->_upgrade_table('domains','is_compacted','int not null default 0');
    $self->_upgrade_table('domains','has_backups','int not null default 0');
    $self->_upgrade_table('domains','has_clones','int default NULL');
    $self->_upgrade_table('domains','has_host_devices','int default NULL');
    $self->_upgrade_table('domains','is_locked','int not null default 0');
    $self->_upgrade_table('domains','auto_compact','int default NULL');
    $self->_upgrade_table('domains','date_status_change' , 'datetime');
    $self->_upgrade_table('domains','show_clones' , 'int not null default 1');
    $self->_upgrade_table('domains','config_no_hd' , 'text');
    $self->_upgrade_table('domains','networking' , 'varchar(32)');

    $self->_upgrade_table('domains_network','allowed','int not null default 1');

    $self->_upgrade_table('iptables','id_vm','int DEFAULT NULL');
    $self->_upgrade_table('vms','security','varchar(255) default NULL');
    $self->_upgrade_table('grant_types','enabled','int not null default 1');
    $self->_upgrade_table('grant_types','default_admin','int not null default 1');

    $self->_upgrade_table('vms','mac','char(18)');
    $self->_upgrade_table('vms','tls','text');

    $self->_upgrade_table('domain_displays', 'id_vm','int DEFAULT NULL');

    $self->_upgrade_table('domain_drivers_options','data', 'char(200) ');

    $self->_upgrade_table('messages','date_changed','timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');

    $self->_upgrade_table('grant_types', 'is_int', 'int DEFAULT 0');

    $self->_upgrade_table('grants_user', 'id_user', 'int not null references `users` (`id`) ON DELETE CASCADE');

    $self->_upgrade_table('bases_vm','id_vm','int not null references `vms` (`id`) ON DELETE CASCADE');
    $self->_upgrade_table('bases_vm','id_domain','int not null references `domains` (`id`) ON DELETE CASCADE');
    $self->_upgrade_table('bases_vm','id_request','integer');

    $self->_upgrade_table('domain_instances','id_vm','int not null references `vms` (`id`) ON DELETE CASCADE');

    $self->_upgrade_users_table();
}

sub _upgrade_timestamps($self) {
    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/;

    my $req = Ravada::Request->ping_backend();
    return if $req->{date_changed};

    my @commands = qw(cleanup enforce_limits list_isos list_network_interfaces
    manage_pools open_exposed_ports open_iptables ping_backend
    refresh_machine refresh_storage refresh_vms
    screenshot);
    my $sql ="DELETE FROM requests WHERE "
        .join(" OR ", map { "command = '$_'" } @commands);
    my $sth = $CONNECTOR->dbh->prepare($sql);
    $sth->execute();

    $self->_upgrade_timestamp('requests','date_changed');
}

sub _upgrade_timestamp($self, $table, $field) {

    my $sth = $CONNECTOR->dbh->prepare("ALTER TABLE $table change $field "
        ."$field timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP");
    $sth->execute();
}

sub _connect_dbh($self=undef) {
    _wait_pids($self);
    my $driver= ($CONFIG->{db}->{driver} or 'mysql');;
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_pass = ($CONFIG->{db}->{password} or undef);
    my $db = ( $CONFIG->{db}->{db} or 'ravada' );
    my $host = $CONFIG->{db}->{host};
    my $hostname = $CONFIG->{db}->{hostname};
    if (defined $host && defined $hostname && $host ne $hostname) {
        warn "Warning: DB config in $FILE_CONFIG conflicting parameters host='$host', hostname='$hostname'\n";
    }
    $host = $hostname if !defined $host && defined $hostname;

    my $data_source = "DBI:$driver:$db";
    $data_source = "DBI:$driver:database=$db;host=$host"
        if $host && $host ne 'localhost';

    my $con;
    for my $try ( 1 .. 10 ) {
        eval { $con = DBIx::Connector->new($data_source
                        ,$db_user,$db_pass,{RaiseError => 1
                        , PrintError=> 0 });
            $con->dbh();
        };
        my $err = $@;
        $con->dbh->do("PRAGMA foreign_keys = ON") if $driver =~ /sqlite/i;

        if ($@ && $@ =~ /Too many connections/) {
            _wait_child_pids();
            sleep 10;
        }

        return $con if $con && !$err;
        sleep 1;
        warn "Try $try $data_source $@\n";
    }
    die ($@ or "Can't connect to $driver $db at $host");
}

sub _dbh($self) {
    return $CONNECTOR->dbh;
}

=head2 display_ip

Returns the default display IP read from the config file

=cut

sub display_ip($self=undef, $new_ip=undef) {
    if (defined $new_ip) {
        unlock_hash(%$CONFIG);
        if (!length $new_ip) {
            delete $CONFIG->{display_ip};
        } else {
            $CONFIG->{display_ip} = $new_ip;
        }
        lock_hash(%$CONFIG);
    }
    my $ip;
    $ip = $CONFIG->{display_ip} if exists $CONFIG->{display_ip};
    return $ip if $ip;
}

=head2 nat_ip

Returns the IP for NATed environments

=cut

sub nat_ip($self=undef, $new_ip=undef) {
    if (defined $new_ip) {
        unlock_hash(%$CONFIG);
        if (!length $new_ip) {
            delete $CONFIG->{nat_ip};
        } else {
            $CONFIG->{nat_ip} = $new_ip;
        }
        lock_hash(%$CONFIG);
    }

    return $CONFIG->{nat_ip} if exists $CONFIG->{nat_ip};
}

sub _init_config {
    my $file = shift or confess "ERROR: Missing config file";

    my $connector = shift;
    confess "Deprecated connector" if $connector;

    confess "ERROR: Missing config file $file\n"
        if !-e $file;

    eval { $CONFIG = YAML::LoadFile($file) };

    die "ERROR: Format error in config file $file\n$@"  if $@;
    _check_config($CONFIG);

    if ( !$CONFIG->{vm} ) {
        my %default_vms = %VALID_VM;
        delete $default_vms{Void};
        $CONFIG->{vm} = [keys %default_vms];
    }
    #    lock_hash(%$CONFIG);
#    $CONNECTOR = ( $connector or _connect_dbh());

    _init_config_vm();

    lock_hash(%$CONFIG);
}

sub _init_config_vm {

    for my $vm ( @{$CONFIG->{vm}} ) {
        confess "$vm not available in this system.\n".($ERROR_VM{$vm})
            if !exists $VALID_VM{$vm} || !$VALID_VM{$vm};
    }

    for my $vm ( keys %VALID_VM ) {
        if ( exists $VALID_VM{$vm}
                && exists $CONFIG->{vm}
                && scalar @{$CONFIG->{vm}}
                && !grep /^$vm$/,@{$CONFIG->{vm}}) {
            unlock_hash(%VALID_VM);
            delete $VALID_VM{$vm};
            lock_hash(%VALID_VM);
        }
    }

    lock_hash(%VALID_VM);

    @Ravada::Front::VM_TYPES = keys %VALID_VM;
}

sub _create_vm_kvm {
    my $self = shift;
    die "KVM not installed" if !exists $VALID_VM{KVM} ||!$VALID_VM{KVM};

    my $cmd_qemu_img = `which qemu-img`;
    chomp $cmd_qemu_img;

    die "ERROR: Missing qemu-img" if !$cmd_qemu_img;

    my $vm_kvm;

    $vm_kvm = Ravada::VM::KVM->new( );

    my $internal_vm;
    $internal_vm = $vm_kvm->vm;
    $vm_kvm = undef if !$internal_vm;

    return $vm_kvm;
}

sub _check_config($config_orig = {} , $valid_config = \%VALID_CONFIG, $quiet = $0=~/\.t$/ ) {
    return 1 if !defined $config_orig;
    my %config = %$config_orig;

    for my $key (sort keys %$valid_config) {
        if ( $config{$key} && ref($valid_config->{$key})) {
           my $ok = _check_config( $config{$key} , $valid_config->{$key}, $quiet );
           return 0 if !$ok;
        }
        delete $config{$key};
    }
    if ( keys %config ) {
        warn "Error: Unknown config entry \n".Dumper(\%config) if ! $quiet;
        return 0;
    }
    warn "Warning: LDAP authentication with match is discouraged. Try bind.\n"
        if exists $config_orig->{ldap}
        && exists $config_orig->{ldap}->{auth}
        && $config_orig->{ldap}->{auth} =~ /match/
        && $0 !~ /\.t$/;

    return 1;
}

=head2 disconnect_vm

Disconnect all the Virtual Managers connections.

=cut


sub disconnect_vm {
    my $self = shift;
    $self->_disconnect_vm();
    Ravada::VM::_clean_cache();
}

sub _disconnect_vm{
    my $self = shift;
    return $self->_connect_vm(0);
}

sub _connect_vm {
    my $self = shift;

    my $connect = shift;
    $connect = 1 if !defined $connect;

    my @vms;
    eval { @vms = $self->vm };
    warn $@ if $@ && $self->warn_error;
    return if $@ && $@ =~ /No VMs found/i;
    die $@ if $@;

    return if !scalar @vms;
    for my $n ( 0 .. $#{$self->vm}) {
        my $vm = $self->vm->[$n];

        if (!$connect) {
            $vm->disconnect() if $vm;
        } else {
            $vm->connect();
        }
    }
}

sub _create_vm_lxc {
    my $self = shift;

    return ;
}

sub _create_vm_void {
    my $self = shift;

    return Ravada::VM::Void->new( connector => ( $self->connector or $CONNECTOR ));
}

sub _create_vm($self, $type=undef) {

    # TODO: add a _create_vm_default for VMs that just are created with ->new
    #       like Void or LXC
    my %create = (
        'KVM' => \&_create_vm_kvm
        ,'LXC' => \&_create_vm_lxc
        ,'Void' => \&_create_vm_void
    );

    my @vms = ();
    my $err = '';

    my @vm_types = keys %VALID_VM;
    @vm_types = ($type) if defined $type;
    for my $vm_name (@vm_types) {
        my $vm;
        my $sub = $create{$vm_name}
            or confess "Error: Unknown VM $vm_name";
        eval { $vm = $sub->($self) };
        warn $@ if $@;
        $err.= $@ if $@;
        push @vms,$vm if $vm;
    }
    die "No VMs found: $err\n" if $self->warn_error && !@vms && $err;

    return [@vms, $self->_list_remote_vms];

}

sub _list_remote_vms($self ) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM vms WHERE hostname <> 'localhost'");
    $sth->execute;

    my @vms;

    while ( my $row = $sth->fetchrow_hashref) {
        my $vm;
        eval { $vm = Ravada::VM->open( $row->{id}) };
        push @vms,( $vm )   if $vm;
    }
    $sth->finish;

    return @vms;
}

sub _check_vms {
    my $self = shift;

    my @vm;
    eval { @vm = @{$self->vm} };
    for my $n ( 0 .. $#vm ) {
        if ($vm[$n] && ref $vm[$n] =~ /KVM/i) {
            if (!$vm[$n]->is_alive) {
                warn "$vm[$n] dead" if $DEBUG;
                $vm[$n] = $self->_create_vm_kvm();
            }
        }
    }
}

=head2 create_domain

Creates a new domain based on an ISO image or another domain.

  my $domain = $ravada->create_domain(
         name => $name
    , id_iso => 1
  );


  my $domain = $ravada->create_domain(
         name => $name
    , id_base => 3
  );


=cut


sub create_domain {
    my $self = shift;

    my %args = @_;

    my $request = $args{request};
    if ($request) {
        my %args_r = %{$request->args};
        delete $args_r{'at'};
        for my $field (keys %args_r) {
            confess "Error: Argument $field different in request "
                if $args{$field} && $args{$field} ne $args_r{$field};
            $args{$field} = $args_r{$field};
        }
    }
    my $vm_name = delete $args{vm};

    my $start = delete $args{start};
    my $id_base = $args{id_base};
    my $data = delete $args{data};
    my $id_owner = $args{id_owner} or confess "Error: missing id_owner ".Dumper(\%args);
    _check_args(\%args,qw(iso_file id_base id_iso id_owner name active swap memory disk id_template start remote_ip request vm add_to_pool options storage));

    confess "ERROR: Argument vm required"   if !$id_base && !$vm_name;

    my $vm;
    if ($vm_name) {
        $vm = $self->search_vm($vm_name);
        confess "ERROR: vm $vm_name not found"  if !$vm;
    }
    my $base;
    if ($id_base) {
        $base = Ravada::Domain->open($id_base)
            or confess "Unknown base id: $id_base";
        $vm = $base->_vm;

        my $net_bundle = $self->_net_bundle($base, $id_owner);
        if ($net_bundle) {
            unlock_hash(%args);
            $args{options}->{network} = $net_bundle->{name};
            lock_hash(%args);
        }
    }
    my $user = Ravada::Auth::SQL->search_by_id($id_owner)
        or confess "Error: Unkown user '$id_owner'";

    $request->status("creating machine")    if $request;

    unlock_hash(%args);
    my $swap = delete $args{swap};
    my $storage = delete $args{storage};
    lock_hash(%args);

    my $domain;
    eval { $domain = $vm->create_domain(%args, storage => $storage)};

    my $error = $@;
    if ( $request ) {
        $request->error(''.$error) if $error;
        if ($error =~ /has \d+ requests/) {
            $request->status('retry');
        }
        $request->id_domain($domain->id) if $domain;
    } elsif ($error) {
        die $error;
    }
    return if !$domain;
    my $req_add_swap = _req_add_disk($args{id_owner}, $domain->id,
        ,'swap', $swap ,$request, $storage);
    my $req_add_data = _req_add_disk($args{id_owner}, $domain->id
        ,'data', $data, ($req_add_swap or $request ), $storage);

    my $previous_req = ($req_add_data or $req_add_swap or $request);

    my $req_add_iso = _add_extra_iso($domain, $request,$previous_req);
    if ( $start ) {
        $previous_req = ($req_add_iso or $req_add_data or $req_add_swap
                or $request);
        _start_domain_after_create($domain, $request, $id_owner, $previous_req)
    }
    return $domain;
}

sub _req_add_disk($uid, $id_domain, $type, $size, $request, $storage=undef) {
    return if !$size;

    my $data = { size => $size, type => $type };
    $data->{storage}= $storage if $storage;

    my @after_req;
    if ($request) {
        @after_req = (after_request => $request->id);
    }
    return Ravada::Request->add_hardware(
        uid => $uid
        ,id_domain => $id_domain
        ,name => 'disk'
        ,data => $data
        ,@after_req
        ,at => time + 1
    );
}
sub _start_domain_after_create($domain, $request, $uid,$previous_request) {
    my $remote_ip;
    $remote_ip = $request->defined_arg('remote_ip') if $request;

    my @after_req;
    @after_req = (after_request => $previous_request->id );
    my $req_refresh = Ravada::Request->refresh_machine(
        uid => $uid
        ,id_domain => $domain->id
        ,@after_req
    );
    @after_req = (after_request => $req_refresh->id )
    if $req_refresh;

    my $req = Ravada::Request->start_domain(
        uid => $uid
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip
        ,at => time + 3
        ,@after_req
    );

}

sub _search_iso($id) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM iso_images"
        ." WHERE id = ? "
    );
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    return $row;
}

sub _add_extra_iso($domain, $request, $previous_request) {
    return if !$request;
    my $id_iso = $request->defined_arg('id_iso');
    return if !$id_iso;
    my $iso = _search_iso($id_iso);

    my $extra_iso = $iso->{extra_iso};
    return if !$extra_iso;

    $previous_request = $request if !$previous_request;

    my ($url, $file_re) = $extra_iso =~ m{(.*/)(.*)};
    my $volume = $domain->_vm->search_volume_path_re(qr($file_re));

    my $download = 0;
    if (!$volume) {
        my ($url_match) = $domain->_vm->_search_url_file($extra_iso);
        my ($device) = $url_match =~ m{.*/(.*)};
        die "Error: file not found in $extra_iso\n"
        if !$device;

        $volume = $domain->_vm->dir_img()."/$device";
        $download = 1 if $device;
    }
    my @after_request;
    @after_request = ( after_request => $previous_request->id )
    if $previous_request;

    my $req = Ravada::Request->refresh_storage(id_vm => $domain->_vm->id
                                        ,@after_request);

    @after_request = ( after_request => $req->id ) if $req;

    my $req_add = Ravada::Request->add_hardware(
        name => 'disk'
        ,uid => Ravada::Utils::user_daemon->id
        ,id_domain => $domain->id
        ,data => {
            file => $volume
            ,device => 'cdrom'
        }
        ,@after_request
        ,at => time+5
    );

    $domain->_vm->_download_file_external($extra_iso, $volume)
    if $download;

    return $req_add;
}

sub _check_args($args,@fields) {
    my %args_check = %$args;
    for my $field (@fields) {
        delete $args_check{$field};
    }
    confess "ERROR: Unknown arguments ".Dumper(\%args_check) if keys %args_check;
    lock_hash(%$args);
}

=head2 remove_domain

Removes a domain

  $ravada->remove_domain($name);

=cut

sub remove_domain {
    my $self = shift;
    my %arg = @_;

    my $name = delete $arg{name} or confess "Argument name required ";

    confess "Argument uid required "
        if !$arg{uid};

    lock_hash(%arg);

    my $sth = $CONNECTOR->dbh->prepare("SELECT id,vm FROM domains WHERE name = ?");
    $sth->execute($name);

    my ($id,$vm_type)= $sth->fetchrow;
    if (!$id) {
        warn "Error: Unknown domain $name, maybe already removed.\n";
        return;
    }

    my $user = Ravada::Auth::SQL->search_by_id( $arg{uid});
    die "Error: user id:$arg{uid} removed\n" if !$user;

    die "Error: user ".$user->name." can't remove domain $id"
        if !$user->can_remove_machine($id);

    my $domain0;
    eval {
        $domain0 = Ravada::Domain->open( $id );
        $domain0->shutdown_now($user) if $domain0 && $domain0->is_active;
    };
    warn "Warning: $@" if $@;

    my $vm = Ravada::VM->open(type => $vm_type);
    my $domain;
    eval { $domain = Ravada::Domain->open(id => $id, _force => 1, id_vm => $vm->id) };
    warn $@ if $@;
    if (!$domain) {
            warn "Warning: I can't find domain [$id ] '$name' in ".$vm->name.", maybe already removed.\n";
            Ravada::Domain::_remove_domain_data_db($id);
            return;
    };

    $domain->remove( $user);
}

=head2 search_domain

  my $domain = $ravada->search_domain($name);

=cut

sub search_domain($self, $name, $import = 0) {
    my $query =
         "SELECT d.id, d.id_vm "
        ." FROM domains d LEFT JOIN vms "
        ."      ON d.id_vm = vms.id "
        ." WHERE "
        ."    (d.name=? OR d.alias=?) "
        ;
    my $sth = $CONNECTOR->dbh->prepare($query);
    $sth->execute($name, $name);
    my ($id, $id_vm ) = $sth->fetchrow();

    return if !$id;
    if ($id_vm) {
        my $vm;
        my $vm_is_active;
        eval {
            $vm = Ravada::VM->open($id_vm);
            $vm_is_active = $vm->is_active if $vm;
        };
        warn $@ if $@;
        if ( $vm && !$vm_is_active) {
            eval {
                $vm->disconnect();
                $vm->connect;
            };
            warn $@ if $@;
        }
        if ($vm && $vm_is_active ) {
            my $domain;
            eval { $domain = $vm->search_domain($name)};
            warn $@ if $@;
            return $domain if $domain;
        }
    }
#    for my $vm (@{$self->vm}) {
#        warn $vm->name;
#        next if !$vm->is_active;
#        my $domain = $vm->search_domain($name, $import);
#        next if !$domain;
#        next if !$domain->_select_domain_db && !$import;
#        my $id_domain;
#        eval { $id_domain = $domain->id };
#        next if !$id_domain && !$import;
#
#        return $domain if $domain->is_active;
#    }
#    return if !$id;
    return Ravada::Domain->open($id);
}

=head2 search_domain_by_id

  my $domain = $ravada->search_domain_by_id($id);

=cut

sub search_domain_by_id($self, $id) {
    return Ravada::Domain->open($id);
}

=head2 list_vms

List all the Virtual Machine Managers

=cut

sub list_vms($self) {
    return @{$self->vm};
}

sub _list_vms_id($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms"
    );
    $sth->execute();
    my @vms;
    while (my ($id) = $sth->fetchrow) {
        push @vms,($id);
    }
    return @vms;
}

=head2 list_domains

List all created domains

  my @list = $ravada->list_domains();

This list can be filtered:

  my @active = $ravada->list_domains(active => 1);
  my @inactive = $ravada->list_domains(active => 0);

  my @user_domains = $ravada->list_domains(user => $id_user);

  my @user_active = $ravada->list_domains(user => $id_user, active => 1);

=cut

sub list_domains {
    my $self = shift;
    my %args = @_;

    my $active = delete $args{active};
    my $user = delete $args{user};

    die "ERROR: Unknown arguments ".join(",",sort keys %args)
        if keys %args;

    my $domains_data = $self->list_domains_data();

    my @domains;

    for my $row (@$domains_data) {
        my $domain =  Ravada::Domain->open($row->{id});
        next if !$domain;
        my $is_active;
        $is_active = $domain->is_active;
            if ( defined $active && !$domain->is_removed &&
                ( $is_active && !$active
                    || !$is_active && $active )) {
                next;
            }
            next if $user && $domain->id_owner != $user->id;

            push @domains,($domain);
    }
    return @domains;
}


=head2 list_domains_data

List all domains in raw format. Return a list of id => { name , id , is_active , is_base }

   my @list = $ravada->list_domains_data();

   $c->render(json => @list);

=cut

sub list_domains_data($self, %args ) {
    my @domains;

    my $where = '';
    my @values;
    for my $field ( sort keys %args ) {
        $where .= " AND " if $where;
        $where .= " $field = ? ";
        push @values,( $args{$field});
    }
    $where = " WHERE $where " if $where;
    my $query = "SELECT * FROM domains $where ORDER BY name";
    my $sth = $CONNECTOR->dbh->prepare($query);

    my $sth_hd = $CONNECTOR->dbh->prepare(
        "SELECT count(*) FROM host_devices_domain_locked "
        ." WHERE id_domain=?"
    );
    $sth->execute(@values);
    while (my $row = $sth->fetchrow_hashref) {
        $row->{date_changed} = 0 if !defined $row->{date_changed};
        $sth_hd->execute($row->{id});
        ($row->{host_devices})=$sth_hd->fetchrow;
        lock_hash(%$row);
        push @domains,($row);
    }
    $sth->finish;
    return @domains if wantarray;
    return \@domains;
}

# sub list_domains_data {
#     my $self = shift;
#     my @domains;
#     for my $domain ($self->list_domains()) {
#         eval { $domain->id };
#         warn $@ if $@;
#         next if $@;
#         push @domains, {                id => $domain->id
#                                     , name => $domain->name
#                                   ,is_base => $domain->is_base
#                                 ,is_active => $domain->is_active

#                            }
#     }
#     return \@domains;
# }


=head2 list_bases

List all base domains

  my @list = $ravada->list_domains();


=cut

sub list_bases {
    my $self = shift;
    my @domains;
    for my $vm (@{$self->vm}) {
        for my $domain ($vm->list_domains) {
            eval { $domain->id };
            confess $@ if $@;
            next    if $@;
            push @domains,($domain) if $domain->is_base;
        }
    }
    return @domains;
}

=head2 list_bases_data

List information about the bases

=cut

sub list_bases_data {
    my $self = shift;
    my @data;
    for ($self->list_bases ) {
        push @data,{ id => $_->id , name => $_->name };
    }
    return \@data;
}

=head2 list_images

List all ISO images

=cut

sub list_images {
    my $self = shift;
    my @domains;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM iso_images ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @domains,($row);
    }
    $sth->finish;
    return @domains;
}

=head2 list_images_data

List information about the images

=cut

sub list_images_data {
    my $self = shift;
    my @data;
    for ($self->list_images ) {
        push @data,{ id => $_->{id} , name => $_->{name} };
    }
    return \@data;
}


=pod

sub _list_images_lxc {
    my $self = shift;
    my @domains;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM lxc_templates ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @domains,($row);
    }
    $sth->finish;
    return @domains;
}

sub _list_images_data_lxc {
    my $self = shift;
    my @data;
    for ($self->list_images_lxc ) {
        push @data,{ id => $_->{id} , name => $_->{name} };
    }
    return \@data;
}

=cut

=head2 remove_volume

  $ravada->remove_volume($file);


=cut

sub remove_volume {
    my $self = shift;

    my $file = shift;
    my ($name) = $file =~ m{.*/(.*)};

    my $removed = 0;
    for my $vm (@{$self->vm}) {
        my $vol = $vm->search_volume($name);
        next if !$vol;

        $vol->delete();
        $removed++;
    }
    if (!$removed && -e $file ) {
        warn "volume $file not found. removing file $file.\n";
        unlink $file or die "$! $file";
    }

}

=head2 clean_old_requests

Before processing requests, old requests must be cleaned.

=cut

sub clean_old_requests {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM requests "
        ." WHERE status <> 'done' AND STATUS <> 'requested'"
    );
    $sth->execute;
    while (my ($id) = $sth->fetchrow) {
        my $req = Ravada::Request->open($id);
        $req->status("done","Killed ".$req->command." before completion");
    }

    $self->_clean_requests('refresh_vms');
    $self->_clean_requests('cleanup');
}

sub _clean_interrupted_downloads($self) {
    my $sth = $CONNECTOR->dbh->prepare("UPDATE iso_images "
        ." SET downloading=0 WHERE downloading=1"
    );
    $sth->execute();
}

=head2 process_requests

This is run in the ravada backend. It processes the commands requested by the fronted

  $ravada->process_requests();

=cut

sub process_requests {
    my $self = shift;
    my $debug = shift;
    my $dont_fork = shift;
    my $request_type = ( shift or 'all');
    confess "ERROR: Request type '$request_type' unknown, it must be long, huge, all"
            ." or priority"
        if $request_type !~ /^(long|huge|priority|all)$/;

    if (time - $TIMEOUT_REFRESH_REQUESTS > 60) {
        $TIMEOUT_REFRESH_REQUESTS = time;
        $self->_wait_pids();
        $self->_kill_stale_process();
        $self->_kill_dead_process();
        $self->_timeout_requests();
    }

    my $sth = $CONNECTOR->dbh->prepare("SELECT id,id_domain,command FROM requests "
        ." WHERE "
        ."    ( status='requested' OR status like 'retry%' OR status='waiting')"
        ."   AND ( at_time IS NULL  OR at_time = 0 OR at_time<=?) "
        ." ORDER BY date_req"
    );
    $sth->execute(time);

    my @reqs;
    my %duplicated;
    while (my ($id_request, $id_domain, $command)= $sth->fetchrow) {
        my $req;
        eval { $req = Ravada::Request->open($id_request) };

        next if $@ && $@ =~ /I can't find/;
        warn $@ if $@;
        next if !$req;

        if ($req->command eq 'ping_backend') {
            $req->status("done");
            next;
        }
        next if !$req->requirements_done;

        next if $request_type ne 'all' && $req->type ne $request_type;

        next if $duplicated{"id_req.$id_request"}++;

        $id_domain = $req->defined_arg('id_domain') if !defined $id_domain && $req->defined_arg('id_domain');

        next if defined $id_domain && $duplicated{$id_domain.".$command"}++;

        next if $req->command !~ /shutdown/i
            && $self->_domain_working($id_domain, $req);

        my $domain = '';
        $domain = $id_domain if $id_domain;
        $domain .= ($req->defined_arg('name') or '');

        next if $domain && $duplicated{$domain};
        my $id_base = $req->defined_arg('id_base');
        next if $id_base && $duplicated{$id_base};
        $duplicated{"domain.$domain"}++;
        push @reqs,($req);
    }
    $sth->finish;

    for my $req (sort { $a->priority <=> $b->priority } @reqs) {
        next if $req eq 'refresh_vms' && scalar@reqs > 2;
        next if $req eq 'refresh_vms' && $self->_processing_start();
        next if !$req->id;
        next if $req->status() =~ /^(done|working)$/;

        my $txt_retry = '';
        $txt_retry = " retry=".$req->retry if $req->retry;

        warn ''.localtime." [$request_type] $$ executing request id=".$req->id." ".
        "pid=".($req->pid or '')." ".$req->status()
            ."$txt_retry "
            .$req->command
            ." ".Dumper($req->args) if ( $DEBUG || $debug ) && $req->command ne 'set_time';

        my ($n_retry) = $req->status() =~ /retry (\d+)/;
        $n_retry = 0 if !$n_retry;

        $self->_execute($req, $dont_fork);
#        $req->status("done") if $req->status() !~ /retry/;
        next if !$DEBUG && !$debug;

        warn ''.localtime." req ".$req->id." , cmd: ".$req->command." ".$req->status()
            ." , err: '".($req->error or '')."'\n"  if ($DEBUG || $VERBOSE )
            && $req->command ne 'set_time';
            #        sleep 1 if $DEBUG;

    }

    my @reqs2 = grep { $_->command ne 'set_time' } @reqs;
    warn Dumper([map { $_->id." ".($_->pid or '')." ".$_->command." ".$_->status }
            grep { $_->id } @reqs2 ])
        if ($DEBUG || $debug ) && @reqs2;

    return scalar(@reqs);
}

sub _processing_start($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM requests WHERE "
        ." ( command = 'start' OR command='refresh_vms' OR command='clone')"
        ." AND status = 'working'"
    );
    $sth->execute();
    my ($id) = $sth->fetchrow;
    return $id;
}

sub _date_now($seconds = 0) {
    my @now = localtime(time + $seconds);
    $now[4]++;
    for (0 .. 4) {
        $now[$_] = "0".$now[$_] if length($now[$_])<2;
    }
    my $time_recent = ($now[5]+=1900)."-".$now[4]."-".$now[3]
        ." ".$now[2].":".$now[1].":".$now[0];

    return $time_recent;
}

sub _timeout_requests($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,pid, start_time, date_changed "
        ." FROM requests "
        ." WHERE ( status = 'working' or status = 'stopping' )"
        ."  AND date_changed >= ? "
        ."  AND command <> 'move_volume'"
        ." ORDER BY date_req "
    );
    $sth->execute(_date_now(-30));

    my @requests;
    while (my ($id, $pid, $start_time) = $sth->fetchrow()) {
        my $req = Ravada::Request->open($id);
        my $timeout = $req->defined_arg('timeout') or next;
        $start_time = 0 if !defined $start_time;
        next if time - $start_time <= $timeout;
        warn "request pid=".($req->pid or '<NULL>')." ".$req->command." timeout [".(time - $start_time)." <= $timeout";
        push @requests,($req);
    }
    $sth->finish;

    $self->_kill_requests(@requests);
}

sub _kill_requests($self, @requests) {
    for my $req (@requests) {
        $req->status('stopping');
        my @procs = $self->_process_sons($req->pid);
        if ( @procs) {
            for my $current (@procs) {
                my ($pid, $cmd) = @$current;
                my $signal = 15;
                $signal = 9 if $cmd =~ /<defunct>$/;
                warn "sending $signal to $pid $cmd";
                kill($signal, $pid);
            }
        }
        $req->stop();
    }
}

sub _process_sons($self, $pid) {
    return if !defined $pid;
    my @process;

    my $cmd = "ps -eo 'ppid pid cmd'";

    open my $ps,'-|', $cmd or die "$! $cmd";
    while (my $line = <$ps>) {
        warn "looking for $pid in ".$line if $line =~ /$pid/;
        my ($pid_son, $cmd) = $line =~ /^\s*$pid\s+(\d+)\s+(.*)/;
        next if !$pid_son;
        warn "$cmd\n";
        push @process,[$pid_son, $cmd] if $pid_son;
    }

    return @process;
}

=head2 process_long_requests

Process requests that take log time. It will fork on each one

=cut

sub process_long_requests {
    my $self = shift;
    my ($debug,$dont_fork) = @_;

    return $self->process_requests($debug, $dont_fork, 'long');
}

=head2 process_all_requests

Process all the requests, long and short

=cut

sub process_all_requests {

    my $self = shift;
    my ($debug,$dont_fork) = @_;

    return $self->process_requests($debug, $dont_fork,'all');

}

=head2 process_priority_requests

Process all the priority requests, long and short

=cut

sub process_priority_requests($self, $debug=0, $dont_fork=0) {

    return $self->process_requests($debug, $dont_fork,'priority');

}

sub _kill_stale_process($self) {

    if (!$TIMEOUT_STALE_PROCESS) {
        my @domains = $self->list_domains_data();
        $TIMEOUT_STALE_PROCESS = scalar(@domains)*5 + 60;
    }
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,pid,command,start_time "
        ." FROM requests "
        ." WHERE start_time<? "
        ." AND ( command = 'refresh_vms' or command = 'screenshot' or command = 'set_time' "
        ."      OR command = 'open_exposed_ports' OR command='remove' "
        ."      OR command = 'refresh_machine_ports'"
        ."      OR command = 'post_login'"
        .") "
        ." AND status <> 'done' "
        ." AND start_time IS NOT NULL "
    );
    $sth->execute(time - $TIMEOUT_STALE_PROCESS);
    while (my ($id, $pid, $command, $start_time) = $sth->fetchrow) {
        if (defined $pid && $pid == $$ ) {
            warn "HOLY COW! I should kill pid $pid stale for ".(time - $start_time)
                ." seconds, but I won't because it is myself";
            my $request = Ravada::Request->open($id);
            $request->status('done',"Stale process pid=$pid");
            next;
        }
        my $request = Ravada::Request->open($id);
        $request->stop();
     }
    $sth->finish;
}

sub _kill_dead_process($self) {

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,pid,command,start_time "
        ." FROM requests "
        ." WHERE start_time<? "
        ." AND ( status like 'working%' OR status like 'downloading%'"
        ."      OR status like 'start%' ) "
        ." AND pid IS NOT NULL "
        ." AND command <> 'move_volume'"
    );
    $sth->execute(time - 2);
    while (my ($id, $pid, $command, $start_time) = $sth->fetchrow) {
        next if -e "/proc/$pid";
        if ($pid == $$ ) {
            warn "HOLY COW! I should kill pid $pid stale for ".(time - $start_time)
                ." seconds, but I won't because it is myself";
            next;
        }
        my $request = Ravada::Request->open($id);
        $request->stop();
        warn "stopping ".$request->id." ".$request->command;
     }
    $sth->finish;
}


sub _domain_working {
    my $self = shift;
    my ($id_domain, $req) = @_;

    confess "Missing request" if !defined $req;

    if (!$id_domain) {
        $id_domain = $req->defined_arg('id_base');
        if (!$id_domain) {
            my $domain_name = $req->defined_arg('name');
            return if !$domain_name;
            my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM domains WHERE name=?");
            $sth->execute($domain_name);
            ($id_domain) = $sth->fetchrow;
            if (!$id_domain) {
                # TODO: maybe this request should be marked down because domain already removed
                return;
            }
        }
    }
    my $sth = $CONNECTOR->dbh->prepare("SELECT id, status FROM requests "
        ." WHERE id <> ? AND id_domain=? "
        ." AND (status <> 'requested' AND status <> 'done' AND status <> 'waiting' "
        ."      AND command <> 'set_base_vm'"
        ."      AND command <> 'set_time'"
        ."      AND command NOT LIKE 'refresh_machine%' "
        ."     )"
    );
    $sth->execute($req->id, $id_domain);
    my ($id, $status) = $sth->fetchrow;
#    warn "CHECKING DOMAIN WORKING "
#        ."[$id_request] id_domain $id_domain working in request ".($id or '<NULL>')
#            ." status: ".($status or '<UNDEF>');
    return $id;
}

sub _process_all_requests_dont_fork {
    my $self = shift;
    my $debug = shift;

    return $self->process_requests($debug,1, 'all');
}

sub _process_requests_dont_fork {
    my $self = shift;
    my $debug = shift;
    return $self->process_requests($debug, 'priority');
    return $self->process_requests($debug, 'long');
}

=head2 list_vm_types

Returnsa list ofthe types of Virtual Machines available on this system

=cut

sub list_vm_types {
    my $self = shift;

    my %type;
    for my $vm (@{$self->vm}) {
            my ($name) = ref($vm) =~ /.*::(.*)/;
            $type{$name}++;
    }
    return keys %type;
}

sub _stop_refresh($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM requests where status='working' "
        ." AND ( command like ? ) "
    );
    $sth->execute('refresh%');
    while ( my ($id) = $sth->fetchrow ) {
        eval {
            my $req = Ravada::Request->open($id);
            $req->stop;
        };

    }
}

sub _execute {
    my $self = shift;
    my $request = shift;
    my $dont_fork = shift;

    my $sub = $self->_req_method($request->command);

    if (!$sub) {
        $request->error("Unknown command ".$request->command);
        $request->status('done');
        return;
    }

    $request->status('working','') unless $request->status() eq 'waiting';
    $request->start_time(time);
    $request->error('');
    if ($dont_fork || !$CAN_FORK) {
        $self->_do_execute_command($sub, $request);
        return;
    }

    if ($request->command eq 'clone' || $request->command eq 'start') {
        $self->_stop_refresh();
    }

    $self->_wait_pids();
    return if !$self->_can_fork($request);

    my $pid = fork();
    die "I can't fork" if !defined $pid;

    if ( $pid == 0 ) {
        srand();
        $self->_do_execute_command($sub, $request);
        $CONNECTOR->disconnect();
        exit;
    }
    warn "$$ forked $pid\n" if $DEBUG;
    $self->_add_pid($pid, $request);
    $request->pid($pid);
}

sub _do_execute_command {
    my $self = shift;
    my ($sub, $request) = @_;

#    if ($DEBUG ) {
#        mkdir 'log' if ! -e 'log';
#        open my $f_out ,'>', "log/fork_$$.out";
#        open my $f_err ,'>', "log/fork_$$.err";
#        $| = 1;
#        local *STDOUT = $f_out;
#        local *STDERR = $f_err;
#    }

    $request->status('working','') unless $request->status() eq 'working';
    $request->pid($$);
    my $t0 = [gettimeofday];
    $request->lock_domain();
    eval {
        $sub->($self,$request);
    };
    my $err = ( $@ or '');
    my $elapsed = tv_interval($t0,[gettimeofday]);
    $request->run_time($elapsed);
    $request->unlock_domain();
    if ($err) {
        $request->error(''.$err);
        my $user = $request->defined_arg('user');
        if ($user && ref($user)) {
            my $subject = $err;
            my $message = '';
            if (length($subject) > 40 ) {
                $message = $subject;
                $subject = substr($subject,0,40);
                $user->send_message(Encode::decode_utf8($subject)
                    , Encode::decode_utf8($message));
            }
        }
    }
    if ($err && $err =~ /retry.?$/i) {
        my $retry = $request->retry;
        if (defined $retry && $retry>0) {
            my $wait_retry = $self->setting('/backend/wait_retry');
            $wait_retry = 10 if !$wait_retry;
            $request->status('requested');
            $request->at(time + $wait_retry);
            $request->retry($retry-1);
        } else {
            $request->status('done');
            $err =~ s/(.*?)retry.?/$1/i;
            $request->error($err)   if $err;
        }
    } else {
    $request->status('done')
        if $request->status() ne 'done'
            && $request->status() !~ /^retry/i;
    }
    $self->_set_domain_changed($request);
}

sub _set_domain_changed($self, $request) {
    my $id_domain = $request->id_domain;
    if (!defined $id_domain) {
        $id_domain = $request->defined_arg('id_domain');
    }
    return if !defined $id_domain;

    my $sth_date = $CONNECTOR->dbh->prepare("SELECT date_changed FROM domains WHERE id=?");
    $sth_date->execute($id_domain);
    my ($date) = $sth_date->fetchrow();

    my $sth = $CONNECTOR->dbh->prepare("UPDATE domains "
        ." set is_locked=0, date_changed=CURRENT_TIMESTAMP"
        ." WHERE id=? ");
    $sth->execute($id_domain);

    $sth_date->execute($id_domain);
    my ($date2) = $sth_date->fetchrow();

    if (defined $date && defined $date2 && $date2 eq $date) {
        my ($n) = $date2 =~ /.*(\d\d)$/;
        if (!defined $n) {
            sleep 1;
            $sth->execute($id_domain);
        } else {
            $n++;
            $n=00 if $n>59;
            $n = "0$n" if length($n)<2;
            $date2 =~ s/(.*)(\d\d)$/$1$n/;
            my $sth2 = $CONNECTOR->dbh->prepare("UPDATE domains set date_changed=?"
                ." WHERE id=? ");
            $sth2->execute($date2,$id_domain);
        }
    }
}

sub _cmd_manage_pools($self, $request) {
    my @domains;
    my $id_domain = $request->defined_arg('id_domain');
    my $uid = $request->defined_arg('uid');
    if (!$uid) {
        $uid = Ravada::Utils::user_daemon->id;
        $request->arg( uid => $uid );
    }
    confess if !defined $uid;
    if ($id_domain) {
        my $domain = Ravada::Domain->open($id_domain)
            or die "Error: missing domain ".$id_domain;
        push @domains,($domain);
    } else {
        push @domains, $self->list_domains;
    }
    for my $domain ( @domains ) {
        next if !$domain->pools();
        my @clone_pool = $domain->clones(is_pool => 1);
        my @reqs = grep {$_->command eq 'clone' } $domain->list_requests();
        my $n_clones = scalar(@clone_pool)+ scalar(@reqs);
        my $number = $domain->pool_clones() - $n_clones;
        if ($domain->_data('volatile_clones')) {
            $number = $domain->pool_start() - $n_clones;
        }
        if ($number > 0 ) {
            $self->_pool_create_clones($domain, $number, $request);
        }
        my $count_active = 0;
        for my $clone_data (@clone_pool) {
            last if $count_active >= $domain->pool_start;
            my $clone = Ravada::Domain->open($clone_data->{id}) or next;
            #            warn $clone->name." ".($clone->client_status or '')." is_active=".$clone->is_active
            #            ." is_volatile=".$clone->is_volatile." COUNT: $count_active >= "
            #    .$domain->pool_start."\n";
            if ( ! $clone->is_active ) {
                Ravada::Request->start_domain(
                    uid => $uid
                    ,id_domain => $clone->id
                );
                $count_active++;
            } else {
                my $status = $clone->client_status();
                $count_active++ if !$status
                                || $status =~ /disconnected/i;
            }
        }
    }
}

sub _cmd_discover($self, $request) {
    my $id_vm = $request->args('id_vm');
    my $vm = Ravada::VM->open($id_vm);
    return if !$vm;
    eval { return if !$vm->vm };
    my @list = $vm->discover();
    $request->output(encode_json(\@list));
}

sub _pool_create_clones($self, $domain, $number, $request) {
    my @arg_clone = ( );
    $request->status("cloning $number");
    if (!$domain->is_base) {
	my @requests = $domain->list_requests();
	return if grep { $_->command eq 'prepare_base' } @requests;
        $request->status("preparing base");
        my $req_base = Ravada::Request->prepare_base(
            uid => $request->args('uid')
            ,id_domain => $domain->id
        );
        push @arg_clone, ( after_request => $req_base->id ) if $req_base;
    }
    my $start = 0;
    $start = 1 if $domain->volatile_clones();
    Ravada::Request->clone(
        uid => $request->args('uid')
        ,id_domain => $domain->id
        ,number => $number
        ,add_to_pool => 1
        ,start => $start
        ,@arg_clone
    );
}

sub _cmd_screenshot {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->args('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);
    if (!$domain->can_screenshot) {
        die "I can't take a screenshot of the domain ".$domain->name;
    } else {
        $domain->screenshot();
        }
}

sub _cmd_copy_screenshot {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->args('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);

    my $id_base = $domain->id_base;
    my $base = $self->search_domain_by_id($id_base);

    if (!$domain->screenshot) {
        die "I don't have the screenshot of the domain ".$domain->name;
    } else {
        $base->_data(screenshot => $domain->_data('screenshot'));
    }
}

sub _upgrade_screenshots($self) {

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, file_screenshot FROM domains WHERE file_screenshot like '%' "
    );
    $sth->execute();

    my $sth_update = $CONNECTOR->dbh->prepare(
        "UPDATE domains set screenshot = ? WHERE id=?"
    );
    while ( my ($id, $name, $file_path)= $sth->fetchrow ) {
        next if ! -e $file_path;
        warn "INFO: converting screenshot from $name";
        my $file= new Image::Magick::Q16;
        $file->Read($file_path);
        my @blobs = $file->ImageToBlob(magick => 'png');
        eval {
            $sth_update->execute(encode_base64($blobs[0]), $id);
        };
        warn $@;
    }
}

sub _cmd_create{
    my $self = shift;
    my $request = shift;

    $request->status('creating machine');
    warn "$$ creating domain ".Dumper($request->args)   if $DEBUG;
    my $domain;

    if ( $request->defined_arg('id_base') ) {
        my $base = Ravada::Domain->open($request->args('id_base'));
        if ( $request->defined_arg('pool') ) {
            if ( $base->pools ) {
                $request->{args}->{id_domain} = delete $request->{args}->{id_base};
                $request->{args}->{uid} = delete $request->{args}->{id_owner};
                my $clone = $self->_cmd_clone($request);
                $request->id_domain($clone->id);
                return $clone;
            } else {
                confess "Error: this base has no pools";
            }
        }
    }

    $domain = $self->create_domain(request => $request);

    my $msg = '';

    if ($domain) {
       $msg = 'Machine'
            ." <a href=\"/machine/manage/".$domain->id.".html\">"
            .$request->args('name')."</a>"
            ." created."
        ;
        $request->id_domain($domain->id);#    if !$request->args('id_domain');
        $request->status('done',$msg);
    }


}

sub _cmd_list_host_devices($self, $request) {
    my $id_host_device = $request->defined_arg('id_host_device');
    my $id_node = $request->defined_arg('id_node');

    my @id_hd;

    if ( $id_host_device ) {
        @id_hd = ($id_host_device);
    }
    if ($id_node) {
        my $sth = $CONNECTOR->dbh->prepare(
            "SELECT id FROM host_devices "
            ." WHERE id_vm=? "
            ."   AND enabled=1"
        );
        $sth->execute($id_node);

        while ( my ($id_hd) = $sth->fetchrow ) {
            push @id_hd , ($id_hd );
        }
        return if !@id_hd;
    }
    if (!@id_hd) {
        my $sth = $CONNECTOR->dbh->prepare(
            "SELECT id,name FROM host_devices "
            ." WHERE enabled=1"
        );
        $sth->execute;
        while ( my ($id_hd, $name) = $sth->fetchrow ) {
            push @id_hd , ($id_hd );
        }
    }

    for my $id_hd (@id_hd) {
        my $hd = Ravada::HostDevice->search_by_id( $id_hd);
        next if !$hd;
        eval { $hd->list_devices_nodes };
        warn $@ if $@;
    }

}

sub _cmd_remove_host_device($self, $request) {
    my $id_host_device = $request->args('id_host_device');
    my $host_device = Ravada::HostDevice->search_by_id($id_host_device);

    my $id_domain = $request->defined_arg('id_domain');

    if ($id_domain) {
        my $domain = Ravada::Domain->open($id_domain);
        $domain->remove_host_device($host_device);
    } else {
        $host_device->remove;
    }
}

sub _can_fork {
    my $self = shift;
    my $req = shift or confess "Missing request";

    # don't wait for priority requests
    return if $req->type eq 'priority';

    my $type = $req->type;

    return 1 if !$self->{pids}->{$type};
    my %reqs = %{$self->{pids}->{$type}};

    for my $pid (keys %reqs) {
        my $id_req = $reqs{$pid};
        my $request;
        eval {
            $request = Ravada::Request->open($id_req)   if defined $id_req;
        };
        delete $reqs{$pid} if !$request || $request->status eq 'done';
    }
    my $n_pids = scalar(keys %reqs);
    return 1 if $n_pids < $req->requests_limit();

    my $msg = $req->command
                ." waiting for processes to finish"
                ." limit ".$req->requests_limit;

    warn $msg if $DEBUG;

    $req->error($msg);
    $req->at_time(time+10);
    $req->status('waiting') if $req->status() !~ 'waiting';
    $req->at_time(time+10);
    return 0;
}

sub _wait_child_pids() {
    for (;;) {
        my $pid = waitpid(0, WNOHANG);
        last if $pid<1;
    }
}

sub _wait_pids($self) {

    my @done;
    for my $type ( keys %{$self->{pids}} ) {
        for my $pid ( keys %{$self->{pids}->{$type}}) {
            next if kill(0,$pid);
            my $kid = waitpid($pid , WNOHANG);
            next if kill(0,$pid);
            push @done, ($pid) if $kid == $pid || $kid == -1;
        }
    }
    _wait_child_pids();
    return if !$CONNECTOR;
    return if !@done;
    for my $pid (@done) {
        my $id_req;
        for my $type ( keys %{$self->{pids}} ) {
            $id_req = $self->{pids}->{$type}->{$pid} if exists $self->{pids}->{$type}->{$pid};
            next if !$id_req;
            delete $self->{pids}->{$type}->{$pid};
            last;
        }
        next if !$id_req;
        my $request;
        eval { $request = Ravada::Request->open($id_req) };
        warn $@ if $@ && $@ !~ /I can't find id/;
        if ($request) {
            $request->status('done') if $request->status =~ /working/i;
        };
        warn("$$ request id=$id_req ".$request->command." ".$request->status()
            .", error='".($request->error or '')."'\n") if $DEBUG && $request && $request->command ne 'set_time';
    }
}

sub _add_pid($self, $pid, $request=undef) {

    my ($type, $id) = ('default',1);
    if ($request) {
        $type = $request->type;
        $id = $request->id;
    }
    $self->{pids}->{$type}->{$pid} = $id;

}

sub _list_pids($self) {
    my @alive;
    for my $type ( keys %{$self->{pids}} ) {
        for my $pid ( keys %{$self->{pids}->{$type}}) {
            push @alive, ($pid);
        }
    }
    return @alive;
}

sub _delete_pid {
    my $self = shift;
    my $pid = shift;

    for my $type ( keys %{$self->{pids}} ) {
        delete $self->{pids}->{$type}->{$pid}
    }
}

sub _cmd_remove {
    my $self = shift;
    my $request = shift;

    confess "Unknown user id ".$request->args->{uid}
        if !defined $request->args->{uid};

    $self->remove_domain(name => $request->args('name'), uid => $request->args('uid'));
}

sub _cmd_remove_clones($self, $request) {

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    my $id_domain = $request->args('id_domain');

    die "Error: user ".$user->name." not authorized to remove clones"
    unless $user->is_admin();

    my $domain = Ravada::Front::Domain->open($id_domain);
    for my $clone ( $domain->clones ) {
        Ravada::Request->remove_domain(
            uid => $uid
            ,name => $clone->{name}
        );
    }
}

sub _cmd_restore_domain($self,$request) {
    my $domain = Ravada::Domain->open($request->args('id_domain'));
    return $domain->restore(Ravada::Auth::SQL->search_by_id($request->args('uid')));
}

sub _cmd_pause {
    my $self = shift;
    my $request = shift;

    my $name = $request->args('name');
    my $domain = $self->search_domain($name);
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $self->_remove_unnecessary_downs($domain);

    $domain->pause($user);

    $request->status('done');

}

sub _cmd_resume {
    my $self = shift;
    my $request = shift;

    my $name = $request->args('name');
    my $domain = $self->search_domain($name);
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $self->_remove_unnecessary_downs($domain);
    $domain->resume(
        remote_ip => $request->args('remote_ip')
        ,user => $user
    );

    $request->status('done');

}


sub _cmd_open_iptables {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    my $domain = $self->search_domain_by_id($request->args('id_domain'));
    die "Unknown domain" if !$domain;

    $domain->open_iptables(
        remote_ip => $request->args('remote_ip')
        ,uid => $user->id
    );
}

sub _cmd_clone($self, $request) {

    return _req_clone_many($self, $request)
        if ( $request->defined_arg('number') && $request->defined_arg('number') > 1)
            || (! $request->defined_arg('name') && $request->defined_arg('add_to_pool'));

    my $domain = Ravada::Domain->open($request->args('id_domain'))
        or confess "Error: Domain ".$request->args('id_domain')." not found";

    my $args = $request->args();
    $args->{request} = $request;

    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'))
        or die "Error: User missing, id: ".$request->args('uid');
    $args->{user} = $user;
    for (qw(id_domain uid at number )) {
        delete $args->{$_};
    }

    my $name = $request->defined_arg('name');
    my $alias0 = ($request->defined_arg('alias') or $name);
    my $alias;
    ($name,$alias) = $self->_new_clone_name($domain, $user) if !$name;

    $alias = $alias0 if $alias0;

    $args->{alias} = $alias if $alias;

    my $net_bundle = $self->_net_bundle($domain, $user);

    $args->{options}->{network} = $net_bundle->{name} if $net_bundle;

    my $clone = $self->search_domain($name);
    die "Error: virtual machine ".$name." already exists "
    if $clone && $clone->id_owner != $user->id;

    if (!$clone) {
        my $volatile = $domain->volatile_clones;
        if (defined $args->{volatile}) {
            $volatile = $args->{volatile};
        }
        for my $try ( 1 .. 3 ) {
            eval {
                $clone = $domain->clone( name => $name ,%$args);
            };
            my $err = $@;
            warn $err if $err;
            next if $err && $err =~ /No field in .*_data/i;
            die $err if $err;
            last if $clone;
        }
    }

    $request->id_domain($clone->id) if $clone;
    my $req_next = $request;

    Ravada::Request->start_domain(
        uid => $user->id
        ,id_domain => $clone->id
        ,remote_ip => $request->defined_arg('remote_ip')
        ,after_request => $req_next->id
    ) if $clone && $request->defined_arg('start');

}

sub _net_bundle($self, $domain, $user0) {
    my $bundle = $domain->bundle();

    return unless $bundle && exists $bundle->{private_network}
    && $bundle->{private_network};

    my $user = $user0;
    $user = Ravada::Auth::SQL->search_by_id($user0) if !ref($user);

    my ($net) = grep { $_->{id_owner} == $user->id }
        $domain->_vm->list_virtual_networks();

    return $net if $net;

    my $req_new_net = Ravada::Request->new_network(
        uid => Ravada::Utils::user_daemon->id
        ,id_vm => $domain->_vm->id
        ,name => $bundle->{name}."-".$user->name
    );
    $self->_cmd_new_network($req_new_net);
    my $data = decode_json($req_new_net->output);
    $req_new_net->status('done');

    if ($bundle->{'isolated'}) {
        $data->{forward_mode} = 'none'
    } else {
        $data->{forward_mode} = 'nat'
    }

    my $req_network = Ravada::Request->create_network(
        uid => Ravada::Utils::user_daemon->id
        ,id_vm => $domain->_vm->id
        ,data => $data
    );
    $self->_cmd_create_network($req_network);
    $req_network->status('done');

    ($net) = grep { $_->{name} eq $data->{name} }
        $domain->_vm->list_virtual_networks();

    $domain->_vm->_update_network_db($net, {id_owner => $user->id });

    return $net;
}

sub _new_clone_name($self, $base,$user) {
    my $name;
    my $alias = $base->name;
    $alias = $base->_data('alias') if $base->_data('alias');
    my $user_name = Encode::decode_utf8($user->name);
    if ($user_name =~ /^[a-zA-Z0-9âêîôûáéíóúàèìòùäëïöüçñ'_\.\-€\$]+$/i) {
        $user_name = $base->_vm->_set_ascii_name(Encode::decode_utf8($user->name));
        $name = $base->name."-".$user_name;
        $alias .= "-".Encode::decode_utf8($user->name);
    } else {
        my $length = length($user->id);
        my $n =  '';
        $n = "0" x (4-$length) if $length < 4;
        $name = $base->name."-".$n.$user->id;
        $alias .= "-".Encode::decode_utf8($user->name);
    }
    return ($name,$alias) if !$self->_domain_exists($name);

    my $count =1;
    my $name2;
    for ( ;; ) {
        $name2 = "$name-".++$count;
        return $name2 if !$self->_domain_exists($name2);
    }
}

sub _domain_exists {
    return Ravada::Front::domain_exists(@_);
}

sub _get_last_used_clone_id
{
    my ($base_name, $domains) = @_;
    my $last_used_id = 0;
    foreach my $domain (@$domains)
    {
        next if ($domain->{is_base});
        $last_used_id = $1 if (($domain->{name} =~ m/^$base_name\-(\d+)$/) && ($1 > $last_used_id));
    }
    return $last_used_id;
}

sub _req_clone_many($self, $request) {
    my $args = $request->args();
    my $id_domain = $args->{id_domain};
    my $base = Ravada::Domain->open($id_domain) or die "Error: Domain '$id_domain' not found";
    my $number = ( delete $args->{number} or 1 );
    my $domains = $self->list_domains_data();
    my %domain_exists = map { $_->{name} => 1 } @$domains;

    if (!$base->is_base) {
        my $uid = $request->defined_arg('uid');
        confess Dumper($request) if !$uid;
        my $req_prepare = Ravada::Request->prepare_base(
                    id_domain => $base->id
                        , uid => $uid
                        ,_force => 1
        );
        $args->{after_request} = $req_prepare->id;
    }
    my @reqs;
    my $last_used_id = _get_last_used_clone_id($base->name, $domains);
    for ( 1 .. $number ) {
        my $n = $last_used_id + $_;
        my $name;
        for ( ;; ) {
            while (length($n) < length($number)) { $n = "0".$n };
            $name = $base->name."-".$n;
            last if !$domain_exists{$name}++;
            $n++;
        }
        $args->{name} = $name;
        my $req2 = Ravada::Request->clone( %$args );
        $args->{after_request} = $req2->id if $req2;
        push @reqs, ( $req2 );
    }
    return @reqs;
}

sub _cmd_start {
    my $self = shift;
    my $request = shift;

    my ($name, $id_domain);
    $name = $request->defined_arg('name');
    $id_domain = $request->defined_arg('id_domain');

    my $domain;
    $domain = $self->search_domain($name)               if $name;
    $domain = Ravada::Domain->open($id_domain)          if $id_domain;

    if(!$domain) {
        $self->_remove_inactive_gone($id_domain);
        die "Unknown machine '".($name or $id_domain)."'\n";
    }

    $domain->status('starting');

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $self->_remove_unnecessary_downs($domain);

    my @args = ( user => $user, request => $request );
    push @args, ( remote_ip => $request->defined_arg('remote_ip') )
        if $request->defined_arg('remote_ip');

    $domain->start(@args);

    Ravada::Request->manage_pools(
        uid => Ravada::Utils::user_daemon->id
    ) if $domain->is_pool && $request->defined_arg('remote_ip');

    my $msg = 'Machine'
            ." <a href=\"/machine/view/".$domain->id.".html\">"
            .$domain->name."</a>"
            ." started"
        ;
    $request->status('done', Encode::decode_utf8($msg));

}

sub _cmd_dettach($self, $request) {
    my $domain = Ravada::Domain->open($request->id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to dettach domain"
        if !$user->is_admin;

    $domain->dettach($user);
}

sub _cmd_rebase($self, $request) {
    my $domain = Ravada::Domain->open($request->id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to dettach domain"
        if !$user->is_admin;

    if ($domain->is_active) {
        my $req_shutdown = Ravada::Request->shutdown_domain(uid => $user->id, id_domain => $domain->id, timeout => 120);
        $request->after_request($req_shutdown->id);
        die "Warning: domain ".$domain->name." is up, retry.\n"
    }
    $request->status('working');

    my $id_base = $request->args('id_base')
    or confess "Error: missing id_base";
    my $new_base = Ravada::Domain->open($id_base)
        or confess "Error: domain $id_base not found";

    $domain->rebase($user, $new_base);
}


sub _cmd_start_clones {
    my $self = shift;
    my $request = shift;

    my $remote_ip = $request->args('remote_ip');
    my $id_domain = $request->defined_arg('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);
    die "Unknown domain '$id_domain'\n" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    my $sequential = $request->defined_arg('sequential');

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, is_base FROM domains WHERE id_base = ? AND is_base = 0 AND status <> 'active'"
    );
    $sth->execute($id_domain);
    my $id_req;
    while ( my ($id, $name, $is_base) = $sth->fetchrow) {
                my @after_request;
                @after_request = ( after_request => $id_req )
                if $sequential && $id_req;

                my $req = Ravada::Request->start_domain(
                    uid => $uid
                   ,id_domain => $id
                   ,remote_ip => $remote_ip
                   ,@after_request
               );
               $id_req = $req->id;
    }
}

sub _cmd_shutdown_clones {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->defined_arg('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);
    die "Unknown domain '$id_domain'\n" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, is_base FROM domains WHERE id_base = ?"
    );
    $sth->execute($id_domain);
    while ( my ($id, $name, $is_base) = $sth->fetchrow) {
        if ($is_base == 0) {
            my $domain2;
            my $is_active;
            eval {
                $domain2 = $self->search_domain_by_id($id);
                $is_active = $domain2->is_active if $domain2;
            };
            warn $@ if $@;
            if ($is_active) {
                my $req = Ravada::Request->shutdown_domain(
                    uid => $uid
                   ,id_domain => $domain2->id);
            }
        }
    }
}

sub _cmd_prepare_base {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->id_domain   or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $domain = $self->search_domain_by_id($id_domain);
    die "Unknown domain id '$id_domain'\n" if !$domain;

    my $user = Ravada::Auth::SQL->search_by_id( $uid)
        or confess "Error: Unknown user id $uid in request ".Dumper($request);

    die "User ".$user->name." [".$user->id."] not allowed to prepare base "
                .$domain->name."\n"
            unless $user->is_admin || (
                $domain->id_owner == $user->id && $user->can_create_base());


    my $with_cd = $request->defined_arg('with_cd');

    if ($domain->is_active) {
        my $req_shutdown = Ravada::Request->shutdown_domain(
            uid => $user->id
            ,id_domain => $domain->id
            ,timeout => 0
        );
        $request->after_request($req_shutdown->id);
        $request->at(time + 10);
        if ( !defined $request->retry() ) {
            $request->retry(5);
            $request->status("retry");
        } elsif($request->retry>0) {
            $request->retry($request->retry-1);
            $request->status("retry");
        }
        $request->error("Machine must be shut down ".$domain->name." [".$domain->id."]");
        return;
    }

    $self->_remove_unnecessary_request($domain);
    $self->_remove_unnecessary_downs($domain);
    return if $domain->is_base();

    $domain->prepare_base(user => $user, with_cd => $with_cd);
    $domain->is_public(1) if $request->defined_arg('publish');

}

sub _cmd_remove_base {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->id_domain or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);
    die "Unknown domain id '$id_domain'\n" if !$domain;

    die "User ".$user->name." [".$user->id."] not allowed to remove base "
                .$domain->name."\n"
            unless $user->is_admin || (
                $domain->id_owner == $user->id && $user->can_create_base());


    $domain->remove_base($user);

}

sub _cmd_spinoff($self, $request) {

    my $id_domain = $request->id_domain or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $domain->spinoff();

}



sub _cmd_hybernate {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid') or confess "Missing argument uid";
    my $id_domain = $request->id_domain or confess "Missing request id_domain";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = Ravada::Domain->open($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $domain->hybernate($user);

}

sub _cmd_download {
    my $self = shift;
    my $request = shift;

    my $id_iso = $request->args('id_iso')
        or confess "Missing argument id_iso";

    my $vm;
    $vm = Ravada::VM->open($request->args('id_vm')) if $request->defined_arg('id_vm');
    $vm = Ravada::VM->open(type => $request->args('vm'))
    if $request->defined_arg('vm');

    $vm = $self->search_vm('KVM')   if !$vm;

    my $delay = $request->defined_arg('delay');
    sleep $delay if $delay;
    my $verbose = $request->defined_arg('verbose');
    my $test = $request->defined_arg('test');

    my $iso = $vm->_search_iso($id_iso);
    if (!$test && $iso->{device} && -e $iso->{device}) {
        $request->status('done',"$iso->{device} already downloaded");
        return;
    }
    my $device_cdrom = $vm->_iso_name($iso, $request, $verbose);
    Ravada::Request->refresh_storage(id_vm => $vm->id);
}

sub _cmd_add_hardware {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $hardware = $request->args('name') or confess "Missing argument name";
    my $id_domain = $request->defined_arg('id_domain') or confess "Missing argument id_domain";

    my $domain = $self->search_domain_by_id($id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    die "Error: User ".$user->name." not allowed to add hardware to machine ".$domain->name
        unless $user->is_admin
            || ($hardware eq 'disk' && $user->can_create_disk )
        ;
    $self->_check_quota_disk($user,$request);

    $domain->set_controller($hardware, $request->defined_arg('number'), $request->defined_arg('data'));

    $self->_apply_clones($request);
}

sub _check_quota_disk($self, $user, $request) {
    return 1 if !$user->quota_disk();
    return 1 if $user->is_admin();

    my $quota
    = int(Ravada::Utils::size_to_number($user->quota_disk().'G')/1024/1024/1024);
    my $used = int($user->disk_used() / 1024 / 1024 / 1024 );
    my $size = ($request->args('data')->{size} or $request->args('data')->{capacity} or '10G');
    my $new = int(Ravada::Utils::size_to_number($size)/1024/1024/1024);
    die "Error: User ".$user->name." out of disk quota."
    ." Using: $used Gb"
    ." requested: $new Gb"
    ." Quota: $quota Gb"."\n"
    if $quota < ($used+$new);
}

sub _cmd_remove_hardware {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $hardware = $request->args('name') or confess "Missing argument name";
    my $id_domain = $request->defined_arg('id_domain') or confess "Missing argument id_domain";
    my $index = $request->defined_arg('index');
    my $option = $request->defined_arg('option');

    my $domain = $self->search_domain_by_id($id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    die "Error: User ".$user->name." not allowed to remove hardware from machine "
    .$domain->name
        if !$user->is_admin;

    $domain->remove_controller($hardware, $index, $option);

    $self->_apply_clones($request);
}

sub _cmd_change_hardware {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $hardware = $request->args('hardware') or confess "Missing argument hardware";
    my $id_domain = $request->args('id_domain') or confess "Missing argument id_domain";

    my $data = $request->defined_arg('data');
    my $domain = $self->search_domain_by_id($id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($uid);

    my $info = $domain->info($user);

    die "Error: User ".$user->name." not allowed\n"
    unless $user->is_admin
    || $hardware eq 'memory'
    || ($hardware eq 'network'
        && $user->can_change_hardware_network($domain, $data)
       )
    || ($hardware eq 'vcpus' && keys %$data == 1 && exists $data->{n_virt_cpu}
            && $data->{n_virt_cpu} <= $info->{max_virt_cpu})
    ;

    $domain->change_hardware(
         $request->args('hardware')
        ,$request->defined_arg('index')
        ,$data
    );
    $self->_apply_clones($request);
}

sub _apply_clones($self, $request) {

    my $id_domain = $request->args('id_domain') or confess "Missing argument id_domain";
    my $domain = Ravada::Front::Domain->open($id_domain);
    return if !$domain->is_base;

    my $args = $request->args;
    if ($request->command eq 'change_hardware') {
        my %fields = ('disk' => 'file'
            ,'display' => ['id','id_domain','id_domain_port']
        );
        my $field = $fields{$args->{hardware}};
        if ($field) {
            $field = [$field] if !ref($field);
            for my $curr_field (@$field) {
                delete $args->{data}->{$curr_field};
            }
        }
    }

    for my $clone ($domain->clones) {
        Ravada::Request->new_request(
            $request->command
            ,%$args
            ,id_domain => $clone->{id}
        );
    }
}

sub _cmd_shutdown {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $name = $request->defined_arg('name');
    my $id_domain = $request->defined_arg('id_domain');
    my $timeout = $request->defined_arg('timeout');
    my $id_vm = $request->defined_arg('id_vm');

    confess "ERROR: Missing id_domain or name" if !$id_domain && !$name;

    my $domain;
    if ($name) {
        if ($id_vm) {
            my $vm = Ravada::VM->open($id_vm);
            $domain = $vm->search_domain($name);
        } else {
            $domain = $self->search_domain($name);
        }
        die "Unknown domain '$name'\n" if !$domain;
    }
    if ($id_domain) {
        my $domain2 = Ravada::Domain->open(id => $id_domain, id_vm => $id_vm);
        die "ERROR: Domain $id_domain is ".$domain2->name." not $name."
            if $domain && $domain->name ne $domain2->name;
        $domain = $domain2;
        die "Unknown domain '$id_domain'\n" if !$domain
    }

    Ravada::Request->refresh_machine(
                   uid => $uid
            ,id_domain => $domain->id
        ,after_request => $request->id
    );
    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    $self->_remove_unnecessary_request($domain);
    $domain->shutdown(timeout => $timeout, user => $user
                    , request => $request);

}

sub _cmd_force_shutdown {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain');
    my $id_vm = $request->defined_arg('id_vm');

    my $domain;
    if ($id_vm) {
        my $vm = Ravada::VM->open($id_vm);
        $domain = $vm->search_domain_by_id($id_domain);
    } else {
        $domain = $self->search_domain_by_id($id_domain);
    }
    die "Unknown domain '$id_domain'\n" if !$domain;

    my $user = Ravada::Auth::SQL->search_by_id( $uid);
    die "Error: unknown user id=$uid in request= ".$request->id if !$user;

    $self->_remove_unnecessary_request($domain);
    $domain->force_shutdown($user,$request);

}

sub _cmd_reboot {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $name = $request->defined_arg('name');
    my $id_domain = $request->defined_arg('id_domain');
    my $timeout = ($request->args('timeout') or 60);
    my $id_vm = $request->defined_arg('id_vm');

    confess "ERROR: Missing id_domain or name" if !$id_domain && !$name;

    my $domain;
    if ($name) {
        if ($id_vm) {
            my $vm = Ravada::VM->open($id_vm);
            $domain = $vm->search_domain($name);
        } else {
            $domain = $self->search_domain($name);
        }
        die "Unknown domain '$name'\n" if !$domain;
    }
    if ($id_domain) {
        my $domain2 = Ravada::Domain->open(id => $id_domain, id_vm => $id_vm);
        die "ERROR: Domain $id_domain is ".$domain2->name." not $name."
            if $domain && $domain->name ne $domain2->name;
        $domain = $domain2;
        die "Unknown domain '$id_domain'\n" if !$domain
    }

    Ravada::Request->refresh_machine(
                   uid => $uid
            ,id_domain => $id_domain
        ,after_request => $request->id
    );
    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    $self->_remove_unnecessary_request($domain);
    $domain->reboot(timeout => $timeout, user => $user
                    , request => $request);

}

sub _cmd_shutdown_start($self, $request) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain');
    my $id_vm = $request->defined_arg('id_vm');

    my $domain;
    if ($id_vm) {
        my $vm = Ravada::VM->open($id_vm);
        $domain = $vm->search_domain_by_id($id_domain);
    } else {
        $domain = $self->search_domain_by_id($id_domain);
    }
    die "Unknown domain '$id_domain'\n" if !$domain;

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    die "USER $uid not authorized to restart machine ".$domain->name
    unless $domain->_data('id_owner') ==  $user->id || $user->is_operator;

    my $timeout = ($request->defined_arg('timeout') or $domain->_timeout_shutdown() or 60);

    for my $try ( 0 .. 1 ) {
        $domain->shutdown(timeout => $timeout, user => $user
                    , request => $request);

        for ( 0 .. $timeout+1 ) {
            last if !$domain->is_active;
            sleep 1;
        }
        last if !$domain->is_active;
    }

    my $req_shutdown = Ravada::Request->force_shutdown_domain(
        uid => $user->id
        ,id_domain => $domain->id
        ,after_request => $request->id
    );

    Ravada::Request->start_domain(
        uid => $user->id
        ,id_domain => $domain->id
        ,after_request => $req_shutdown->id
    );
}

sub _cmd_force_reboot {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain');
    my $id_vm = $request->defined_arg('id_vm');

    my $domain;
    if ($id_vm) {
        my $vm = Ravada::VM->open($id_vm);
        $domain = $vm->search_domain_by_id($id_domain);
    } else {
        $domain = $self->search_domain_by_id($id_domain);
    }
    die "Unknown domain '$id_domain'\n" if !$domain;

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    $self->_remove_unnecessary_request($domain);
    $domain->force_reboot($user,$request);

}


sub _cmd_list_vm_types {
    my $self = shift;
    my $request = shift;
    my @list_types = $self->list_vm_types();
    $request->result(\@list_types);
    $request->status('done');
}

sub _cmd_ping_backend {
    my $self = shift;
    my $request = shift;

    $request->status('done');
    return 1;
}

sub _cmd_rename_domain {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $name = $request->args('name');
    my $id_domain = $request->args('id_domain') or die "ERROR: Missing id_domain";

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = $self->search_domain_by_id($id_domain);

    confess "Unkown domain id=$id_domain ".Dumper($request)   if !$domain;

    $domain->rename(user => $user, name => $name);

}

sub _cmd_set_driver {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain') or die "ERROR: Missing id_domain";

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = $self->search_domain_by_id($id_domain);

    confess "Unkown domain ".Dumper($request)   if !$domain;

    die "USER $uid not authorized to set driver for domain ".$domain->name
        unless $user->can_change_settings($domain->id);

    $domain->set_driver_id($request->args('id_option'));
    $domain->needs_restart(1) if $domain->is_active;
}

sub _cmd_refresh_storage($self, $request=undef) {

    my @vm;
    if ($request && $request->defined_arg('id_vm')) {
	    push @vm,Ravada::VM->open($request->defined_arg('id_vm'));
    } else {
	    push @vm,(@{$self->vm});
    }
    for my $vm ( @vm ) {
        $vm->refresh_storage();
    }
}

sub _list_mnt($vm, $type) {
    my ($out, $err) = $vm->run_command("findmnt","-$type");
    my %tab;
    for my $line ( split /\n/,$out ) {
        my ($target) = $line =~ /^(.*?) /;
        next if $target eq 'TARGET';
        $tab{$target} = $line;
    }
    return %tab;
}

sub _search_partition($path, $tab) {
    confess if ref($path);
    my $curr_path = "";
    my $found='';
    for my $dir (split /\//,$path ) {
        $dir = "" if !defined $dir;
        $curr_path .= "/$dir";
        $curr_path =~ s{\/\/+}{/}g;
        next if !exists $tab->{$curr_path};
        my $curr_found = $tab->{$curr_path};
        $found = $curr_path if $curr_found && length($curr_found) > length($found);
    }
    return $found;
}

sub _check_mounted($path, $fstab, $mtab) {
    my $partition = _search_partition($path, $fstab);
    return 1 if exists $mtab->{$partition} && $mtab->{$partition};

    die "Error: partition $partition not mounted. Retry.\n";
}

sub _cmd_check_storage($self, $request) {
    my $contents = "a" x 160;
    for my $vm ( $self->list_vms ) {
        next if !$vm || !$vm->is_local;
        my %fstab = _list_mnt($vm,"s");
        my %mtab = _list_mnt($vm,"m");

        for my $storage ( $vm->list_storage_pools ) {
            next if $storage !~ /tst/;
            my $path = ''.$vm->_storage_path($storage);
            _check_mounted($path,\%fstab,\%mtab);
            my ($ok,$err) = $vm->write_file("$path/check_storage",$contents);
            die "Error on storage pool $storage : $err. Retry.\n" if $err;
        }
    }
}

sub _remove_inactive_gone($self,$id_domain) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT name,is_volatile "
        ." FROM domains "
        ." WHERE id=?"
    );
    $sth->execute($id_domain);
    my ($name,$is_volatile) = $sth->fetchrow;
    if ($is_volatile) {
        my $req = Ravada::Request->remove_domain(
            name => $name
            ,uid => Ravada::Utils::user_daemon->id
        );
        $self->_cmd_remove($req);
    }
}

sub _cmd_refresh_machine($self, $request) {

    my $id_domain = $request->args('id_domain');
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));

    # it may have been removed on shutdown when volatile
    my $domain = Ravada::Domain->open($id_domain);

    return $self->_remove_inactive_gone($id_domain) if !$domain;

    $domain->check_status();
    $domain->list_volumes_info();
    my $is_active = $domain->is_active;
    if (!$is_active) {
        $self->_remove_unnecessary_downs($domain);
        if ( $domain->is_volatile && !$domain->_volatile_active ) {
            $domain->remove(Ravada::Utils::user_daemon);
            return;
        }
        $domain->_fetch_networking_mode() if $domain->is_known();
    }
    $domain->info($user);
    $domain->client_status(1) if $is_active;
    $domain->_check_port_conflicts();

    Ravada::Request->refresh_machine_ports(id_domain => $domain->id, uid => $user->id
        ,timeout => 60, retry => 10)
    if $is_active && $domain->ip && $domain->list_ports;

    $domain->_unlock_host_devices() if !$is_active;

    if ($domain->autostart() ne $domain->_data('autostart')) {
        $domain->_data('autostart' => $domain->autostart());
    }
}

sub _cmd_refresh_machine_ports($self, $request) {
    my $id_domain = $request->args('id_domain');
    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = Ravada::Domain->open($id_domain) or confess "Error: domain $id_domain not found";

    die "USER $uid not authorized to refresh machine ports for domain ".$domain->name
    unless $domain->_data('id_owner') ==  $user->id || $user->is_operator
            || $user->can_start_machine($domain->id);

    return if !$domain->is_active;

    $domain->refresh_ports($request);
    $domain->client_status(1) if $domain->is_active;
}


sub _cmd_change_owner($self, $request) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain');
    my $sth = $CONNECTOR->dbh->prepare(
        "UPDATE domains SET id_owner=?"
        ." WHERE id=?"
    );
    $sth->execute($uid, $id_domain);
    $sth->finish;
}

sub _cmd_domain_autostart($self, $request ) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain') or die "ERROR: Missing id_domain";

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = $self->search_domain_by_id($id_domain);
    $domain->autostart($request->args('value'), $user);
}

sub _cmd_refresh_vms($self, $request=undef) {

    $self->_refresh_disabled_nodes( $request );
    $self->_refresh_down_nodes( $request );

    my $active_vm = $self->_refresh_active_vms();
    my $active_domain = $self->_refresh_active_domains($request);
    $self->_log_active_domains($active_domain);
    $self->_refresh_down_domains($active_domain, $active_vm);

    $self->_clean_requests('refresh_vms', $request);
    $self->_refresh_volatile_domains();

    $self->_check_duplicated_prerouting();
    $self->_check_duplicated_iptable();
    $request->error('')                             if $request;
}

sub _log_active_domains($self, $list) {
    my $active = 0;
    for my $key (keys %$list) {
            $active++ if $list->{$key}==1;
    }

    my $sth2 = $CONNECTOR->dbh->prepare(
        "INSERT INTO log_active_domains "
        ." (active,date_changed) "
        ." values(?,?)"
    );
    $sth2->execute(scalar($active),Ravada::Utils::date_now());
}

sub _cmd_shutdown_node($self, $request) {
    my $id_node = $request->args('id_node');
    my $node = Ravada::VM->open($id_node);
    $node->shutdown();
}

sub _cmd_start_node($self, $request) {
    my $id_node = $request->args('id_node');
    my $node;
    eval{ $node = Ravada::VM->open($id_node);
        $node->start() if$node;
    };
    Ravada::VM::_wake_on_lan($id_node) if !$node;
}

sub _cmd_connect_node($self, $request) {
    my $backend = $request->defined_arg('backend');
    my $hostname = $request->defined_arg('hostname');
    my $id_node = $request->defined_arg('id_node');

    my $node;

    if ($id_node) {
        $node = Ravada::VM->open(id => $id_node, force => 1);
        $hostname = $node->host if $node;
    } else {
        $node = Ravada::VM->open( type => $backend
            , host => $hostname
            , store => 0
        );
    }

    die "I can't ping $hostname\n"
        if !$node || ! $node->ping();

    $request->error("Ping ok. Trying to connect to $hostname");
    my ($out, $err);
    eval {
        ($out, $err) = $node->run_command('/bin/true');
    };
    $err = $@ if $@ && !$err;
    warn "out: $out" if $out;
    if ($err) {
        warn $err;
        $err =~ s/(.*?) at lib.*/$1/s;
        chomp $err;
        $err .= "\n";
        die $err if $err;
    }
    $node->connect() && do {
        $request->error("Connection OK");
        $node->_data('cached_down' => 0);
    };
}

sub _cmd_list_network_interfaces($self, $request) {

    my $vm_type = $request->args('vm_type');
    my $type = $request->defined_arg('type');
    my @type;
    @type = ( $type ) if $type;

    my $vm = Ravada::VM->open( type => $vm_type );
    my @ifs = $vm->list_network_interfaces( @type );

    $request->output(encode_json(\@ifs));
}

sub _cmd_list_storage_pools($self, $request) {
    my $id_vm = $request->args('id_vm');
    my $vm;
    if ($id_vm =~ /^\d+$/) {
        $vm = Ravada::VM->open( $id_vm );
    } else {
        $vm = Ravada::VM->open( type => $id_vm );
    }
    die "Error: vm '$id_vm' not found" if !$vm;

    my $data = $request->defined_arg('data');

    $request->output(encode_json([ $vm->list_storage_pools($data) ]));
}

sub _cmd_list_isos($self, $request){
    my $vm_type = $request->args('vm_type');

    my $vm = Ravada::VM->open( type => $vm_type );
    $vm->refresh_storage();
    my @isos = sort { "\L$a" cmp "\L$b" } $vm->search_volume_path_re(qr(.*\.iso$));

    $request->output(encode_json(\@isos));
}

sub _cmd_list_machine_types($self, $request) {
    my $id_vm = $request->defined_arg('id_vm');
    my $vm_type = $request->defined_arg('vm_type');
    my $vm;
    $vm = Ravada::VM->open(type => $vm_type) if $vm_type;
    $vm = Ravada::VM->open($id_vm) if $id_vm;
    die "Error: No id_vm nor vm_type defined ".Dumper($request->args)
    if !$id_vm && ! $vm_type;
    my %out = $vm->list_machine_types();
    $request->output(encode_json(\%out));
}

sub _cmd_list_cpu_models($self, $request) {

    my $id_domain = $request->args('id_domain');

    my $domain = Ravada::Domain->open($id_domain);
    return [] if !$domain->_vm->can_list_cpu_models();

    my $info = $domain->get_info();
    my $vm = $domain->_vm->vm;

    my @out = $domain->_vm->get_cpu_model_names('x86_64');
    $request->output(encode_json(\@out));
}


sub _cmd_set_time($self, $request) {
    my $id_domain = $request->args('id_domain');
    my $domain = Ravada::Domain->open($id_domain)
        or do {
            $request->retry(0);
            Ravada::Request->refresh_vms();
            die "Error: domain $id_domain not found\n";
        };
    return if !$domain->is_active;
    eval { $domain->set_time() };
    return if $@ =~ /Guest agent is not responding/ && $domain->get_info()->{ip};
    die "$@ , retry.\n" if $@;
}

sub _cmd_compact($self, $request) {
    my $id_domain = $request->args('id_domain');
    my $domain = Ravada::Domain->open($id_domain)
        or do {
            $request->retry(0);
            Ravada::Request->refresh_vms();
            die "Error: domain $id_domain not found\n";
        };

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    die "Error: user ".$user->name." not allowed to compact ".$domain->name
    unless $user->is_operator || $uid == $domain->_data('id_owner');

    $domain->compact($request);
}

sub _cmd_purge($self, $request) {
    my $id_domain = $request->args('id_domain');
    my $domain = Ravada::Domain->open($id_domain)
        or do {
            $request->retry(0);
            Ravada::Request->refresh_vms();
            die "Error: domain $id_domain not found\n";
        };

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    die "Error: user ".$user->name." not allowed to compact ".$domain->name
    unless $user->is_operator || $uid == $domain->_data('id_owner');

    $domain->purge($request);
}

sub _migrate_base($self, $domain, $id_node, $uid, $request) {
    if (ref($id_node)) {
        $id_node = $id_node->id;
    }
    my $base = Ravada::Domain->open($domain->id_base);
    return if $base->base_in_vm($id_node);

    my $req_base = Ravada::Request->set_base_vm(
        id_domain => $base->id
        , id_vm => $id_node
        , uid => $uid
        , retry => 10
    );
    confess "Error: no request for set_base_vm" if !$req_base;
    confess "Error: same request" if $req_base->id == $request->id;
    $request->retry(10) if !defined $request->retry();
    $request->after_request_ok($req_base->id);
    die "Base ".$base->name." still not prepared in node $id_node. Retry\n";
}

sub _cmd_migrate($self, $request) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain') or die "ERROR: Missing id_domain";

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = Ravada::Domain->open($id_domain)
        or confess "Error: domain $id_domain not found";

    die "Error: user ".$user->name." not allowed to migrate domain ".$domain->name
    unless $user->is_operator;

    my $node = Ravada::VM->open($request->args('id_node'));
    $self->_migrate_base($domain, $node, $uid, $request) if $domain->id_base;

    if ($domain->is_active) {
        if ($request->defined_arg('shutdown')) {
            my @timeout;
            @timeout = ( timeout => $request->defined_arg('shutdown_timeout') )
            if $request->defined_arg('shutdown_timeout');

            my $req_shutdown = Ravada::Request->shutdown_domain(
                uid => $uid
                ,id_domain => $id_domain
                ,@timeout
            );
            $request->after_request_ok($req_shutdown->id);
            $request->retry(10) if !defined $request->retry();
            die "Virtual Machine ".$domain->name." ".$request->retry." is active. Shutting down. Retry.\n";
        }
    }

    $self->_remove_unnecessary_downs($domain);
    $domain->migrate($node, $request);

    my @remote_ip;
    @remote_ip = ( remote_ip => $request->defined_arg('remote_ip'))
    if $request->defined_arg('remote_ip');

    $domain->start(user => $user, @remote_ip)
    if $request->defined_arg('start') && $domain->_vm->id == $node->id;

}

sub _cmd_rsync_back($self, $request) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain') or die "ERROR: Missing id_domain";

    my $domain = Ravada::Domain->open($id_domain);
    return if $domain->is_active || $domain->is_volatile;

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    die "Error: user ".$user->name." not allowed to migrate domain ".$domain->name
    unless $user->is_operator;

    my $node = Ravada::VM->open($request->args('id_node'));
    $domain->_rsync_volumes_back($node, $request);

}


sub _clean_requests($self, $command, $request=undef, $status='requested') {
    my $query = "DELETE FROM requests "
        ." WHERE command=? "
        ."   AND status=?";

    if ($status eq 'done') {
        my $date= Time::Piece->localtime(time - 300);
        $query .= " AND date_changed < ".$CONNECTOR->dbh->quote($date->ymd." ".$date->hms);
    }
    if ($request) {
        confess "Wrong request" if !ref($request) || ref($request) !~ /Request/;
        $query .= "   AND id <> ?";
    }
    my $sth = $CONNECTOR->dbh->prepare($query);

    if ($request) {
        $sth->execute($command, $status, $request->id);
    } else {
        $sth->execute($command, $status);
    }
}

sub _refresh_active_vms ($self) {

    my %active_vm;
    for my $id ($self->_list_vms_id) {
        my $vm;
        eval{ $vm = Ravada::VM->open($id) };
        next if !$vm;
        if ( !$vm->vm || !$vm->enabled() || !$vm->is_active ) {
            $vm->shutdown_domains();
            $active_vm{$vm->id} = 0;
            $vm->disconnect();
            next;
        }
        $active_vm{$vm->id} = 1;
        eval {
            $vm->list_virtual_networks();
        };
        warn $@ if $@;
    }
    return \%active_vm;
}

sub _refresh_active_domains($self, $request=undef) {
    my $id_domain;
    $id_domain = $request->defined_arg('id_domain')  if $request;
    my %active_domain;

        if ($id_domain) {
            my $domain;
            eval { $domain = $self->search_domain_by_id($id_domain) };
            if ( $@ ) {
                next if $@ =~ /not found/;
                warn $@;
            }
            $self->_refresh_active_domain($domain, \%active_domain)
            if $domain && !$domain->is_locked;
         } else {
            my @domains;
            eval { @domains = $self->list_domains_data };
            warn $@ if $@;
            my $t0 = time;
            for my $domain_data (sort { $b->{date_changed} cmp $a->{date_changed} }
                                @domains) {
                $request->output("checking $domain_data->{name}") if $request;
                next if $active_domain{$domain_data->{id}};
                my $domain;
                eval { $domain = Ravada::Domain->open($domain_data->{id}) };
                if ( $@ ) {
                    next if $@ =~ /not found/;
                    warn $@;
                }
                next if !$domain || $domain->is_locked;
                next if $domain->_volatile_active();

                $self->_refresh_active_domain($domain, \%active_domain);
                $self->_remove_unnecessary_downs($domain) if !$domain->is_active;
                last if !$CAN_FORK && time - $t0 > 10;
            }
            $request->error("checked ".scalar(@domains)) if $request;
        }
    return \%active_domain;
}

sub _refresh_down_nodes($self, $request = undef ) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms "
    );
    $sth->execute();
    while ( my ($id) = $sth->fetchrow()) {
        my $vm;
        eval { $vm = Ravada::VM->open($id) };
        warn $@ if $@;
        $vm->is_active() if $vm;
    }
}

sub _check_duplicated_prerouting($self, $request = undef ) {
    my $debug_ports = $self->setting('/backend/debug_ports');
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms WHERE is_active=1 "
    );
    $sth->execute();
    while ( my ($id) = $sth->fetchrow()) {
        my $vm;
        eval { $vm = Ravada::VM->open($id) };
        warn $@ if $@;
        if ($vm) {
            my $iptables;
            eval { $vm = $vm->iptables_list() };
            if ($@ ) {
                warn $@;
                next;
            }
            my %prerouting;
            my %already_open;
            my %already_clean;
            for my $line (@{$iptables->{'nat'}}) {
                my %args = @$line;
                next if $args{A} ne 'PREROUTING' || !$args{dport};
                my $port = $args{dport};
                for my $item ( 'dport' , 'to-destination') {
                    my $value = $args{$item} or next;
                    if ($prerouting{$value}) {
                        warn "clean duplicated prerouting "
                        .Dumper($prerouting{$value}, \%args)."\n" if $debug_ports;

                        $self->_reopen_ports($port) unless $already_open{$port}++;
                        $self->_delete_iptables_rule($vm,'nat', \%args);
                        $self->_delete_iptables_rule($vm,'nat', $prerouting{$port});
                    }
                    $prerouting{$value} = \%args;
                }
            }
        }
    }
}

sub _check_duplicated_iptable($self, $request = undef ) {
    my $debug_ports = $self->setting('/backend/debug_ports');
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms WHERE is_active=1 "
    );
    $sth->execute();
    while ( my ($id) = $sth->fetchrow()) {
        my $vm;
        eval { $vm = Ravada::VM->open($id) };
        warn $@ if $@;
        if ($vm) {
            my $iptables;
            eval { $iptables = $vm->iptables_list() };
            next if $@;
            my %dupe;
            my %already_open;
            for my $line (@{$iptables->{'filter'}}) {
                my %args = @$line;
                my $rule = join(" ", map { $_." ".$args{$_} }  sort keys %args);

                if ($dupe{$rule}) {
                    my %args2;
                    while (my ($key, $value) = each %args) {
                        $args2{"-$key"} = $value;
                    }
                    warn "clean duplicated iptables rule ".join(" ",%args2)."\n";
                    $self->_delete_iptables_rule($vm,'filter', \%args);
                }
                $dupe{$rule}++;

            }
        }
    }
}

sub _reopen_ports($self, $port) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT id_domain FROM domain_ports "
        ." WHERE public_port=?");
    $sth->execute($port);
    my ($id_domain) = $sth->fetchrow;
    return if !$id_domain;

    my $domain = Ravada::Domain->open($id_domain);
    Ravada::Request->open_exposed_ports(
               uid => Ravada::Utils::user_daemon->id
        ,id_domain => $id_domain
        ,_force => 1
        , retry => 20
    ) if $domain->is_active;
}

sub _delete_iptables_rule($self, $vm, $table, $rule) {
    my %delete = %$rule;
    my $chain = delete $delete{A};
    my $to_destination = delete $delete{'to-destination'};
    my $j = delete $delete{j};
    my @delete = ( t => $table, 'D' => $chain);

    for my $key ( qw(m p dport)) {
        push @delete ,($key => delete $delete{$key}) if $delete{$key};
    }
    push @delete,("j" => $j) if $j;
    push @delete,( 'to-destination' => $to_destination) if $to_destination;
    push @delete, %delete;

    $vm->iptables(@delete);

}

sub _refresh_disabled_nodes($self, $request = undef ) {
    my @timeout = ();
    @timeout = ( timeout => $request->args('timeout_shutdown') )
        if defined $request && $request->defined_arg('timeout_shutdown');

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT d.id, d.name, vms.name FROM domains d, vms "
        ." WHERE d.id_vm = vms.id "
        ."    AND ( vms.enabled = 0 || vms.is_active = 0 )"
        ."    AND d.status = 'active'"
    );
    $sth->execute();
    while ( my ($id_domain, $domain_name, $vm_name) = $sth->fetchrow ) {
        Ravada::Request->shutdown_domain( id_domain => $id_domain
            , uid => Ravada::Utils::user_daemon->id
            , @timeout
        );
        $request->status("Shutting down domain $domain_name in disabled node $vm_name");
    }
    $sth->finish;
}

sub _refresh_active_domain($self, $domain, $active_domain) {
    return if $domain->is_locked();
    $domain->check_status();

    return $self->_refresh_hibernated($domain) if $domain->is_hibernated();

    my $is_active = $domain->is_active();

    my $status = 'shutdown';
    if ( $is_active ) {
        $status = 'active';
        $domain->client_status(1);
    }
    $domain->_set_data(status => $status);
    $domain->info(Ravada::Utils::user_daemon)             if $is_active;
    $active_domain->{$domain->id} = $is_active;

    $domain->_post_shutdown()
    if $domain->_data('status') eq 'shutdown' && !$domain->_data('post_shutdown')
    && !$domain->_volatile_active;
}

sub _refresh_hibernated($self, $domain) {
    return unless $domain->is_hibernated();

    $domain->_post_hibernate() if !$domain->_data('post_hibernated');
}

sub _refresh_down_domains($self, $active_domain, $active_vm) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, id_vm FROM domains WHERE status='active'"
    );
    $sth->execute();
    while ( my ($id_domain, $name, $id_vm) = $sth->fetchrow ) {
        next if exists $active_domain->{$id_domain};

        my $domain;
        eval { $domain = Ravada::Domain->open($id_domain) };
        next if !$domain || $domain->is_hibernated;

        if (defined $id_vm && !$active_vm->{$id_vm} ) {
            $domain->_set_data(status => 'shutdown');
            $domain->_post_shutdown()
        } else {
            my $status = 'shutdown';
            $status = 'active' if $domain->is_active;
            $domain->_set_data(status => $status);
            for my $req ( $domain->list_requests ) {
                next if $req->command !~ /shutdown/i;
                $req->status('done');
            }
        }
        $domain->_post_shutdown()
        if $domain->_data('status') eq 'shutdown' && !$domain->_data('post_shutdown');
    }
}

sub _remove_unnecessary_request($self, $domain, $command = ['set_time', 'open_exposed_ports']) {
    $command = [$command] if !ref($command);
    my %remove = map { $_ => 1 } @$command;

    my @requests = $domain->list_requests(1);
    for my $req (@requests) {
        $req->status('done') if $remove{$req->command};
        $req->_remove_messages();
    }

}

sub _remove_unnecessary_downs($self, $domain) {

        my @requests = $domain->list_requests(1);
        for my $req (@requests) {
            $req->status('done')
                if $req->command =~ /shutdown/ && (!$req->at_time || $req->at_time <= time+180);
            $req->_remove_messages();
        }
}

sub _refresh_volatile_domains($self) {
   my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, id_vm, id_owner, vm FROM domains WHERE is_volatile=1 "
        ." AND date_changed < ? "
    );
    $sth->execute(Ravada::Utils::date_now(-$Ravada::Domain::TTL_REMOVE_VOLATILE));
    while ( my ($id_domain, $name, $id_vm, $id_owner, $type) = $sth->fetchrow ) {
        my $domain;
        eval { $domain = Ravada::Domain->open(id => $id_domain, _force => 1) } ;
        next if $domain && $domain->is_locked;
        if ( !$domain || $domain->status eq 'down' || !$domain->is_active) {
            if ($domain && !$domain->is_locked ) {
                Ravada::Request->shutdown_domain(
                    uid => $USER_DAEMON->id
                    ,id_domain => $id_domain
                );
            } else {
                my $user;
                eval { $user = Ravada::Auth::SQL->search_by_id($id_owner) };
                warn $@ if $@;
                if ($user && $user->is_temporary) {
                    cluck "Warning: temporary user id=$id_owner should already be removed";
                    $user->remove();
                }
            }
        }
    }
}

sub _cmd_remove_base_vm {
    return _cmd_set_base_vm(@_);
}

sub _cmd_set_base_vm {
    my $self = shift;
    my $request = shift;

    my $value = $request->args('value');
    die "ERROR: Missing value"                  if !defined $value;

    my $uid = $request->args('uid')             or die "ERROR: Missing uid";
    my $id_vm = $request->args('id_vm')         or die "ERROR: Missing id_vm";
    my $id_domain = $request->args('id_domain') or die "ERROR: Missing id_domain";

    eval {
        $self->_do_cmd_set_base_vm($uid, $id_vm, $id_domain, $value, $request);
    };
    my $err = $@;
    if ($err) {
        my $domain = Ravada::Front::Domain->open($id_domain);
        $domain->_set_base_vm_db($id_vm, (!$value or 0), 0);
        die $err;
    }
}

sub _do_cmd_set_base_vm($self, $uid, $id_vm, $id_domain, $value, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = Ravada::Domain->open($id_domain) or confess "Error: Unknown domain id $id_domain";

    #    my $domain = $self->search_domain_by_id($id_domain) or confess "Error: Unknown domain id: $id_domain";

    die "USER $uid not authorized to set base vm"
    if !$user->is_admin;

    $self->_migrate_base($domain, $id_vm, $uid, $request) if $domain->id_base;
    if ( $value && !$domain->is_base ) {
        $domain->prepare_base($user);
    }

    $domain->set_base_vm(
        id_vm => $id_vm
        ,user => $user
        ,value => $value
        ,request => $request
    );
}

sub _cmd_cleanup($self, $request) {
    $self->_clean_volatile_machines( request => $request);
    $self->_clean_temporary_users( );
    for my $cmd ( qw(cleanup enforce_limits refresh_vms
        manage_pools refresh_machine screenshot
        open_iptables ping_backend
        )) {
            $self->_clean_requests($cmd, $request,'done');
    }

}

sub _verify_connection($self, $domain) {
    for ( 1 .. 60 ) {
        my $status = $domain->client_status(1);
        if ( $status && $status ne 'disconnected' ) {
            return 1;
        }
    }
    return 0;
}

sub _domain_just_started($self, $domain) {
    my $sth = $CONNECTOR->dbh->prepare(
       "SELECT id,command,id_domain,args "
        ." FROM requests "
        ." WHERE start_time>? "
        ." OR status <> 'done' "
        ." OR start_time IS NULL "
    );
    my $start_time = time - 300;
    $sth->execute($start_time);
    while ( my ($id, $command, $id_domain, $args) = $sth->fetchrow ) {
        next if $command !~ /create|clone|start|open/i;
        return 1 if defined $id_domain && $id_domain == $domain->id;
        my $args_h = decode_json($args);
        return 1 if exists $args_h->{id_domain} && defined $args_h->{id_domain}
        && $args_h->{id_domain} == $domain->id;
        return 1 if exists $args_h->{name} && defined $args_h->{name}
        && $args_h->{name} eq $domain->name;
    }
    return 0;
}

sub _shutdown_disconnected($self) {
    for my $dom ( $self->list_domains_data(status => 'active') ) {
        next if !$dom->{shutdown_disconnected};
        my $domain = Ravada::Domain->open($dom->{id}) or next;
        my $is_active = $domain->is_active;
        my ($req_shutdown) = grep { $_->command eq 'shutdown'
            && $_->defined_arg('check')
            && $_->defined_arg('check') eq 'disconnected'
        } $domain->list_requests(1);

        if ($is_active && $domain->client_status eq 'disconnected') {
            next if $self->_domain_just_started($domain) || $self->_verify_connection($domain);
            next if $req_shutdown;
            next if !$domain->check_grace('connected');
            Ravada::Request->shutdown_domain(
                uid => Ravada::Utils::user_daemon->id
                ,id_domain => $domain->id
                ,at => time + 60
                ,check => 'disconnected'
            );
            my $user = Ravada::Auth::SQL->search_by_id($domain->id_owner);
            $user->send_message("The virtual machine has been disconnected for too long. Shutting down ".$dom->{name});
        } elsif ($req_shutdown) {
            $req_shutdown->status('done','Canceled') if $req_shutdown;
        }
    }
}

sub _req_method {
    my $self = shift;
    my  $cmd = shift;

    my %methods = (

          clone => \&_cmd_clone
         ,start => \&_cmd_start
  ,start_clones => \&_cmd_start_clones
,shutdown_clones => \&_cmd_shutdown_clones
         ,pause => \&_cmd_pause
        ,create => \&_cmd_create
        ,remove => \&_cmd_remove
        ,remove_domain => \&_cmd_remove
        ,remove_clones => \&_cmd_remove_clones
        ,restore_domain => \&_cmd_restore_domain
        ,resume => \&_cmd_resume
       ,dettach => \&_cmd_dettach
       ,cleanup => \&_cmd_cleanup
      ,download => \&_cmd_download
      ,shutdown => \&_cmd_shutdown
      ,reboot => \&_cmd_reboot
     ,hybernate => \&_cmd_hybernate
    ,set_driver => \&_cmd_set_driver
    ,screenshot => \&_cmd_screenshot
    ,add_disk => \&_cmd_add_disk
    ,copy_screenshot => \&_cmd_copy_screenshot
   ,cmd_cleanup => \&_cmd_cleanup

   ,remove_base => \&_cmd_remove_base
   ,spinoff => \&_cmd_spinoff
   ,set_base_vm => \&_cmd_set_base_vm
,remove_base_vm => \&_cmd_set_base_vm

   ,refresh_vms => \&_cmd_refresh_vms
  ,ping_backend => \&_cmd_ping_backend
  ,prepare_base => \&_cmd_prepare_base
 ,rename_domain => \&_cmd_rename_domain
 ,open_iptables => \&_cmd_open_iptables
 ,list_vm_types => \&_cmd_list_vm_types
 ,list_machine_types => \&_cmd_list_machine_types
 ,list_cpu_models => \&_cmd_list_cpu_models
,enforce_limits => \&_cmd_enforce_limits
,force_shutdown => \&_cmd_force_shutdown
,force_shutdown_domain => \&_cmd_force_shutdown
,force_reboot   => \&_cmd_force_reboot
,shutdown_start => \&_cmd_shutdown_start
        ,rebase => \&_cmd_rebase

,refresh_storage => \&_cmd_refresh_storage
,check_storage => \&_cmd_check_storage
,refresh_machine => \&_cmd_refresh_machine
,refresh_machine_ports => \&_cmd_refresh_machine_ports
,domain_autostart=> \&_cmd_domain_autostart
,change_owner => \&_cmd_change_owner
,add_hardware => \&_cmd_add_hardware
,remove_hardware => \&_cmd_remove_hardware
,change_hardware => \&_cmd_change_hardware
,set_time => \&_cmd_set_time
,compact => \&_cmd_compact
,purge => \&_cmd_purge
,backup => \&_cmd_backup
,restore_backup => \&_cmd_restore_backup

,list_storage_pools => \&_cmd_list_storage_pools
,active_storage_pool => \&_cmd_active_storage_pool
,create_storage_pool => \&_cmd_create_storage_pool

# Domain ports
,expose => \&_cmd_expose
,remove_expose => \&_cmd_remove_expose
,open_exposed_ports => \&_cmd_open_exposed_ports
,close_exposed_ports => \&_cmd_close_exposed_ports
# Virtual Managers or Nodes
    ,shutdown_node  => \&_cmd_shutdown_node
    ,start_node  => \&_cmd_start_node
    ,connect_node  => \&_cmd_connect_node
    ,migrate => \&_cmd_migrate
    ,rsync_back => \&_cmd_rsync_back

    #users
    ,post_login => \&_cmd_post_login

    #networks
    ,list_network_interfaces => \&_cmd_list_network_interfaces

    #isos
    ,list_isos => \&_cmd_list_isos

    ,manage_pools => \&_cmd_manage_pools
    ,list_host_devices => \&_cmd_list_host_devices
    ,remove_host_device => \&_cmd_remove_host_device

    ,discover => \&_cmd_discover
    ,import_domain => \&_cmd_import
    ,list_unused_volumes => \&_cmd_list_unused_volumes
    ,remove_files => \&_cmd_remove_files
    ,move_volume => \&_cmd_move_volume
    ,update_iso_urls => \&_cmd_update_iso_urls

    ,list_networks => \&_cmd_list_virtual_networks
    ,new_network => \&_cmd_new_network
    ,create_network => \&_cmd_create_network
    ,remove_network => \&_cmd_remove_network
    ,change_network => \&_cmd_change_network

    );
    return $methods{$cmd};
}

=head2 open_vm

Opens a VM of a given type


  my $vm = $ravada->open_vm('KVM');

=cut

sub open_vm {
    return search_vm(@_);
}

=head2 search_vm

Searches for a VM of a given type

  my $vm = $ravada->search_vm('kvm');

=cut

sub search_vm {
    my $self = shift;
    my $type = shift;
    my $host = (shift or 'localhost');

    confess "Missing VM type"   if !$type;

    my $class = 'Ravada::VM::'.uc($type);

    if ($type =~ /Void/i) {
        return Ravada::VM::Void->new(host => $host);
    }

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms "
        ." WHERE vm_type = ? "
        ."   AND hostname=?"
    );
    $sth->execute($type, $host);
    my ($id) = $sth->fetchrow();
    my $vm;
    $vm = Ravada::VM->open($id)    if $id;
    return if $host eq 'localhost' && $vm && !$vm->vm;

    return if $host ne 'localhost';

    my $vms = $self->_create_vm($type);

    for my $vm (@$vms) {
        return $vm if ref($vm) eq $class && $vm->host eq $host;
    }
    return;
}

=head2 vm

Returns the list of Virtual Managers

=cut

sub vm($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms WHERE is_active=1"
    );
    $sth->execute();
    my @vms;
    while ( my ($id) = $sth->fetchrow()) {
        my $vm;
        eval {
            $vm = Ravada::VM->open($id);
        };
        if ( $@ ) {
            warn $@;
            next;
        }
        eval {
            push @vms, ( $vm ) if $vm && $vm->vm;
        };
    };
    return [@vms] if @vms;
    return $self->_create_vm();

}

=head2 import_domain

Imports a domain in Ravada

    my $domain = $ravada->import_domain(
                            vm => 'KVM'
                            ,name => $name
                            ,user => $user_name
                            ,spinoff_disks => 1
    );

=cut

sub import_domain {
    my $self = shift;
    my %args = @_;

    my $vm_name = delete $args{vm} or die "ERROR: mandatory argument vm required";
    my $name = delete $args{name} or die "ERROR: mandatory argument domain name required";
    my $user_name = delete $args{user} or die "ERROR: mandatory argument user required";
    my $spinoff_disks = delete $args{spinoff_disks};
    $spinoff_disks = 1 if !defined $spinoff_disks;
    my $import_base = delete $args{import_base};

    confess "Error : unknown args ".Dumper(\%args) if keys %args;

    my $vm = $self->search_vm($vm_name) or die "ERROR: unknown VM '$vm_name'";
    my $user = Ravada::Auth::SQL->new(name => $user_name);
    die "ERROR: unknown user '$user_name'" if !$user || !$user->id;

    my $domain;
    eval { $domain = $self->search_domain($name) };
    die "ERROR: Domain '$name' already in RVD"  if $domain;

    return $vm->import_domain($name, $user, $spinoff_disks, $import_base);
}

sub _cmd_enforce_limits($self, $request=undef) {
    _enforce_limits_active($self, $request);
    $self->_shutdown_disconnected();
    $self->_shutdown_bookings() if $self->setting('/backend/bookings');
}

sub _shutdown_bookings($self) {
    my @bookings = Ravada::Booking::bookings();
    return if !scalar(@bookings);

    my @domains = $self->list_domains_data(status => 'active');
    for my $dom ( @domains ) {
        next if $dom->{autostart};
        next if $self->_user_is_admin($dom->{id_owner});

        if ( Ravada::Booking::user_allowed($dom->{id_owner}, $dom->{id_base}, $dom->{host_devices})
            && Ravada::Booking::user_allowed($dom->{id_owner}, $dom->{id}, $dom->{host_devices})
        ) {
            #warn "\tuser $dom->{id_owner} allowed to start clones from $dom->{id_base}";
            next;
        }

        my $user = Ravada::Auth::SQL->search_by_id($dom->{id_owner});
        $user->send_message("The server is booked. Shutting down ".$dom->{name});
        Ravada::Request->shutdown_domain(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain => $dom->{id}
        );
    }
}

sub _user_is_admin($self, $id_user) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT is_admin FROM users where id=? ");
    $sth->execute($id_user);
    my ($is_admin) = $sth->fetchrow;
    return $is_admin;
}

sub _enforce_limits_active($self, $request) {
    confess if !$request;
    my $timeout = ($request->defined_arg('timeout') or 10);
    my $start_limit_default = $self->setting('/backend/start_limit');

    my %domains;
    for my $domain ($self->list_domains( active => 1 )) {
        next if $domain->is_in_bundle();
        push @{$domains{$domain->id_owner}},$domain;
        $domain->client_status();
    }
    for my $id_user(keys %domains) {
        my $user = Ravada::Auth::SQL->search_by_id($id_user);
        my %grants;
        %grants = $user->grants() if $user;
        my $start_limit = (defined($grants{'start_limit'}) && $grants{'start_limit'} > 0) ? $grants{'start_limit'} : $start_limit_default;

        next if scalar @{$domains{$id_user}} <= $start_limit;
        next if $user && $user->is_admin;
        next if $user && $user->can_start_many;

        my @domains_user = sort { $a->start_time <=> $b->start_time
                                    || $a->id <=> $b->id }
                        @{$domains{$id_user}};

#        my @list = map { $_->name => $_->start_time } @domains_user;
        my $active = scalar(@domains_user);
        DOMAIN: for my $domain (@domains_user) {
            last if $active <= $start_limit;
            for my $request ($domain->list_requests) {
                next DOMAIN if $request->command =~ /shutdown/;
            }
            if ($domain->is_pool) {
                $domain->id_owner(Ravada::Utils::user_daemon->id);
                $domain->_data(comment => '');
                Ravada::Request->shutdown(user => Ravada::Utils::user_daemon->id
                    ,id_domain => $domain->id
                );
                return;
            }
            $user->send_message("Too many machines started. $active out of $start_limit. Stopping ".$domain->name) if $user;
            $active--;
            if ($domain->can_hybernate && !$domain->is_volatile) {
                $domain->hybernate($USER_DAEMON);
            } else {
                $domain->shutdown(timeout => $timeout, user => $USER_DAEMON );
            }
        }
    }
}

sub _clean_temporary_users($self) {
    my $sth_users = $CONNECTOR->dbh->prepare(
        "SELECT u.id, d.id, u.date_created"
        ." FROM users u LEFT JOIN domains d "
        ." ON u.id = d.id_owner "
        ." WHERE u.is_temporary = 1 AND u.date_created < ?"
    );

    my $one_day = _date_now(-24 * 60 * 60);
    $sth_users->execute( $one_day );
    while ( my ( $id_user, $id_domain, $date_created ) = $sth_users->fetchrow ) {
        next if $id_domain;
        my $user;
        eval { $user = Ravada::Auth::SQL->search_by_id($id_user) };
        warn $@ if $@;
        $user->remove() if $user;
    }
}

sub _clean_volatile_machines($self, %args) {
    my $request = delete $args{request};

    confess "ERROR: Unknown arguments ".join(",",sort keys %args)
        if keys %args;

    my $sth_remove = $CONNECTOR->dbh->prepare("DELETE FROM domains where id=?");
    for my $domain ( $self->list_domains_data( is_volatile => 1 )) {
        my $domain_real = Ravada::Domain->open(
            id => $domain->{id}
            ,_force => 1
        );
        if ($domain_real) {
            next if $domain_real->domain && $domain_real->is_active;
            next if $domain_real->is_locked;
            next if $domain_real->_volatile_active;
            eval { $domain_real->_post_shutdown() };
            warn $@ if $@;
            eval { $domain_real->remove($USER_DAEMON) };
            warn $@ if $@;
        } elsif ($domain->{id_owner}) {
            my $user;
            eval { $user = Ravada::Auth::SQL->search_by_id($domain->{id_owner})};
            warn $@ if $@;
            $user->remove() if $user && $user->is_temporary;
        }

        $sth_remove->execute($domain->{id});
    }
}

sub _cmd_post_login($self, $request) {
    my $user = Ravada::Auth::SQL->new(name => $request->args('user'));
    $user->unshown_messages();
    $self->_post_login_locale($request);
    $self->_check_tls_date($user) if $user->is_admin;
}

sub _check_tls_date($self, $user) {
    return if !$user->is_admin;
    my $sth = $CONNECTOR->dbh->prepare("SELECT name,tls FROM vms");
    $sth->execute();
    while (my ($name,$tls) = $sth->fetchrow ) {
        next if !$tls;
        my $tls_h = {};
        eval {
            $tls_h = decode_json($tls);
        };
        warn "Warning: error decoding tls for $name '$tls' $@" if $@;
        next if !keys %$tls_h;
        my $not_after = $tls_h->{notAfter};
        next if !$not_after;
        my $date;
        eval { $date = DateTime::Format::DateParse->parse_datetime($not_after) };

        if($date) {
            my $duration = $date-DateTime->now;
            my ($years, $months, $days) = $duration->in_units('years','months','days');
            if ($years<1 && $months<1) {
                if ($years<0 || $months<0 || $days<=0 ) {
                    $not_after =~ s/(.*) \d+:\d+:\d+(.*)/$1$2/;
                    $user->send_message("Critical: TLS certificate for $name expired on $not_after");
                }elsif ($days<7) {
                    $user->send_message("Critical: TLS certificate for $name has only $days days left. $not_after");
                } elsif ($days<30) {
                    $user->send_message("Warning: TLS certificate for $name has only $days days left. $not_after");
                }
            }
        }

    }
}

sub _post_login_locale($self, $request) {
    return if ! $request->defined_arg('locale');

    my @locales;

    my $locales = $request->args('locale');
    if (ref($locales)) {
        @locales = @$locales;
    } else {
        @locales = $locales;
    }
    for my $locale ( @locales ) {
        Ravada::Repository::ISO::insert_iso_locale($locale);
    }
}

sub _cmd_expose($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));

    die "Error: access denied to expose ports for ".$user->name
    if !$user->can_expose_ports($request->id_domain);

    my $domain = Ravada::Domain->open($request->id_domain);
    $domain->expose(
               port => $request->args('port')
              ,name => $request->defined_arg('name')
           ,id_port => $request->defined_arg('id_port')
        ,restricted => $request->defined_arg('restricted')
    );
}

sub _cmd_remove_expose($self, $request) {
    my $domain = Ravada::Domain->open($request->id_domain);
    $domain->remove_expose($request->args('port'));
}

sub _cmd_open_exposed_ports($self, $request) {
    my $domain = Ravada::Domain->open($request->id_domain) or return;
    return if !$domain->list_ports();

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id( $uid )
        or die "Error: user $uid not found";

    die "Error: user ".$user->name." not authorized to open ports"
    unless $user->is_admin || $domain->_data('id_owner') == $uid
        || $user->can_start_machine($domain);

    my $remote_ip = $request->defined_arg('remote_ip');

    $domain->open_exposed_ports($remote_ip);

    Ravada::Request->refresh_machine_ports(
        uid => $request->args('uid'),
        ,id_domain => $domain->id
        ,retry => 20
        ,timeout => 180
    );

}

sub _cmd_close_exposed_ports($self, $request) {
    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id( $uid ) or die "Error: user $uid not found";

    my $domain = Ravada::Domain->open($request->id_domain);
    return if !$domain;

    die "Error: user ".$user->name." not authorized to delete iptables rule"
    unless $user->is_admin || $domain->_data('id_owner') == $uid
        || $user->can_start_machine($domain);

    my $port = $request->defined_arg('port');

    $domain->_close_exposed_port($port);

    if ($request->defined_arg('clean')) {
        my $query = "UPDATE domain_ports SET public_port=?"
                    ." WHERE id_domain=? ";
        $query .=" AND internal_port=?" if $port;

        my $sth_update = $CONNECTOR->dbh->prepare($query);

        if ($port) {
            $sth_update->execute($domain->_vm->_new_free_port()
                ,$domain->id, $port);
        } else {
            $sth_update->execute($domain->_vm->_new_free_port()
                ,$domain->id);
        }
    }
}

sub _cmd_import($self, $request) {
    my $owner=Ravada::Auth::SQL->search_by_id($request->args('id_owner'));
    $self->import_domain(
        name => $request->args('name')
        ,user => $owner->name
        ,vm => $request->args('vm')
        ,spinoff_disks => $request->defined_arg('spinoff_disks')
    );
}

sub _cmd_list_unused_volumes($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to dettach domain"
        if !$user->is_admin;

    my $vm;
    eval { $vm = Ravada::VM->open($request->args('id_vm')) };
    die "Error: I can't find VM ".$request->args('id_vm')." ".($@ or '')
    if $@ || !$vm;

    my $limit = $request->defined_arg('limit');

    my $start = ($request->defined_arg('start') or 0 );
    my $n_items = 0;
    my $more = 0;
    my @files0 = $vm->list_unused_volumes();
    my @files;
    my $count = 0;
    for my $file ( sort @files0 ) {
        next if $start && $start>$count++;
        push @files,($file);
    }
    if ( defined $limit && $limit && scalar(@files)>$limit) {
            $#files = $limit;
            $more=1;
    }
    my @list = map { {file => $_} } sort @files;

    $request->output(encode_json({list => \@list, more => $more}))
        if $request;
    return @list;
}

sub _search_domain_volume($self, $file) {
    my $sth = $self->connector->dbh->prepare(
        "SELECT d.name FROM volumes v,domains d "
        ." WHERE d.id=v.id_domain AND v.file=?");
    $sth->execute($file);
    my @dom;
    while (my $row = $sth->fetchrow_hashref()) {
        push @dom,($row->{name})
    }
    return @dom;
}

sub _cmd_remove_files($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to remove files"
        if !$user->is_admin;

    my $file = $request->args('files');
    my @file =($file);
    if (ref($file)) {
        @file = @$file;
    }
    my @dom = $self->_search_domain_volume($file);

    die "Error: file $file belongs is in use by ".join(",", @dom)
    if @dom;

    my $vm = Ravada::VM->open($request->args('id_vm')) ;

    $vm->remove_file(@file);
}

sub _cmd_list_virtual_networks($self, $request) {
    my $user=Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized\n"
    unless $user->is_admin || $user->can_manage_all_networks || $user->can_create_networks;

    my $id = $request->args('id_vm') or die "Error: missing id_vm";
    my $vm = Ravada::VM->open($id);
    my @list = $vm->list_virtual_networks();

    $request->output(encode_json(\@list));
}


sub _cmd_new_network($self, $request) {
    my $user=Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized\n"
    unless $user->can_create_networks;

    $request->output(encode_json({}));

    my $id = $request->args('id_vm') or die "Error: missing id_vm";
    my $vm = Ravada::VM->open($id);
    my $name = ($request->defined_arg('name') or 'net');

    my $new = $vm->new_network($name);
    $new = {} if !$new;

    $request->output(encode_json( $new));
}

sub _cmd_create_network($self, $request) {
    my $user=Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized\n"
    unless $user->can_create_networks || $user->can_manage_all_networks;

    my $id = $request->args('id_vm') or die "Error: missing id_vm";
    my $vm = Ravada::VM->open($id);
    $request->output(encode_json({}));
    my $id_net = $vm->create_network($request->args('data'),$request->args('uid')
                    , $request);
    $request->output(encode_json({id_network => $id_net}));
}

sub _cmd_remove_network($self, $request) {

    my $id = $request->args('id');
    my $name = $request->defined_arg('name');
    my $sth_net = $CONNECTOR->dbh->prepare(
        "SELECT * FROM virtual_networks WHERE id=?"
    );
    $sth_net->execute($id);
    my $network = $sth_net->fetchrow_hashref;
    if  ($network && $network->{id} ) {
        _check_user_authorized_network($request, $id);
    }
    my $id_vm = ( $network->{id_vm} or $request->defined_arg('id_vm') );
    die "Error: unknown id_vm ".Dumper([$network,$request]) if !$id_vm;

    die "Error: unkonwn network , id=$id, name='".($name or '')."' "
    .Dumper($network) if ! $network->{id} && !$name;

    my $user=Ravada::Auth::SQL->search_by_id($request->args('uid'));

    my $vm = Ravada::VM->open($id_vm);
    $vm->remove_network($user, ($network->{id} or $name));
}

sub _check_user_authorized_network($request, $id_network) {

    my $user=Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: user ".$request->args('uid')." not found" if !$user;

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM virtual_networks WHERE id=?"
    );
    $sth->execute($id_network);
    my $network = $sth->fetchrow_hashref;

    confess "Error: network $id_network not found" if !$network->{id};

    die "Error: ".$user->name." not authorized\n"
    unless $user->is_admin
    || $user->can_manage_all_networks
    || ( $user->can_create_networks && $network->{id_owner} == $user->id);

    return $network;
}

sub _cmd_change_network($self, $request) {

    my $data = $request->args('data');
    die "Error: network.id required" if !exists $data->{id} || !$data->{id};

    my $network = _check_user_authorized_network($request, $data->{id});

    $data->{internal_id} = $network->{internal_id} if !$data->{internal_id};
    my $vm = Ravada::VM->open($network->{id_vm});

    my $forward_mode;

    $forward_mode = $data->{forward_mode} if $data->{forward_mode};
    my $network_name = $data->{name};

    $vm->change_network($data, $request->args('uid'));

    if ($forward_mode) {
        $vm->_set_active_machines_isolated($network_name);
    }
}

sub _cmd_active_storage_pool($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to manage storage pools"
        if !$user->is_admin;

    my $vm = Ravada::VM->open($request->args('id_vm'));
    $vm->active_storage_pool($request->arg('name'), $request->arg('value'));
}

sub _cmd_create_storage_pool($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to manage storage pools"
        if !$user->is_admin;

    my $vm = Ravada::VM->open($request->args('id_vm'));
    $vm->create_storage_pool($request->arg('name'), $request->arg('directory'));

}

sub _cmd_move_volume($self, $request) {

    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to move volumes"
        if !$user->is_admin;

    my $domain = Ravada::Domain->open($request->args('id_domain'));
    die "Error: I can not move volume while machine running ".$domain->name."\n"
    if $domain->is_active;

    my $volume = $request->args('volume');
    my @volumes = $domain->list_volumes_info();
    my $found;
    my $n_found = 0;
    for my $vol (@volumes) {
        if ($vol->file eq $volume ) {
            $found = $vol;
            last;
        }
        $n_found++;
    }
    die "Volume $volume not found in ".$domain->name."\n".Dumper([map { $_->file } @volumes]) if !$found;

    my $vm = $domain->_vm;
    my $storage = $request->args('storage');
    my $dst_path = $vm->_storage_path($storage);
    my ($filename) = $volume =~ m{.*/(.*)};
    my $dst_vol = "$dst_path/$filename";

    die "Error: file '$dst_vol' already exists in ".$vm->name."\n" if $vm->file_exists($dst_vol);

    my $new_file = $vm->copy_file_storage($volume, $storage);

    $domain->change_hardware('disk', $n_found, { file => $new_file });
    if ($volume !~ /\.iso$/) {
        $vm->remove_file($volume);
    }
}

sub _cmd_backup($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to backup"
        if !$user->is_admin;

    my $domain = Ravada::Domain->open($request->args('id_domain'));
    die "Error: I can not backup while machine is active".$domain->name."\n"
    if $domain->is_active;

    $request->output($domain->backup());
}

sub _cmd_restore_backup($self, $request) {
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    die "Error: ".$user->name." not authorized to backup"
        if !$user->is_admin;

    my $file = $request->args('file');
    die "Error: missing file  '$file'" if ! -e $file;

    $self->restore_backup($file,0);
    $request->output();
}

=head2 set_debug_value

Sets debug global variable from setting

=cut

sub set_debug_value($self) {
	$DEBUG = $FORCE_DEBUG || $self->setting('backend/debug');
}

=head2 setting

Returns the value of a configuration setting

=cut
sub setting {
    return Ravada::Front::setting(@_);
}

sub _setting_data {
    return Ravada::Front::_setting_data(@_);
}


=head2 restore_backup

  Restores a virtual machine from a backup file

=cut

sub restore_backup($self, $file, $interactive=undef) {
    die "Error: file '$file' not found\n" if !-e $file;

    if (!defined $interactive) {
        $interactive = $ENV{TERM};
    }

    my ($name) = $file =~ m{.*/(.*?).\d{4}-\d\d-\d\d_\d\d-\d\d-};
    my $domain = $self->search_domain($name);

    die "Error: ".$domain->name." is active, shut it down to restore.\n"
    if $domain && $domain->is_active;

    return if $domain && $interactive && !$self->_confirm_restore();

    return Ravada::Domain::restore_backup($domain, $file);
}



sub _restore_backup_data($self, $file_data, $file_data_extra
                            ,$file_data_owner) {
    open my $f,"<",$file_data or die "$! $file_data";
    my $json = join "",<$f>;
    close $f;

    my $data = decode_json($json);

    open my $f2,"<",$file_data_extra or die "$! $file_data_extra";
    my $json2 = join "",<$f2>;
    close $f2;

    my $data_extra = decode_json($json2);

    my $id = $data->{id};
    my $name = $data->{name};
    my $vm = $self->search_vm($data->{vm});

    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains "
        ."WHERE id=? OR name=?"
    );
    $sth->execute($id,$name);
    my $domain_old = $sth->fetchrow_hashref;
    if ($domain_old && $domain_old->{name} ne $name) {
        die "Domain id='$id' already exists, it is called "
            .$domain_old->{name};
    }
    if (!$domain_old) {
        my $domain = $vm->create_domain(
            name => $name
            ,config => $data_extra->{xml}
            ,id_owner => Ravada::Utils::user_daemon->id
            ,id => $id
        );
        $domain_old = $domain;
    } else {
        $domain_old = Ravada::Domain->open($domain_old->{id});
    }
    $domain_old->_restore_backup_metadata($file_data, $file_data_owner);
    return $domain_old;
}

sub DESTROY($self) {
    $self->_wait_pids() unless $0 =~ /\.t$/;
}

=head2 version

Returns the version of the module

=cut

sub version {
    return $VERSION;
}


=head1 AUTHOR

Francesc Guasch-Ortiz	, frankie@telecos.upc.edu

=head1 SEE ALSO

Sys::Virt

=cut

1;

