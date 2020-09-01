package Ravada;

use warnings;
use strict;

our $VERSION = '0.9.0';

use Carp qw(carp croak);
use Data::Dumper;
use DBIx::Connector;
use File::Copy;
use Hash::Util qw(unlock_hash lock_hash);
use JSON::XS;
use Moose;
use POSIX qw(WNOHANG);
use Time::HiRes qw(gettimeofday tv_interval);
use YAML;
use MIME::Base64;
use Socket qw( inet_aton inet_ntoa );
use Image::Magick::Q16;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Auth;
use Ravada::Request;
use Ravada::Repository::ISO;
use Ravada::VM::Void;

our %VALID_VM;
our %ERROR_VM;
our $TIMEOUT_STALE_PROCESS;

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
    ,db => {user => undef, password => undef,  hostname => undef}
    ,ldap => { admin_user => { dn => undef, password => undef }
        ,filter => undef
        ,base => undef
        ,auth => undef
        ,admin_group => undef
        ,ravada_posix_group => undef
    }
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
our $DEBUG;
our $VERBOSE;
our $CAN_FORK = 1;
our $CAN_LXC = 0;

# Seconds to wait for other long process
our $SECONDS_WAIT_CHILDREN = 5;

our $DIR_SQL = "sql/mysql";
$DIR_SQL = "/usr/share/doc/ravada/sql/mysql" if ! -e $DIR_SQL;

our $USER_DAEMON;
our $USER_DAEMON_NAME = 'daemon';

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

sub _install($self) {
    $self->_sql_create_tables();
    $self->_create_tables();
    $self->_upgrade_tables();
    $self->_upgrade_timestamps();
    $self->_update_data();
    $self->_init_user_daemon();
    $self->_sql_insert_defaults();
}

sub _init_user_daemon {
    my $self = shift;
    return if $USER_DAEMON;

    $USER_DAEMON = Ravada::Auth::SQL->new(name => $USER_DAEMON_NAME);
    if (!$USER_DAEMON->id) {
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
        my $user = Ravada::Auth::SQL->search_by_id($id);
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
    my %data = (
	    androidx86 => {
                    name => 'Android 8.1 x86'
            ,description => 'Android-x86 64 bits. Requires an user provided ISO image.'
                   ,arch => 'amd64'
                    ,xml => 'android-amd64.xml'
             ,xml_volume => 'android-volume.xml'
	     ,min_disk_size => '4'
        },
        arch_1909 => {
                    name => 'Arch Linux 19.09'
            ,description => 'Arch Linux 19.09.01 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'https://archive.archlinux.org/iso/2019.09.01/'
                    ,file_re => 'archlinux-2019.09.01-x86_64.iso'
                    ,md5_url => ''
                    ,md5 => '1d6bdf5cbc6ca98c31f02d23e418dd96'
        },
	mate_focal_fossa => {
                    name => 'Ubuntu Mate Focal Fossa 64 bits'
            ,description => 'Ubuntu Mate 20.04 (Focal Fossa) 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/20.04/release/ubuntu-mate-20.04-desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
        },
        mate_bionic => {
                    name => 'Ubuntu Mate Bionic 64 bits'
            ,description => 'Ubuntu Mate 18.04 (Bionic Beaver) 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/18.04.*/release/ubuntu-mate-18.04.*-desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
        },
        mate_bionic_i386 => {
                    name => 'Ubuntu Mate Bionic 32 bits'
            ,description => 'Ubuntu Mate 18.04 (Bionic Beaver) 32 bits'
                   ,arch => 'i386'
                    ,xml => 'bionic-i386.xml'
             ,xml_volume => 'bionic32-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/18.04.*/release/ubuntu-mate-18.04.*-desktop-i386.iso'
                ,md5_url => '$url/MD5SUMS'
        },
        mate_xenial => {
                    name => 'Ubuntu Mate Xenial'
            ,description => 'Ubuntu Mate 16.04.3 (Xenial) 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'yakkety64-amd64.xml'
             ,xml_volume => 'yakkety64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/16.04.*/release/ubuntu-mate-16.04.*-desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
                ,min_disk_size => '10'
        },
	,focal_fossa=> {
                    name => 'Ubuntu Focal Fossa'
            ,description => 'Ubuntu 20.04 Focal Fossa 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'focal_fossa-amd64.xml'
             ,xml_volume => 'focal_fossa64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/20.04/'
                ,file_re => '^ubuntu-20.04.*desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
          ,min_disk_size => '9'
        }

        ,bionic=> {
                    name => 'Ubuntu Bionic Beaver'
            ,description => 'Ubuntu 18.04 Bionic Beaver 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/18.04/'
                ,file_re => '^ubuntu-18.04.*desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
          ,min_disk_size => '9'
        }

        ,serena64 => {
            name => 'Mint 18.1 Mate 64 bits'
    ,description => 'Mint Serena 18.1 with Mate Desktop based on Ubuntu Xenial 64 bits'
           ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
     ,xml_volume => 'xenial64-volume.xml'
            ,url => 'http://mirrors.evowise.com/linuxmint/stable/18.1/'
        ,file_re => 'linuxmint-18.1-mate-64bit.iso'
        ,md5_url => ''
            ,md5 => 'c5cf5c5d568e2dfeaf705cfa82996d93'
            ,min_disk_size => '10'

        }
        ,mint20_64 => {
            name => 'Mint 20 Mate 64 bits'
    ,description => 'Mint Ulyana 20 with Mate Desktop 64 bits'
           ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
     ,xml_volume => 'xenial64-volume.xml'
            ,url => 'http://mirrors.evowise.com/linuxmint/stable/20/'
        ,file_re => 'linuxmint-20-mate-64bit.iso'
        ,sha256_url => '$url/sha256sum.txt'
            ,min_disk_size => '15'
        }
        ,alpine381_64 => {
            name => 'Alpine 3.8 64 bits'
    ,description => 'Alpine Linux 3.8 64 bits ( Minimal Linux Distribution )'
           ,arch => 'amd64'
            ,xml => 'alpine-amd64.xml'
     ,xml_volume => 'alpine381_64-volume.xml'
            ,url => 'http://dl-cdn.alpinelinux.org/alpine/v3.8/releases/x86_64/'
        ,file_re => 'alpine-standard-3.8.1-x86_64.iso'
        ,sha256_url => 'http://dl-cdn.alpinelinux.org/alpine/v3.8/releases/x86_64/alpine-standard-3.8.1-x86_64.iso.sha256'
            ,min_disk_size => '1'
        }
        ,alpine381_32 => {
            name => 'Alpine 3.8 32 bits'
    ,description => 'Alpine Linux 3.8 32 bits ( Minimal Linux Distribution )'
           ,arch => 'i386'
            ,xml => 'alpine-i386.xml'
     ,xml_volume => 'alpine381_32-volume.xml'
            ,url => 'http://dl-cdn.alpinelinux.org/alpine/v3.8/releases/x86/'
        ,file_re => 'alpine-standard-3.8.1-x86.iso'
        ,sha256_url => 'http://dl-cdn.alpinelinux.org/alpine/v3.8/releases/x86/alpine-standard-3.8.1-x86.iso.sha256'
            ,min_disk_size => '1'
        }
        ,fedora_28 => {
            name => 'Fedora 28'
            ,description => 'RedHat Fedora 28 Workstation 64 bits'
            ,url => 'https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/28/Workstation/x86_64/iso/Fedora-Workstation-netinst-x86_64-28-.*\.iso'
            ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
            ,xml_volume => 'xenial64-volume.xml'
            ,sha256_url => '$url/Fedora-Workstation-28-.*-x86_64-CHECKSUM'
            ,min_disk_size => '10'
        }
	      ,kubuntu_64_focal_fossa => {
            name => 'Kubuntu Focal Fossa 64 bits'
            ,description => 'Kubuntu 20.04 Focal Fossa 64 bits'
            ,arch => 'amd64'
            ,xml => 'focal_fossa-amd64.xml'
            ,xml_volume => 'focal_fossa64-volume.xml'
            ,md5_url => '$url/MD5SUMS'
            ,url => 'http://cdimage.ubuntu.com/kubuntu/releases/20.04/release/'
            ,file_re => 'kubuntu-20.04-desktop-amd64.iso'
            ,rename_file => 'kubuntu_focal_fossa_64.iso'
        }
        ,kubuntu_64 => {
            name => 'Kubuntu Bionic Beaver 64 bits'
            ,description => 'Kubuntu 18.04 Bionic Beaver 64 bits'
            ,arch => 'amd64'
            ,xml => 'bionic-amd64.xml'
            ,xml_volume => 'bionic64-volume.xml'
            ,md5_url => '$url/MD5SUMS'
            ,url => 'http://cdimage.ubuntu.com/kubuntu/releases/18.04/release/'
            ,file_re => 'kubuntu-18.04-desktop-amd64.iso'
            ,rename_file => 'kubuntu_bionic_64.iso'
        }
        ,kubuntu_32 => {
            name => 'Kubuntu Bionic Beaver 32 bits'
            ,description => 'Kubuntu 18.04 Bionic Beaver 32 bits'
            ,arch => 'i386'
            ,xml => 'bionic-i386.xml'
            ,xml_volume => 'bionic32-volume.xml'
            ,md5_url => '$url/MD5SUMS'
            ,url => 'http://cdimage.ubuntu.com/kubuntu/releases/18.04/release/'
            ,file_re => 'kubuntu-18.04-desktop-i386.iso'
            ,rename_file => 'kubuntu_bionic_32.iso'
        }
        ,suse_15 => {
            name => "openSUSE Leap 15"
            ,description => "openSUSE Leap 15 64 bits"
            ,arch => 'amd64'
            ,xml => 'bionic-amd64.xml'
            ,xml_volume => 'bionic64-volume.xml'
            ,url => 'https://download.opensuse.org/distribution/leap/15.0/iso/'
            ,sha256_url => '$url/openSUSE-Leap-15.\d+-NET-x86_64.iso.sha256'
            ,file_re => 'openSUSE-Leap-15.\d+-NET-x86_64.iso'

        }
        ,xubuntu_beaver_64 => {
            name => 'Xubuntu Bionic Beaver 64 bits'
            ,description => 'Xubuntu 18.04 Bionic Beaver 64 bits'
            ,arch => 'amd64'
            ,xml => 'bionic-amd64.xml'
            ,xml_volume => 'bionic64-volume.xml'
            ,md5_url => '$url/../MD5SUMS'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-amd64/current/images/netboot/'
            ,file_re => 'mini.iso'
            ,rename_file => 'xubuntu_bionic_64.iso'
        }
        ,xubuntu_beaver_32 => {
            name => 'Xubuntu Bionic Beaver 32 bits'
            ,description => 'Xubuntu 18.04 Bionic Beaver 32 bits'
            ,arch => 'i386'
            ,xml => 'bionic-i386.xml'
            ,xml_volume => 'bionic32-volume.xml'
            ,md5_url => '$url/../MD5SUMS'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-i386/current/images/netboot/'
            ,file_re => 'mini.iso'
            ,rename_file => 'xubuntu_bionic_32.iso'
        }
        ,xubuntu_xenial => {
            name => 'Xubuntu Xenial Xerus'
            ,description => 'Xubuntu 16.04 Xenial Xerus 64 bits (LTS)'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/mini.iso'
           ,xml => 'yakkety64-amd64.xml'
            ,xml_volume => 'yakkety64-volume.xml'
            ,md5 => 'fe495d34188a9568c8d166efc5898d22'
            ,rename_file => 'xubuntu_xenial_mini.iso'
            ,min_disk_size => '10'
        }
	,lubuntu_bionic_64 => {
             name => 'Lubuntu Bionic Beaver 64 bits'
             ,description => 'Lubuntu 18.04 Bionic Beaver 64 bits'
             ,url => 'http://cdimage.ubuntu.com/lubuntu/releases/18.04.*/release/lubuntu-18.04.*-desktop-amd64.iso'
             ,md5_url => '$url/MD5SUMS'
             ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
         }
         ,lubuntu_bionic_32 => {
             name => 'Lubuntu Bionic Beaver 32 bits'
             ,description => 'Lubuntu 18.04 Bionic Beaver 32 bits'
             ,arch => 'i386'
             ,url => 'http://cdimage.ubuntu.com/lubuntu/releases/18.04.*/release/lubuntu-18.04.*-desktop-i386.iso'
             ,md5_url => '$url/MD5SUMS'
             ,xml => 'bionic-i386.xml'
             ,xml_volume => 'bionic32-volume.xml'
        }
        ,lubuntu_xenial => {
            name => 'Lubuntu Xenial Xerus'
            ,description => 'Xubuntu 16.04 Xenial Xerus 64 bits (LTS)'
            ,url => 'http://cdimage.ubuntu.com/lubuntu/releases/16.04.*/release/'
            ,file_re => 'lubuntu-16.04.*-desktop-amd64.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'yakkety64-amd64.xml'
            ,xml_volume => 'yakkety64-volume.xml'
            ,min_disk_size => '10'
        }
        ,debian_jessie_32 => {
            name =>'Debian Jessie 32 bits'
            ,description => 'Debian 8 Jessie 32 bits'
            ,url => 'http://cdimage.debian.org/cdimage/archive/^8\..*/i386/iso-cd/'
            ,file_re => 'debian-8.[\d\.]+-i386-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,debian_jessie_64 => {
            name =>'Debian Jessie 64 bits'
            ,description => 'Debian 8 Jessie 64 bits'
            ,url => 'http://cdimage.debian.org/cdimage/archive/^8\..*/amd64/iso-cd/'
            ,file_re => 'debian-8.[\d\.]+-amd64-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
       ,debian_stretch_32 => {
            name =>'Debian Stretch 32 bits'
            ,description => 'Debian 9 Stretch 32 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/^9\..*\d$/i386/iso-cd/'
            ,file_re => 'debian-9.[\d\.]+-i386-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,debian_stretch_64 => {
            name =>'Debian Stretch 64 bits'
            ,description => 'Debian 9 Stretch 64 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/cdimage/archive/^9\..*/amd64/iso-cd/'
            ,file_re => 'debian-9.[\d\.]+-amd64-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,debian_buster_64=> {
            name =>'Debian Buster 64 bits'
            ,description => 'Debian 10 Buster 64 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/debian-cd/^10\..*\d$/amd64/iso-cd/'
            ,file_re => 'debian-10.[\d\.]+-amd64-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,debian_buster_32=> {
            name =>'Debian Buster 32 bits'
            ,description => 'Debian 10 Buster 32 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/debian-cd/^10\..*\d$/i386/iso-cd/'
            ,file_re => 'debian-10.[\d\.]+-i386-(netinst|xfce-CD-1).iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-i386.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,min_disk_size => '10'
        }
        ,kali_64 => {
            name => 'Kali Linux 2020'
            ,description => 'Kali Linux 2020 64 Bits'
            ,arch => 'amd64'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,url => 'https://cdimage.kali.org/kali-2020.\d+/'
            ,file_re => 'kali-linux-2020.\d+-installer-amd64.iso'
            ,sha256_url => '$url/SHA256SUMS'
            ,min_disk_size => '10'
        }
        ,kali_64_netinst => {
            name => 'Kali Linux 2020 (NetInstaller)'
            ,description => 'Kali Linux 2020 64 Bits (light NetInstall)'
            ,arch => 'amd64'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
            ,url => 'https://cdimage.kali.org/kali-2020.\d+/'
            ,file_re => 'kali-linux-2020.\d+-installer-netinst-amd64.iso'
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
        }
        ,windows_10 => {
          name => 'Windows 10'
          ,description => 'Windows 10 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_10.xml'
          ,xml_volume => 'windows10-volume.xml'
          ,min_disk_size => '21'
        }
        ,windows_xp => {
          name => 'Windows XP'
          ,description => 'Windows XP 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_xp.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '3'
        }
        ,windows_12 => {
          name => 'Windows 2012'
          ,description => 'Windows 2012 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_12.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '21'
        }
        ,windows_8 => {
          name => 'Windows 8.1'
          ,description => 'Windows 8.1 64 bits. Requires an user provided ISO image.'
          .'<a target="_blank" href="http://ravada.readthedocs.io/en/latest/docs/new_iso_image.html">[help]</a>'
          ,xml => 'windows_8.xml'
          ,xml_volume => 'wisuvolume.xml'
          ,min_disk_size => '21'
        }
       ,empty_32bits => {
          name => 'Empty Machine 32 bits'
          ,description => 'Empty Machine 32 bits Boot PXE'
          ,xml => 'empty-i386.xml'
          ,xml_volume => 'jessie-volume.xml'
          ,min_disk_size => '0'
        }
       ,empty_64bits => {
          name => 'Empty Machine 64 bits'
          ,description => 'Empty Machine 64 bits Boot PXE'
          ,xml => 'empty-amd64.xml'
          ,xml_volume => 'jessie-volume.xml'
          ,min_disk_size => '0'
        }
    );
    $self->_scheduled_fedora_releases(\%data);
    $self->_update_table($table, $field, \%data);

}

sub _scheduled_fedora_releases($self,$data) {
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

            $data->{$name} = {
            name => 'Fedora '.$release
            ,description => "RedHat Fedora $release Workstation 64 bits"
            ,url => $url.$release
                    .'/Workstation/x86_64/iso/Fedora-Workstation-.*-x86_64-'.$release
                    .'-.*\.iso'
            ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
            ,xml_volume => 'xenial64-volume.xml'
            ,sha256_url => '$url/Fedora-Workstation-'.$release.'-.*-x86_64-CHECKSUM'
            ,min_disk_size => 10 + $release-27
            };
        }
    }
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
           ,value => 'type="qxl" ram="65536" vram="65536" vgamem="16384" heads="1" primary="yes"'
        },
        vmvga => {
            id => 2,
            ,id_driver_type => 1,
            ,name => 'VMVGA'
           ,value => 'type="vmvga" vram="16384" heads="1" primary="yes"'
        },
        cirrus => {
            id => 3,
            ,id_driver_type => 1,
            ,name => 'Cirrus'
           ,value => 'type="cirrus" vram="16384" heads="1" primary="yes"'
        },
        vga => {
            id => 4,
            ,id_driver_type => 1,
            ,name => 'VGA'
           ,value => 'type="vga" vram="16384" heads="1" primary="yes"'
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
}

sub _update_table($self, $table, $field, $data, $verbose=0) {

    my $sth_search = $CONNECTOR->dbh->prepare("SELECT id FROM $table WHERE $field = ?");
    for my $name (sort keys %$data) {
        my $row = $data->{$name};
        $sth_search->execute($row->{$field});
        my ($id) = $sth_search->fetchrow;
        if ( $id ) {
            warn("INFO: $table : $row->{$field} already added.\n") if $verbose;
            next;
        }
        warn("INFO: updating $table : $row->{$field}\n")    if $0 !~ /\.t$/;

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
    }
}

sub _remove_old_isos {
    my $self = shift;
    for my $sql (
        "DELETE FROM iso_images "
            ."  WHERE url like '%debian-9.0%iso'"
        ,"DELETE FROM iso_images"
            ."  WHERE name like 'Debian%' "
            ."      AND NOT url  like '%*%' "
        ,"DELETE FROM iso_images "
            ."  WHERE name like 'Lubuntu Artful%'"
            ."      AND url NOT LIKE '%*%' "
        ,"DELETE FROM iso_images "
            ."  WHERE name like 'Lubuntu Zesty%'"
        ,"DELETE FROM iso_images "
            ."  WHERE name like 'Debian Buster 32%'"
            ."  AND file_re like '%xfce-CD-1.iso'"

    ) {
        my $sth = $CONNECTOR->dbh->prepare($sql);
        $sth->execute();
        $sth->finish;
    }
}

sub _update_data {
    my $self = shift;

    $self->_remove_old_isos();
    $self->_update_isos();

    $self->_rename_grants();
    $self->_alias_grants();
    $self->_add_grants();
    $self->_enable_grants();
    $self->_update_user_grants();

    $self->_update_domain_drivers_types();
    $self->_update_domain_drivers_options();
    $self->_update_domain_drivers_options_disk();
    $self->_update_old_qemus();

    $self->_add_indexes();
}

sub _add_indexes($self) {
    $self->_add_indexes_generic();
}

sub _add_indexes_generic($self) {
    my %index = (
        domains => [
            "index(date_changed)"
            ,"index(id_base):id_base_index"
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
            ,"index(id_user)"
        ]
        ,iptables => [
            "index(id_domain,time_deleted,time_req)"
        ]
        ,messages => [
             "index(id_request,date_send)"
             ,"index(date_changed)"
        ]
        ,settings => [
            "index(id_parent,name)"
        ]
        ,vms=> [
            "unique(hostname, vm_type)"
        ]
    );
    my $if_not_exists = '';
    $if_not_exists = ' IF NOT EXISTS ' if $CONNECTOR->dbh->{Driver}{Name} =~ /sqlite|mariadb/i;

    for my $table ( keys %index ) {
        my $known = $self->_get_indexes($table);
        for my $change (@{$index{$table}} ) {
            my ($type,$fields ) =$change =~ /(\w+)\((.*)\)/;
            my ($name) = $change =~ /:(.*)/;
            $name = $fields if !$name;
            $name =~ s/,/_/g;
            $name =~ s/ //g;
            next if $known->{$name};

            $type .=" INDEX " if $type=~ /^unique/i;
            my $sql = "CREATE $type $if_not_exists $name on $table ($fields)";

            warn "INFO: Adding index to $table: $name" if $0 !~ /\.t$/;
            my $sth = $CONNECTOR->dbh->prepare($sql);
            $sth->execute();
        }
    }
}

sub _get_indexes($self,$table) {

    return {} if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/;

    my $sth = $CONNECTOR->dbh->prepare("show index from $table");
    $sth->execute;
    my %index;
    while (my $row = $sth->fetchrow_hashref) {
        $index{$row->{Key_name}}->{$row->{Column_name}}++;
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
    $self->_add_grant('rename', 0,"Can rename any virtual machine owned by the user.");
    $self->_add_grant('rename_all', 0,"Can rename any virtual machine.");
    $self->_add_grant('rename_clones', 0,"Can rename clones from virtual machines owned by the user.");
    $self->_add_grant('shutdown', 1,"Can shutdown own virtual machines.");
    $self->_add_grant('screenshot', 1,"Can get a screenshot of own virtual machines.");
    $self->_add_grant('start_many',0,"Can have more than one machine started.");
    $self->_add_grant('expose_ports',0,"Can expose virtual machine ports.");
}

sub _add_grant($self, $grant, $allowed, $description) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, description FROM grant_types WHERE name=?"
    );
    $sth->execute($grant);
    my ($id, $current_description) = $sth->fetchrow();
    $sth->finish;

    if ($id && $current_description ne $description) {
        my $sth = $CONNECTOR->dbh->prepare(
            "UPDATE grant_types SET description = ? WHERE id = ?;"
        );
        $sth->execute($description, $id);
        $sth->finish;
    }
    return if $id;

    $sth = $CONNECTOR->dbh->prepare("INSERT INTO grant_types (name, description)"
        ." VALUES (?,?)");
    $sth->execute($grant, $description);
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

    my $sth = $CONNECTOR->dbh->prepare(
        "UPDATE grant_types set enabled=0"
    );
    $sth->execute;
    my @grants = (
        'change_settings',  'change_settings_all',  'change_settings_clones'
        ,'clone',           'clone_all',            'create_base', 'create_machine'
        ,'expose_ports'
        ,'grant'
        ,'manage_users'
        ,'rename', 'rename_all', 'rename_clones'
        ,'remove',          'remove_all',   'remove_clone',     'remove_clone_all'
        ,'screenshot'
        ,'shutdown',        'shutdown_all',    'shutdown_clone'
        ,'screenshot'
        ,'start_many'
    );

    $sth = $CONNECTOR->dbh->prepare("SELECT id,name FROM grant_types");
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
        die "Permission $name doesn't exist at table grant_types"
                ."\n".Dumper(\%grant_exists)
            if !$grant_exists{$name};

        $sth->execute($name);

    }

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
sub _upgrade_table {
    my $self = shift;
    my ($table, $field, $definition) = @_;
    my $dbh = $CONNECTOR->dbh;

    my ($new_size) = $definition =~ m{\((\d+)};
    my ($new_type) = $definition =~ m{(\w+)};

    my $sth = $dbh->column_info(undef,undef,$table,$field);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    if ( $dbh->{Driver}{Name} =~ /mysql/
        && $row
        && (
            ($row->{COLUMN_SIZE}
            && defined $new_size
            && $new_size != $row->{COLUMN_SIZE}
            ) || (
                lc($row->{TYPE_NAME}) ne lc($new_type)
            )
        )
    ){

        warn "INFO: changing $field\n"
            ." $row->{COLUMN_SIZE} to ".($new_size or '')."\n"
            ." $row->{TYPE_NAME} -> $new_type \n"
            ." in $table\n$definition\n"  if $0 !~ /\.t$/;
        $dbh->do("alter table $table change $field $field $definition");
        return;
    }

    return if $row;

    my $sqlite_trigger;
    if ($dbh->{Driver}{Name} =~ /sqlite/i) {
        $definition =~ s/DEFAULT.*ON UPDATE(.*)//i;
        $sqlite_trigger = $1;
    }
    warn "INFO: adding $field $definition to $table\n"  if $0 !~ /\.t$/;
    $dbh->do("alter table $table add $field $definition");
    if ( $sqlite_trigger && !$self->_exists_trigger($dbh, "Update$field") ) {
        $self->_sqlite_trigger($dbh,$table, $field, $sqlite_trigger);
    }
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

sub _remove_field {
    my $self = shift;
    my ($table, $field ) = @_;

    my $dbh = $CONNECTOR->dbh;
    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/i;

    my $sth = $dbh->column_info(undef,undef,$table,$field);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    return if !$row;

    warn "INFO: removing $field to $table\n"  if $0 !~ /\.t$/;
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

    warn "INFO: creating table $table\n"    if $0 !~ /\.t$/;

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

    warn "INFO: inserting data for $table\n";
    open my $in,'<',$file_sql or die "$! $file_sql";
    my $sql = '';
    while (my $line = <$in>) {
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
    my $driver = lc($CONNECTOR->dbh->{Driver}{Name});
    my %tables = (
        settings => {
            id => 'integer NOT NULL PRIMARY KEY AUTO_INCREMENT'
            , id_parent => 'INT NOT NULL'
            , name => 'varchar(64) NOT NULL'
            , value => 'varchar(128) DEFAULT NULL'
        }
    );
    for my $table ( keys %tables ) {
        my $sth = $CONNECTOR->dbh->table_info('%',undef,$table,'TABLE');
        my $info = $sth->fetchrow_hashref();
        $sth->finish;
        next if keys %$info;

        warn "INFO: creating table $table\n"    if $0 !~ /\.t$/;

        my $sql_fields;
        for my $field (sort keys %{$tables{$table}} ) {
            my $definition = _port_definition($driver, $tables{$table}->{$field});
            $sql_fields .= ", " if $sql_fields;
            $sql_fields .= " $field $definition";
        }

        my $sql = "CREATE TABLE $table ( $sql_fields )";
        $CONNECTOR->dbh->do($sql);

    }
}

sub _sql_insert_defaults($self){
    require Mojolicious::Plugin::Config;
    my $plugin = Mojolicious::Plugin::Config->new();
    my $conf = {
        fallback => 0
        ,session_timeout => 10*60
        ,admin_session_timeout => 30*60
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
            ,{
                id_parent => $id_backend
                ,name => 'start_limit'
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
            warn "INFO adding default $table ".Dumper($entry) if $0 !~ /t$/;
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
    return $definition0 if $driver eq 'mysql';
    if ($driver eq 'sqlite') {
        $definition0 =~ s/(.*) AUTO_INCREMENT$/$1 AUTOINCREMENT/i;
        return $definition0 if $definition0 =~ /^(int|integer|char|varchar) /i;
    }
}

sub _clean_iso_mini {
    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM iso_images WHERE device like ?");
    $sth->execute('%/mini.iso');
    $sth->finish;

    $sth = $CONNECTOR->dbh->prepare("DELETE FROM iso_images WHERE url like ? AND rename_file = NULL");
    $sth->execute('%/mini.iso');
    $sth->finish;
}

sub _upgrade_tables {
    my $self = shift;
#    return if $CONNECTOR->dbh->{Driver}{Name} !~ /mysql/i;

    $self->_upgrade_table('file_base_images','target','varchar(64) DEFAULT NULL');

    $self->_upgrade_table('vms','vm_type',"char(20) NOT NULL DEFAULT 'KVM'");
    $self->_upgrade_table('vms','connection_args',"text DEFAULT NULL");
    $self->_upgrade_table('vms','cached_active_time',"int DEFAULT 0");
    $self->_upgrade_table('vms','public_ip',"varchar(128) DEFAULT NULL");
    $self->_upgrade_table('vms','is_active',"int DEFAULT 0");
    $self->_upgrade_table('vms','enabled',"int DEFAULT 1");

    $self->_upgrade_table('vms','min_free_memory',"int DEFAULT 600000");
    $self->_upgrade_table('vms', 'max_load', 'int not null default 10');
    $self->_upgrade_table('vms', 'active_limit','int DEFAULT NULL');
    $self->_upgrade_table('vms', 'base_storage','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('vms', 'clone_storage','varchar(64) DEFAULT NULL');

    $self->_upgrade_table('requests','at_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','pid','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','start_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','output','text DEFAULT NULL');
    $self->_upgrade_table('requests','after_request','int(11) DEFAULT NULL');

    $self->_upgrade_table('requests','at_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','run_time','float DEFAULT NULL');
    $self->_upgrade_table('requests','retry','int(11) DEFAULT NULL');

    $self->_upgrade_table('iso_images','rename_file','varchar(80) DEFAULT NULL');
    $self->_clean_iso_mini();
    $self->_upgrade_table('iso_images','md5_url','varchar(255)');
    $self->_upgrade_table('iso_images','sha256','varchar(255)');
    $self->_upgrade_table('iso_images','sha256_url','varchar(255)');
    $self->_upgrade_table('iso_images','file_re','char(64)');
    $self->_upgrade_table('iso_images','device','varchar(255)');
    $self->_upgrade_table('iso_images','min_disk_size','int (11) DEFAULT NULL');

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

    $self->_upgrade_table('domains','spice_password','varchar(20) DEFAULT NULL');
    $self->_upgrade_table('domains','description','text DEFAULT NULL');
    $self->_upgrade_table('domains','run_timeout','int DEFAULT NULL');
    $self->_upgrade_table('domains','id_vm','int DEFAULT NULL');
    $self->_upgrade_table('domains','start_time','int DEFAULT 0');
    $self->_upgrade_table('domains','is_volatile','int NOT NULL DEFAULT 0');
    $self->_upgrade_table('domains','autostart','int NOT NULL DEFAULT 0');

    $self->_upgrade_table('domains','status','varchar(32) DEFAULT "shutdown"');
    $self->_upgrade_table('domains','display','text');
    $self->_upgrade_table('domains','display_file','text DEFAULT NULL');
    $self->_upgrade_table('domains','info','varchar(255) DEFAULT NULL');
    $self->_upgrade_table('domains','internal_id','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('domains','id_vm','int default null');
    $self->_upgrade_table('domains','volatile_clones','int NOT NULL default 0');
    $self->_upgrade_table('domains','comment',"varchar(80) DEFAULT ''");

    $self->_upgrade_table('domains','client_status','varchar(32)');
    $self->_upgrade_table('domains','client_status_time_checked','int NOT NULL default 0');
    $self->_upgrade_table('domains','pools','int NOT NULL default 0');
    $self->_upgrade_table('domains','pool_clones','int NOT NULL default 0');
    $self->_upgrade_table('domains','pool_start','int NOT NULL default 0');
    $self->_upgrade_table('domains','is_pool','int NOT NULL default 0');

    $self->_upgrade_table('domains','needs_restart','int not null default 0');
    $self->_upgrade_table('domains','shutdown_disconnected','int not null default 0');
    $self->_upgrade_table('domains','date_changed','timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');

    if ($self->_upgrade_table('domains','screenshot','MEDIUMBLOB')) {

    $self->_upgrade_screenshots();

    }

    $self->_upgrade_table('domains_network','allowed','int not null default 1');

    $self->_upgrade_table('iptables','id_vm','int DEFAULT NULL');
    $self->_upgrade_table('vms','security','varchar(255) default NULL');
    $self->_upgrade_table('grant_types','enabled','int not null default 1');

    $self->_upgrade_table('vms','mac','char(18)');

    $self->_upgrade_table('volumes','name','char(200)');

    $self->_upgrade_table('domain_ports', 'internal_ip','char(200)');
    $self->_upgrade_table('domain_ports', 'restricted','int(1) DEFAULT 0');

    $self->_upgrade_table('messages','date_changed','timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');
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

sub _connect_dbh {
    my $driver= ($CONFIG->{db}->{driver} or 'mysql');;
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_pass = ($CONFIG->{db}->{password} or undef);
    my $db = ( $CONFIG->{db}->{db} or 'ravada' );
    my $host = $CONFIG->{db}->{host};

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
        return $con if $con && !$@;
        sleep 1;
        warn "Try $try $@\n";
    }
    die ($@ or "Can't connect to $driver $db at $host");
}

=head2 display_ip

Returns the default display IP read from the config file

=cut

sub display_ip($self=undef, $new_ip=undef) {
    if (defined $new_ip) {
        if (!length $new_ip) {
            delete $CONFIG->{display_ip};
        } else {
            $CONFIG->{display_ip} = $new_ip;
        }
    }
    my $ip = $CONFIG->{display_ip};
    return $ip if $ip;
}

=head2 nat_ip

Returns the IP for NATed environments

=cut

sub nat_ip {
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
#    $CONNECTOR = ( $connector or _connect_dbh());

    _init_config_vm();
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

    my ($internal_vm , $storage);
    $storage = $vm_kvm->dir_img();
    $internal_vm = $vm_kvm->vm;
    $vm_kvm = undef if !$internal_vm || !$storage;

    return $vm_kvm;
}

sub _check_config($config_orig = {} , $valid_config = \%VALID_CONFIG ) {
    return 1 if !defined $config_orig;
    my %config = %$config_orig;

    for my $key (sort keys %$valid_config) {
        if ( $config{$key} && ref($valid_config->{$key})) {
           my $ok = _check_config( $config{$key} , $valid_config->{$key} );
           return 0 if !$ok;
        }
        delete $config{$key};
    }
    if ( keys %config ) {
        warn "Error: Unknown config entry \n".Dumper(\%config) if ! $0 =~ /\.t$/;
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
            $vm->disconnect();
        } else {
            $vm->connect();
        }
    }
}

sub _create_vm_lxc {
    my $self = shift;

    return;
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

    my $start = $args{start};
    my $id_base = $args{id_base};
    my $data = delete $args{data};
    my $id_owner = $args{id_owner} or confess "Error: missing id_owner ".Dumper(\%args);
    _check_args(\%args,qw(iso_file id_base id_iso id_owner name active swap memory disk id_template start remote_ip request vm add_to_pool));

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
    }
    my $user = Ravada::Auth::SQL->search_by_id($id_owner)
        or confess "Error: Unkown user '$id_owner'";

    $request->status("creating machine")    if $request;

    my $domain;
    eval { $domain = $vm->create_domain(%args)};

    my $error = $@;
    if ( $request ) {
        $request->error($error) if $error;
        if ($error =~ /has \d+ requests/) {
            $request->status('retry');
        }
    } elsif ($error) {
        die $error;
    }
    if (!$error && $start) {
        $request->status("starting") if $request;
        eval {
            my $remote_ip;
            $remote_ip = $request->defined_arg('remote_ip') if $request;
            $domain->start(
                user => $user
                ,remote_ip => $remote_ip
            )
        };
        my $error = $@;
        die $error if $error && !$request;
        $request->error($error) if $error;
    }
    Ravada::Request->add_hardware(
        uid => $args{id_owner}
        ,id_domain => $domain->id
        ,name => 'disk'
        ,data => { size => $data, type => 'data' }
    ) if $domain && $data;
    return $domain;
}

sub _check_args($args,@) {
    my %args_check = %$args;
    for my $field (@_) {
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
    confess "Error: Unknown domain $name"   if !$id;

    my $user = Ravada::Auth::SQL->search_by_id( $arg{uid});
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
            warn "Warning: I can't find domain '$id', maybe already removed.";
            $sth = $CONNECTOR->dbh->prepare("DELETE FROM domains where id=?");
            $sth->execute($id);
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
        ."    d.name=? "
        ;
    my $sth = $CONNECTOR->dbh->prepare($query);
    $sth->execute($name);
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

sub _search_domain {
    my $self = shift;
    my $name = shift;
    my $import = shift;

    my $vm = $self->search_vm('Void');
    warn "No Void VM" if !$vm;
    return if !$vm;

    my $domain = $vm->search_domain($name, $import);
    return $domain if $domain;

    my @vms;
    eval { @vms = $self->vm };
    return if $@ && $@ =~ /No VMs found/i;
    die $@ if $@;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain($name, $import);
        next if !$domain;
        next if !$domain->_select_domain_db && !$import;
        my $id;
        eval { $id = $domain->id };
        # TODO import the domain in the database with an _insert_db or something
        warn $@ if $@   && $DEBUG;
        next if !$id && !$import;

        $domain->_vm($domain->last_vm())    if $id && $domain->last_vm;
        return $domain;
    }


    return;
}

=head2 search_domain_by_id

  my $domain = $ravada->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
    my $id = shift  or confess "ERROR: missing argument id";

    my $sth = $CONNECTOR->dbh->prepare("SELECT name FROM domains WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    confess "Unknown domain id=$id" if !$name;

    return $self->search_domain($name);
}

=head2 list_vms

List all the Virtual Machine Managers

=cut

sub list_vms($self) {
    return @{$self->vm};
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
    $sth->execute(@values);
    while (my $row = $sth->fetchrow_hashref) {
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

    $self->_wait_pids();
    $self->_kill_stale_process();

    my $sth = $CONNECTOR->dbh->prepare("SELECT id,id_domain FROM requests "
        ." WHERE "
        ."    ( status='requested' OR status like 'retry%' OR status='waiting')"
        ."   AND ( at_time IS NULL  OR at_time = 0 OR at_time<=?) "
        ." ORDER BY date_req"
    );
    $sth->execute(time);

    my @reqs;
    while (my ($id_request,$id_domain)= $sth->fetchrow) {
        my $req;
        eval { $req = Ravada::Request->open($id_request) };

        next if $@ && $@ =~ /I can't find/;
        warn $@ if $@;
        next if !$req;

        next if !$req->requirements_done;

        next if $request_type ne 'all' && $req->type ne $request_type;

        next if $req->command !~ /shutdown/i
            && $self->_domain_working($id_domain, $id_request);

        push @reqs,($req);
    }

    for my $req (sort { $a->priority <=> $b->priority } @reqs) {
        next if $req eq 'refresh_vms' && scalar@reqs > 2;

        warn "[$request_type] $$ executing request ".$req->id." ".$req->status()." retry=".($req->retry or '<UNDEF>')." "
            .$req->command
            ." ".Dumper($req->args) if $DEBUG || $debug;

        my ($n_retry) = $req->status() =~ /retry (\d+)/;
        $n_retry = 0 if !$n_retry;

        $self->_execute($req, $dont_fork);
#        $req->status("done") if $req->status() !~ /retry/;
        next if !$DEBUG && !$debug;

        warn "req ".$req->id." , command: ".$req->command." , status: ".$req->status()
            ." , error: '".($req->error or 'NONE')."'\n"  if $DEBUG || $VERBOSE;
            #        sleep 1 if $DEBUG;

    }
    $sth->finish;

    $self->_timeout_requests();
}

sub _date_now($seconds = 0) {
    confess "Error, can't search what changed in the future "
        if $seconds > 0;
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
        ." ORDER BY date_req "
    );
    $sth->execute(_date_now(-30));

    my @requests;
    while (my ($id, $pid, $start_time) = $sth->fetchrow()) {
        my $req = Ravada::Request->open($id);
        my $timeout = $req->defined_arg('timeout') or next;
        next if time - $start_time <= $timeout;
        warn "request ".$req->pid." ".$req->command." timeout";
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

    $self->process_requests($debug, $dont_fork,'all');

}

=head2 process_priority_requests

Process all the priority requests, long and short

=cut

sub process_priority_requests($self, $debug=0, $dont_fork=0) {

    $self->process_requests($debug, $dont_fork,'priority');

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
        ." AND command = 'refresh_vms'"
        ." AND status <> 'done' "
        ." AND pid IS NOT NULL "
        ." AND start_time IS NOT NULL "
    );
    $sth->execute(time - $TIMEOUT_STALE_PROCESS);
    while (my ($id, $pid, $command, $start_time) = $sth->fetchrow) {
        if ($pid == $$ ) {
            warn "HOLY COW! I should kill pid $pid stale for ".(time - $start_time)
                ." seconds, but I won't because it is myself";
            next;
        }
        my $request = Ravada::Request->open($id);
        $request->stop();
     }
    $sth->finish;
}

sub _domain_working {
    my $self = shift;
    my ($id_domain, $id_request) = @_;

    confess "Missing id_request" if !defined$id_request;

    if (!$id_domain) {
        my $req = Ravada::Request->open($id_request);
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
        ." AND command <> 'set_base_vm')");
    $sth->execute($id_request, $id_domain);
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
    $request->pid($$);
    $request->start_time(time);
    $request->error('');
    if ($dont_fork || !$CAN_FORK) {
        $self->_do_execute_command($sub, $request);
        return;
    }

    $self->_wait_pids;
    return if !$self->_can_fork($request);

    my $pid = fork();
    die "I can't fork" if !defined $pid;

    if ( $pid == 0 ) {
        srand();
        $self->_do_execute_command($sub, $request);
        exit;
    }
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
    eval {
        $sub->($self,$request);
    };
    my $err = ( $@ or '');
    my $elapsed = tv_interval($t0,[gettimeofday]);
    $request->run_time($elapsed);
    $request->error($err)   if $err;
    if ($err) {
        my $user = $request->defined_arg('user');
        if ($user) {
            my $subject = $err;
            my $message = '';
            if (length($subject) > 40 ) {
                $message = $subject;
                $subject = substr($subject,0,40);
                $user->send_message($subject, $message);
            }
        }
    }
    if ($err && $err =~ /retry.?$/i) {
        my $retry = $request->retry;
        if (defined $retry && $retry>0) {
            $request->status('requested');
            $request->at(time + 10);
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
    $self->_set_domain_changed($request) if $request->status eq 'done';
}

sub _set_domain_changed($self, $request) {
    my $id_domain = $request->id_domain;
    if (!defined $id_domain) {
        $id_domain = $request->defined_arg('id_domain');
    }
    return if !defined $id_domain;

    my $sth = $CONNECTOR->dbh->prepare("UPDATE domains set date_changed=CURRENT_TIMESTAMP"
        ." WHERE id=? ");
    $sth->execute($id_domain);

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
        my $number = $domain->pool_clones() - scalar(@clone_pool);
        if ($number > 0 ) {
            $self->_pool_create_clones($domain, $number, $request);
        }
        my $count_active = 0;
        for my $clone_data (@clone_pool) {
            last if $count_active >= $domain->pool_start;
            my $clone = Ravada::Domain->open($clone_data->{id});
#            warn $clone->name."".($clone->client_status or '')." $count_active >= "
#    .$domain->pool_start."\n";
            if ( ! $clone->is_active ) {
                Ravada::Request->start_domain(
                    uid => $uid
                    ,id_domain => $clone->id
                );
                $count_active++;
            } else {
                $count_active++ if !$clone->client_status
                                || $clone->client_status =~ /disconnected/i;
            }
        }
    }
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
    Ravada::Request->clone(
        uid => $request->args('uid')
        ,id_domain => $domain->id
        ,number => $number
        ,add_to_pool => 1
        ,start => 1
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
       $msg = 'Domain '
            ."<a href=\"/machine/view/".$domain->id.".html\">"
            .$request->args('name')."</a>"
            ." created."
        ;
        $request->id_domain($domain->id);#    if !$request->args('id_domain');
        $request->status('done',$msg);
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
        my $request = Ravada::Request->open($id_req);
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
sub _wait_pids {
    my $self = shift;

    my @done;
    for my $type ( keys %{$self->{pids}} ) {
        for my $pid ( keys %{$self->{pids}->{$type}}) {
            my $kid = waitpid($pid , WNOHANG);
            push @done, ($pid) if $kid == $pid || $kid == -1;
        }
    }
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
        my $request = Ravada::Request->open($id_req);
        if ($request) {
            $request->status('done') if $request->status =~ /working/i;
        };
    }
}

sub _add_pid($self, $pid, $request) {

    my $type = $request->type;
    $self->{pids}->{$type}->{$pid} = $request->id;

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

    return _req_clone_many($self, $request) if $request->defined_arg('number')
    && $request->defined_arg('number') > 1;

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

    my $name = ( $request->defined_arg('name') or $domain->name."-".$user->name );

    my $clone = $domain->clone(
        name => $name
        ,%$args
    );
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
        );
        $args->{after_request} = $req_prepare->id;
    }
    my @reqs;
    for ( 1 .. $number ) {
        my $n = $_;
        my $name;
        for ( ;; ) {
            while (length($n) < length($number)) { $n = "0".$n };
            $name = $base->name."-".$n;
            last if !$domain_exists{$name}++;
            $n++;
        }
        $args->{name} = $name;
        my $req2 = Ravada::Request->clone( %$args );
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
    $domain = $self->search_domain_by_id($id_domain)    if $id_domain;
    die "Unknown domain '".($name or $id_domain)."'" if !$domain;
    $domain->status('starting');

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $self->_remove_unnecessary_downs($domain);

    my @args = ( user => $user );
    push @args, ( remote_ip => $request->defined_arg('remote_ip') )
        if $request->defined_arg('remote_ip');

    $domain->start(@args);

    Ravada::Request->manage_pools(
        uid => Ravada::Utils::user_daemon->id
    ) if $domain->is_pool && $request->defined_arg('remote_ip');

    my $msg = 'Domain '
            ."<a href=\"/machine/view/".$domain->id.".html\">"
            .$domain->name."</a>"
            ." started"
        ;
    $request->status('done', $msg);

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
                $is_active = $domain2->is_active;
            };
            warn $@ if $@;
            if (!$is_active) {
                my $req = Ravada::Request->start_domain(
                    uid => $uid
                   ,name => $name
                   ,remote_ip => $remote_ip);
            }
        }
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
                $is_active = $domain2->is_active;
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

    my $user = Ravada::Auth::SQL->search_by_id( $uid)
        or confess "Error: Unknown user id $uid in request ".Dumper($request);

    my $with_cd = $request->defined_arg('with_cd');

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $self->_remove_unnecessary_downs($domain);
    $domain->prepare_base(user => $user, with_cd => $with_cd);

}

sub _cmd_remove_base {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->id_domain or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

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
    $vm = $self->search_vm('KVM')   if !$vm;

    my $delay = $request->defined_arg('delay');
    sleep $delay if $delay;
    my $verbose = $request->defined_arg('verbose');

    my $iso = $vm->_search_iso($id_iso);
    if ($iso->{device} && -e $iso->{device}) {
        $request->status('done',"$iso->{device} already downloaded");
        return;
    }
    my $device_cdrom = $vm->_iso_name($iso, $request, $verbose);
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
        if !$user->is_admin;

    $domain->set_controller($hardware, $request->defined_arg('number'), $request->defined_arg('data'));
}

sub _cmd_remove_hardware {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $hardware = $request->args('name') or confess "Missing argument name";
    my $id_domain = $request->defined_arg('id_domain') or confess "Missing argument id_domain";
    my $index = $request->args('index');

    my $domain = $self->search_domain_by_id($id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $domain->remove_controller($hardware, $index);
}

sub _cmd_change_hardware {
    my $self = shift;
    my $request = shift;

    my $uid = $request->args('uid');
    my $hardware = $request->args('hardware') or confess "Missing argument hardware";
    my $id_domain = $request->args('id_domain') or confess "Missing argument id_domain";

    my $domain = $self->search_domain_by_id($id_domain);

    my $user = Ravada::Auth::SQL->search_by_id($uid);

    die "Error: User ".$user->name." not allowed\n"
        if !$user->is_admin;

    $domain->change_hardware(
         $request->args('hardware')
        ,$request->defined_arg('index')
        ,$request->args('data')
    );
}

sub _cmd_shutdown {
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

    $domain->force_shutdown($user,$request);

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

    confess "Unkown domain ".Dumper($request)   if !$domain;

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

    if ($request && ( my $id_recent = $request->done_recently(60))) {
        die "Command ".$request->command." run recently by $id_recent.\n";
    }
    my $vm;
    if ($request && $request->defined_arg('id_vm')) {
        $vm = Ravada::VM->open($request->defined_arg('id_vm'));
    } else {
        $vm = $self->search_vm('KVM');
    }
    $vm->refresh_storage();
}

sub _cmd_refresh_machine($self, $request) {

    my $id_domain = $request->args('id_domain');
    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'));
    my $domain = Ravada::Domain->open($id_domain) or confess "Error: domain $id_domain not found";
    $domain->check_status();
    $domain->list_volumes_info();
    $self->_remove_unnecessary_downs($domain) if !$domain->is_active;
    $domain->info($user);

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

    if ($request && (my $id_recent = $request->done_recently(30))) {
        die "Command ".$request->command." run recently by $id_recent.\n";
    }

    $self->_refresh_disabled_nodes( $request );
    $self->_refresh_down_nodes( $request );

    my $active_vm = $self->_refresh_active_vms();
    my $active_domain = $self->_refresh_active_domains($request);
    $self->_refresh_down_domains($active_domain, $active_vm);

    $self->_clean_requests('refresh_vms', $request);
    $self->_refresh_volatile_domains();
}

sub _cmd_shutdown_node($self, $request) {
    my $id_node = $request->args('id_node');
    my $node = Ravada::VM->open($id_node);
    $node->shutdown();
}

sub _cmd_start_node($self, $request) {
    my $id_node = $request->args('id_node');
    my $node = Ravada::VM->open($id_node);
    $node->start();
}

sub _cmd_connect_node($self, $request) {
    my $backend = $request->defined_arg('backend');
    my $hostname = $request->defined_arg('hostname');
    my $id_node = $request->defined_arg('id_node');

    my $node;

    if ($id_node) {
        $node = Ravada::VM->open($id_node);
        $hostname = $node->host;
    } else {
        $node = Ravada::VM->open( type => $backend
            , host => $hostname
            , store => 0
        );
    }

    die "I can't ping $hostname\n"
        if ! $node->ping();

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
    $node->connect() && $request->error("Connection OK");
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

sub _cmd_list_isos($self, $request){
    my $vm_type = $request->args('vm_type');
   
    my $vm = Ravada::VM->open( type => $vm_type );
    $vm->refresh_storage();
    my @isos = sort { "\L$a" cmp "\L$b" } $vm->search_volume_path_re(qr(.*\.iso$));

    $request->output(encode_json(\@isos));
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
    die "$@ , retry.\n" if $@;
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
    for my $vm ($self->list_vms) {
        if ( !$vm->enabled() || !$vm->is_active ) {
            $vm->shutdown_domains();
            $active_vm{$vm->id} = 0;
            $vm->disconnect();
            next;
        }
        $active_vm{$vm->id} = 1;
    }
    return \%active_vm;
}

sub _refresh_active_domains($self, $request=undef) {
    my $id_domain;
    $id_domain = $request->defined_arg('id_domain')  if $request;
    my %active_domain;

        if ($id_domain) {
            my $domain = $self->search_domain_by_id($id_domain);
            $self->_refresh_active_domain($domain, \%active_domain) if $domain;
         } else {
            my @domains;
            eval { @domains = $self->list_domains };
            warn $@ if $@;
            for my $domain (@domains) {
                next if $active_domain{$domain->id};
                next if $domain->is_hibernated;
                $self->_refresh_active_domain($domain, \%active_domain);
                $self->_remove_unnecessary_downs($domain) if !$domain->is_active;
            }
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
    }
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
    $domain->check_status();
    return if $domain->is_hibernated();

    my $is_active = $domain->is_active();

    my $status = 'shutdown';
    if ( $is_active ) {
        $status = 'active';
    }
    $domain->_set_data(status => $status);
    $domain->info(Ravada::Utils::user_daemon)             if $is_active;
    $active_domain->{$domain->id} = $is_active;

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
        } else {
            my $status = 'shutdown';
            $status = 'active' if $domain->is_active;
            $domain->_set_data(status => $status);
            for my $req ( $domain->list_requests ) {
                next if $req->command !~ /shutdown/i;
                $req->status('done');
            }
        }
    }
}

sub _remove_unnecessary_downs($self, $domain) {

        my @requests = $domain->list_requests(1);
        for my $req (@requests) {
            $req->status('done') if $req->command =~ /shutdown/;
            $req->_remove_messages();
        }
}

sub _refresh_volatile_domains($self) {
   my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, id_vm, id_owner FROM domains WHERE is_volatile=1"
    );
    $sth->execute();
    while ( my ($id_domain, $name, $id_vm, $id_owner) = $sth->fetchrow ) {
        my $domain;
        eval { $domain = Ravada::Domain->open(id => $id_domain, _force => 1) } ;
        if ( !$domain || $domain->status eq 'down' || !$domain->is_active) {
            if ($domain) {
                $domain->_post_shutdown(user => $USER_DAEMON);
                $domain->remove($USER_DAEMON);
            } else {
                confess;
                my $sth= $CONNECTOR->dbh->prepare(
                "DELETE FROM users where id=? "
                ." AND is_temporary=1");
                $sth->execute($id_owner);
                $sth->finish;
            }
            my $sth_del = $CONNECTOR->dbh->prepare("DELETE FROM domains WHERE id=?");
            $sth_del->execute($id_domain);
            $sth_del->finish;

            $sth_del = $CONNECTOR->dbh->prepare("DELETE FROM requests where id_domain=?");
            $sth_del->execute($id_domain);
            $sth_del->finish;
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

    my $user = Ravada::Auth::SQL->search_by_id($uid);
    my $domain = Ravada::Domain->open($id_domain) or confess "Error: Unknown domain id $id_domain";

    #    my $domain = $self->search_domain_by_id($id_domain) or confess "Error: Unknown domain id: $id_domain";

    die "USER $uid not authorized to set base vm"
        if !$user->is_admin;

    $domain->prepare_base($user) if $value && !$domain->is_base;

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
    $self->_clean_requests('cleanup', $request);
    for my $cmd ( qw(cleanup enforce_limits refresh_vms
        manage_pools refresh_machine screenshot
        open_iptables ping_backend
        )) {
            $self->_clean_requests($cmd, $request,'done');
    }
}

sub _shutdown_disconnected($self) {
    for my $dom ( $self->list_domains_data(status => 'active') ) {
        next if !$dom->{shutdown_disconnected};
        my $domain = Ravada::Domain->open($dom->{id});
        my $is_active = $domain->is_active;
        my ($req_shutdown) = grep { $_->command eq 'shutdown' } $domain->list_requests(1);
        if ($is_active && $domain->client_status eq 'disconnected') {
            next if $req_shutdown;
            Ravada::Request->shutdown_domain(
                uid => Ravada::Utils::user_daemon->id
                ,id_domain => $domain->id
                ,at => time + 120
            );
        } else {
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
        ,restore_domain => \&_cmd_restore_domain
        ,resume => \&_cmd_resume
       ,dettach => \&_cmd_dettach
       ,cleanup => \&_cmd_cleanup
      ,download => \&_cmd_download
      ,shutdown => \&_cmd_shutdown
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
,enforce_limits => \&_cmd_enforce_limits
,force_shutdown => \&_cmd_force_shutdown
        ,rebase => \&_cmd_rebase

,refresh_storage => \&_cmd_refresh_storage
,refresh_machine => \&_cmd_refresh_machine
,domain_autostart=> \&_cmd_domain_autostart
,change_owner => \&_cmd_change_owner
,add_hardware => \&_cmd_add_hardware
,remove_hardware => \&_cmd_remove_hardware
,change_hardware => \&_cmd_change_hardware
,set_time => \&_cmd_set_time

# Domain ports
,expose => \&_cmd_expose
,remove_expose => \&_cmd_remove_expose
,open_exposed_ports => \&_cmd_open_exposed_ports
# Virtual Managers or Nodes
    ,shutdown_node  => \&_cmd_shutdown_node
    ,start_node  => \&_cmd_start_node
    ,connect_node  => \&_cmd_connect_node

    #users
    ,post_login => \&_cmd_post_login

    #networks
    ,list_network_interfaces => \&_cmd_list_network_interfaces

    #isos
    ,list_isos => \&_cmd_list_isos

    ,manage_pools => \&_cmd_manage_pools
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
    return Ravada::VM->open($id)    if $id;
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
        "SELECT id FROM vms "
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
        push @vms, ( $vm );
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
}

sub _enforce_limits_active($self, $request) {

    confess if !$request;
    if (my $id_recent = $request->done_recently(30)) {
        die "Command ".$request->command." run recently by $id_recent.\n";
    }
    my $timeout = ($request->defined_arg('timeout') or 10);
    my $start_limit = $self->setting('/backend/start_limit');

    my %domains;
    for my $domain ($self->list_domains( active => 1 )) {
        push @{$domains{$domain->id_owner}},$domain;
        $domain->client_status();
    }
    for my $id_user(keys %domains) {
        next if scalar @{$domains{$id_user}} <= $start_limit;
        my $user = Ravada::Auth::SQL->search_by_id($id_user);
        next if $user->is_admin;
        next if $user->can_start_many;

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
            $user->send_message("Too many machines started. $active out of $start_limit. Stopping ".$domain->name);
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

    my $sth_del = $CONNECTOR->dbh->prepare(
        "DELETE FROM users "
        ." WHERE is_temporary = 1 AND id=?"
    );
    my $one_day = _date_now(-24 * 60 * 60);
    $sth_users->execute( $one_day );
    while ( my ( $id_user, $id_domain, $date_created ) = $sth_users->fetchrow ) {
        next if $id_domain;
        $sth_del->execute($id_user);
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
            eval { $domain_real->_post_shutdown() };
            warn $@ if $@;
            eval { $domain_real->remove($USER_DAEMON) };
            warn $@ if $@;
        } elsif ($domain->{id_owner}) {
            my $sth = $CONNECTOR->dbh->prepare(
                "DELETE FROM users where id=? "
                ."AND is_temporary=1");
            $sth->execute($domain->{id_owner});
        }

        $sth_remove->execute($domain->{id});
    }
}

sub _cmd_post_login($self, $request) {
    $self->_post_login_locale($request);
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
    my $domain = Ravada::Domain->open($request->id_domain);
    $domain->open_exposed_ports();
}

sub setting($self, $name) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,value "
        ." FROM settings "
        ." WHERE id_parent=? AND name=?"
    );
    my ($id, $value);
    my $id_parent = 0;
    for my $item (split m{/},$name) {
        next if !$item;
        $sth->execute($id_parent, $item);
        ($id, $value) = $sth->fetchrow;
        die "Error: I can-t find setting $item inside id_parent: $id_parent"
        if !$id;

        $id_parent = $id;
    }
    return $value;
}

sub DESTROY($self) {
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
