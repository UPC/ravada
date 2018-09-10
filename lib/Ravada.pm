package Ravada;

use warnings;
use strict;

our $VERSION = '0.3.0-beta6';

use Carp qw(carp croak);
use Data::Dumper;
use DBIx::Connector;
use File::Copy;
use Hash::Util qw(lock_hash);
use Moose;
use Parallel::ForkManager;
use POSIX qw(WNOHANG);
use Time::HiRes qw(gettimeofday tv_interval);
use YAML;

use Socket qw( inet_aton inet_ntoa );

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Auth;
use Ravada::Request;
use Ravada::VM::Void;

our %VALID_VM;
our %ERROR_VM;

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

=head1 NAME

Ravada - Remove Virtual Desktop Manager

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

    $self->_create_tables();
    $self->_upgrade_tables();
    $self->_update_data();
    $self->_init_user_daemon();
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
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM users");
    my $id;
    $sth->execute;
    $sth->bind_columns(\$id);
    while ($sth->fetch) {
        my $user = Ravada::Auth::SQL->search_by_id($id);
        next if $user->name() eq $USER_DAEMON_NAME;

        next if $user->grants();
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
        mate_artful => {
                    name => 'Ubuntu Mate Artful'
            ,description => 'Ubuntu Mate 17.10.1 (Artful) 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'yakkety64-amd64.xml'
             ,xml_volume => 'yakkety64-volume.xml'
                    ,url => 'http://cdimage.ubuntu.com/ubuntu-mate/releases/17.10.*/release/ubuntu-mate-17.10.*-desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
                ,min_disk_size => '10'
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
        alpine_37 => {
                    name => 'Alpine 3.7'
            ,description => 'Alpine Linux 3.7 64 bits ( Minimal Linux Distribution)'
                   ,arch => 'amd64'
                    ,xml => 'yakkety64-amd64.xml'
             ,xml_volume => 'yakkety64-volume.xml'
                    ,url => 'http://dl-cdn.alpinelinux.org/alpine/v3.7/releases/x86_64/'
                ,file_re => 'alpine-virt-3.7.\d+-x86_64.iso'
                ,sha256_url => 'http://dl-cdn.alpinelinux.org/alpine/v3.7/releases/x86_64/alpine-virt-3.7.0-x86_64.iso.sha256'
                ,min_disk_size => '1'
        }
        ,artful => {
                    name => 'Ubuntu Artful Aardvark'
            ,description => 'Ubuntu 17.10 Artful Aardvark 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'yakkety64-amd64.xml'
             ,xml_volume => 'yakkety64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/17.10/'
                ,file_re => 'ubuntu-17.10.*desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
          ,min_disk_size => '10'
        }
        ,bionic=> {
                    name => 'Ubuntu Bionic Beaver'
            ,description => 'Ubuntu 18.04 Bionic Beaver 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'bionic-amd64.xml'
             ,xml_volume => 'bionic64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/18.04/'
                ,file_re => 'ubuntu-18.04.*desktop-amd64.iso'
                ,md5_url => '$url/MD5SUMS'
          ,min_disk_size => '9'
        }

        ,zesty => {
                    name => 'Ubuntu Zesty Zapus'
            ,description => 'Ubuntu 17.04 Zesty Zapus 64 bits'
                   ,arch => 'amd64'
                    ,xml => 'yakkety64-amd64.xml'
             ,xml_volume => 'yakkety64-volume.xml'
                    ,url => 'http://releases.ubuntu.com/17.04/'
                ,file_re => 'ubuntu-17.04.*desktop-amd64.iso'
                ,md5_url => 'http://releases.ubuntu.com/17.04/MD5SUMS'
                ,min_disk_size => '10'
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
        ,fedora => {
            name => 'Fedora 25'
            ,description => 'RedHat Fedora 25 Workstation 64 bits'
            ,url => 'http://ftp.halifax.rwth-aachen.de/fedora/linux/releases/25/Workstation/x86_64/iso/Fedora-Workstation-netinst-x86_64-25-.*\.iso'
            ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
            ,xml_volume => 'xenial64-volume.xml'
            ,sha256_url => '$url/Fedora-Workstation-25-.*-x86_64-CHECKSUM'
            ,min_disk_size => '10'
        }
        ,fedora_26 => {
            name => 'Fedora 26'
            ,description => 'RedHat Fedora 26 Workstation 64 bits'
            ,url => 'http://ftp.halifax.rwth-aachen.de/fedora/linux/releases/26/Workstation/x86_64/iso/Fedora-Workstation-netinst-x86_64-26-.*\.iso'
            ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
            ,xml_volume => 'xenial64-volume.xml'
            ,sha256_url => 'http://fedora.mirrors.ovh.net/linux/releases/26/Workstation/x86_64/iso/Fedora-Workstation-26-.*-x86_64-CHECKSUM'
            ,min_disk_size => '10'
        }
        ,fedora_27 => {
            name => 'Fedora 27'
            ,description => 'RedHat Fedora 27 Workstation 64 bits'
            ,url => 'http://ftp.halifax.rwth-aachen.de/fedora/linux/releases/27/Workstation/x86_64/iso/Fedora-Workstation-netinst-x86_64-27-.*\.iso'
            ,arch => 'amd64'
            ,xml => 'xenial64-amd64.xml'
            ,xml_volume => 'xenial64-volume.xml'
            ,sha256_url => 'http://fedora.mirrors.ovh.net/linux/releases/27/Workstation/x86_64/iso/Fedora-Workstation-27-.*-x86_64-CHECKSUM'
            ,min_disk_size => '10'
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
            ,arch => 'amd64'
            ,xml => 'bionic-i386.xml'
            ,xml_volume => 'bionic32-volume.xml'
            ,md5_url => '$url/../MD5SUMS'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-i386/current/images/netboot/'
            ,file_re => 'mini.iso'
            ,rename_file => 'xubuntu_bionic_32.iso'
        }
        ,xubuntu_artful => {
            name => 'Xubuntu Artful Aardvark'
            ,description => 'Xubuntu 17.10 Artful Aardvark 64 bits'
            ,arch => 'amd64'
            ,xml => 'yakkety64-amd64.xml'
            ,xml_volume => 'yakkety64-volume.xml'
            ,md5_url => '$url/../MD5SUMS'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/artful/main/installer-amd64/current/images/netboot/'
            ,file_re => 'mini.iso'
            ,rename_file => 'xubuntu_artful.iso'
            ,min_disk_size => '10'
        }
        ,xubuntu_zesty => {
            name => 'Xubuntu Zesty Zapus'
            ,description => 'Xubuntu 17.04 Zesty Zapus 64 bits'
            ,arch => 'amd64'
            ,xml => 'yakkety64-amd64.xml'
            ,xml_volume => 'yakkety64-volume.xml'
            ,md5_url => '$url/../MD5SUMS'
            ,url => 'http://archive.ubuntu.com/ubuntu/dists/zesty/main/installer-amd64/current/images/netboot'
            ,file_re => 'mini.iso'
            ,rename_file => 'xubuntu_zesty_mini.iso'
            ,min_disk_size => '10'
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
        ,lubuntu_aardvark => {
            name => 'Lubuntu Artful Aardvark'
            ,description => 'Lubuntu 17.10 Artful Aardvark 64 bits'
            ,url => 'http://cdimage.ubuntu.com/lubuntu/releases/17.10.*/release/lubuntu-17.10.*-desktop-amd64.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'yakkety64-amd64.xml'
            ,xml_volume => 'yakkety64-volume.xml'
            ,min_disk_size => '10'
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
        ,debian_stretch => {
            name =>'Debian Stretch 64 bits'
            ,description => 'Debian 9 Stretch 64 bits (XFCE desktop)'
            ,url => 'https://cdimage.debian.org/debian-cd/^9\..*/amd64/iso-cd/'
            ,file_re => 'debian-9.[\d\.]+-amd64-xfce-CD-1.iso'
            ,md5_url => '$url/MD5SUMS'
            ,xml => 'jessie-amd64.xml'
            ,xml_volume => 'jessie-volume.xml'
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
    );

    $self->_update_table($table, $field, \%data);

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

sub _update_table($self, $table, $field, $data) {

    my $sth_search = $CONNECTOR->dbh->prepare("SELECT id FROM $table WHERE $field = ?");
    for my $name (keys %$data) {
        my $row = $data->{$name};
        $sth_search->execute($row->{$field});
        my ($id) = $sth_search->fetchrow;
        next if $id;
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
    $self->_update_old_qemus();

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
    $self->_add_grant('shutdown', 1);
    $self->_add_grant('screenshot', 1);
}

sub _add_grant($self, $grant, $allowed) {

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM grant_types WHERE name=?"
    );
    $sth->execute($grant);
    my ($id) = $sth->fetchrow();
    $sth->finish;

    return if $id;

    $sth = $CONNECTOR->dbh->prepare("INSERT INTO grant_types (name, description)"
        ." VALUES (?,?)");
    $sth->execute($grant,"can shutdown any virtual machine owned by the user");
    $sth->finish;

    return if !$allowed;

    $sth = $CONNECTOR->dbh->prepare("SELECT id FROM grant_types WHERE name=?");
    $sth->execute($grant);
    my ($id_grant) = $sth->fetchrow;
    $sth->finish;

    my $sth_insert = $CONNECTOR->dbh->prepare(
        "INSERT INTO grants_user (id_user, id_grant, allowed) VALUES(?,?,?) ");

    $sth = $CONNECTOR->dbh->prepare("SELECT id FROM users ");
    $sth->execute;

    while (my ($id_user) = $sth->fetchrow ) {
        eval { $sth_insert->execute($id_user, $id_grant, $allowed) };
        die $@ if $@ && $@ !~/Duplicate entry /;
    }
}

sub _null_grants($self) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT count(*) FROM grant_types "
            ." WHERE enabled = NULL "
        );
    $sth->execute;
    my ($count) = $sth->fetchrow;

    exit if !$count && $self->{_null}++;
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
        ,'grant'
        ,'manage_users'
        ,'remove',          'remove_all',   'remove_clone',     'remove_clone_all'
        ,'screenshot'
        ,'shutdown',        'shutdown_all',    'shutdown_clone'
        ,'screenshot'
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

    my $sth = $dbh->column_info(undef,undef,$table,$field);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    return if $row;

    warn "INFO: adding $field $definition to $table\n"  if $0 !~ /\.t$/;
    $dbh->do("alter table $table add $field $definition");
    return 1;
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
    $self->_upgrade_table('vms','cached_active_time',"integer DEFAULT 0");
    $self->_upgrade_table('vms','public_ip',"varchar(128) DEFAULT NULL");
    $self->_upgrade_table('vms','is_active',"int DEFAULT 0");

    $self->_upgrade_table('vms','min_free_memory',"text DEFAULT NULL");
    $self->_upgrade_table('vms', 'max_load', 'int not null default 10');
    $self->_upgrade_table('vms', 'active_limit','int DEFAULT NULL');
    $self->_upgrade_table('vms', 'base_storage','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('vms', 'clone_storage','varchar(64) DEFAULT NULL');

    $self->_upgrade_table('requests','at_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','pid','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','start_time','int(11) DEFAULT NULL');

    $self->_upgrade_table('requests','at_time','int(11) DEFAULT NULL');
    $self->_upgrade_table('requests','run_time','float DEFAULT NULL');

    $self->_upgrade_table('iso_images','rename_file','varchar(80) DEFAULT NULL');
    $self->_clean_iso_mini();
    $self->_upgrade_table('iso_images','md5_url','varchar(255)');
    $self->_upgrade_table('iso_images','sha256','varchar(255)');
    $self->_upgrade_table('iso_images','sha256_url','varchar(255)');
    $self->_upgrade_table('iso_images','file_re','char(64)');
    $self->_upgrade_table('iso_images','device','varchar(255)');
    $self->_upgrade_table('iso_images','min_disk_size','int (11) DEFAULT NULL');

    $self->_upgrade_table('users','language','char(3) DEFAULT NULL');
    if ( $self->_upgrade_table('users','is_external','int(11) DEFAULT 0')) {
        my $sth = $CONNECTOR->dbh->prepare(
            "UPDATE users set is_external=1 WHERE password='*LK* no pss'"
        );
        $sth->execute;
    }

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
    $self->_upgrade_table('domains','display','varchar(128) DEFAULT NULL');
    $self->_upgrade_table('domains','info','varchar(255) DEFAULT NULL');
    $self->_upgrade_table('domains','internal_id','varchar(64) DEFAULT NULL');
    $self->_upgrade_table('domains','id_vm','int default null');
    $self->_upgrade_table('domains','volatile_clones','int NOT NULL default 0');

    $self->_upgrade_table('domains','client_status','varchar(32)');
    $self->_upgrade_table('domains','client_status_time_checked','int NOT NULL default 0');

    $self->_upgrade_table('domains','needs_restart','int not null default 0');
    $self->_upgrade_table('domains_network','allowed','int not null default 1');

    $self->_upgrade_table('iptables','id_vm','int DEFAULT NULL');
    $self->_upgrade_table('vms','security','varchar(255) default NULL');
    $self->_upgrade_table('grant_types','enabled','int not null default 1');

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

sub display_ip {
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
        die "$vm not available in this system.\n".($ERROR_VM{$vm})
            if !exists $VALID_VM{$vm} || !$VALID_VM{$vm};
    }

    for my $vm ( keys %VALID_VM ) {
        delete $VALID_VM{$vm}
            if exists $VALID_VM{$vm}
                && exists $CONFIG->{vm}
                && scalar @{$CONFIG->{vm}}
                && !grep /^$vm$/,@{$CONFIG->{vm}};
    }

    lock_hash(%VALID_VM);

    @Ravada::Front::VM_TYPES = keys %VALID_VM;
}

sub _create_vm_kvm {
    my $self = shift;
    die "KVM not installed" if !$VALID_VM{KVM};

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

    return Ravada::VM::LXC->new( connector => ( $self->connector or $CONNECTOR ));
}

sub _create_vm_void {
    my $self = shift;

    return Ravada::VM::Void->new( connector => ( $self->connector or $CONNECTOR ));
}

sub _create_vm {
    my $self = shift;

    # TODO: add a _create_vm_default for VMs that just are created with ->new
    #       like Void or LXC
    my %create = (
        'KVM' => \&_create_vm_kvm
        ,'LXC' => \&_create_vm_lxc
        ,'Void' => \&_create_vm_void
    );

    my @vms = ();
    my $err = '';

    for my $vm_name (keys %VALID_VM) {
        my $vm;
        eval { $vm = $create{$vm_name}->($self) };
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
    my $vm_name = delete $args{vm};

    my $request = $args{request};
    %args = %{$request->args}   if $request;

    my $start = $args{start};
    my $id_base = $args{id_base};
    my $id_owner = $args{id_owner};

    my $vm;
    if ($vm_name) {
        $vm = $self->search_vm($vm_name);
        confess "ERROR: vm $vm_name not found"  if !$vm;
    }
    if ($id_base) {
        my $base = Ravada::Domain->open($id_base)
            or confess "Unknown base id: $id_base";
        $vm = $base->_vm;
    }

    confess "No vm found, request = ".Dumper(request => $request)   if !$vm;

    carp "WARNING: no VM defined, we will use ".$vm->name
        if !$vm_name && !$id_base;

    confess "I can't find any vm ".Dumper($self->vm) if !$vm;

    $request->status("creating")    if $request;
    my $domain;
    delete $args{'at'};
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
            my $user = Ravada::Auth::SQL->search_by_id($id_owner);
            my $remote_ip;
            $remote_ip = $request->defined_arg('remote_ip') if $request;
            $domain->start(
                user => $user
                ,remote_ip => $remote_ip
                ,request => $request
            )
        };
        my $error = $@;
        die $error if $error && !$request;
        $request->error($error) if $error;
    }
    return $domain;
}

sub _check_args($args,@) {
    for my $field (@_) {
        delete $args->{$field};
    }
    confess "ERROR: Unknown arguments ".Dumper($args) if keys %$args;
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

    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM domains WHERE name = ?");
    $sth->execute($name);

    my ($id)= $sth->fetchrow;
    confess "Error: Unknown domain $name"   if !$id;

    my $user = Ravada::Auth::SQL->search_by_id( $arg{uid});
    die "Error: user ".$user->name." can't remove domain $id"
        if !$user->can_remove_machine($id);

    my $domain = Ravada::Domain->open(id => $id, _force => 1)
        or do {
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
    my $sth = $CONNECTOR->dbh->prepare("SELECT id,id_vm "
        ." FROM domains WHERE name=?");
    $sth->execute($name);
    my ($id, $id_vm) = $sth->fetchrow();

    return if !$id;
    if ($id_vm) {
        my $vm = Ravada::VM->open($id_vm);
        if (!$vm->is_active) {
            warn "Don't search domain $name in inactive VM ".$vm->name;
            $vm->disconnect();
        } else {
            return $vm->search_domain($name);
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
            next if defined $active && !$domain->is_removed &&
                ( $domain->is_active && !$active
                    || !$domain->is_active && $active );

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

    $self->_kill_stale_process();

    my $sth = $CONNECTOR->dbh->prepare("SELECT id,id_domain FROM requests "
        ." WHERE "
        ."    ( status='requested' OR status like 'retry%' OR status='waiting')"
        ."   AND ( at_time IS NULL  OR at_time = 0 OR at_time<=?) "
        ." ORDER BY date_req"
    );
    $sth->execute(time);

    while (my ($id_request,$id_domain)= $sth->fetchrow) {
        my $req;
        eval { $req = Ravada::Request->open($id_request) };

        next if $@ && $@ =~ /I can't find/;
        warn $@ if $@;
        next if !$req;

        next if $request_type ne 'all' && $req->type ne $request_type;

        next if $req->command !~ /shutdown/i
            && $self->_domain_working($id_domain, $id_request);

        warn "[$request_type] $$ executing request ".$req->id." ".$req->status()." "
            .$req->command
            ." ".Dumper($req->args) if $DEBUG || $debug;

        my ($n_retry) = $req->status() =~ /retry (\d+)/;
        $n_retry = 0 if !$n_retry;

        $self->_execute($req, $dont_fork);
#        $req->status("done") if $req->status() !~ /retry/;
        next if !$DEBUG && !$debug;

        warn "req ".$req->id." , command: ".$req->command." , status: ".$req->status()
            ." , error: '".($req->error or 'NONE')."'\n"  if $DEBUG || $VERBOSE;
        sleep 1 if $DEBUG;

    }
    $sth->finish;
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

sub process_priority_requests($self, $debug=0, $dont_fork=0) {

    $self->process_requests($debug, $dont_fork,'priority');

}

sub _kill_stale_process($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT pid,command,start_time "
        ." FROM requests "
        ." WHERE start_time<? "
        ." AND command = 'refresh_vms'"
        ." AND status <> 'done' "
        ." AND pid IS NOT NULL "
        ." AND start_time IS NOT NULL "
    );
    $sth->execute(time - 60 );
    while (my ($pid, $command, $start_time) = $sth->fetchrow) {
        if ($pid == $$ ) {
            warn "HOLY COW! I should kill pid $pid stale for ".(time - $start_time)
                ." seconds, but I won't because it is myself";
            next;
        }
        warn "Killing $command stale for ".(time - $start_time)." seconds\n";
        kill (15,$pid);
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
            my $domain = $self->search_domain($domain_name) or return;
            $id_domain = $domain->id;
            if (!$id_domain) {
                warn Dumper($req);
                return;
            }
        }
    }
    my $sth = $CONNECTOR->dbh->prepare("SELECT id, status FROM requests "
        ." WHERE id <> ? AND id_domain=? AND (status <> 'requested' AND status <> 'done')");
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

    confess "Unknown command ".$request->command
            if !$sub;

    $request->pid($$);
    $request->start_time(time);
    $request->error('');
    if ($dont_fork || !$CAN_FORK) {

        my $t0 = [gettimeofday];
        eval { $sub->($self,$request) };
        my $err = ($@ or '');
        my $elapsed = tv_interval($t0,[gettimeofday]);
        $request->run_time($elapsed);
        $request->status('done') if $request->status() ne 'done'
                                    && $request->status !~ /retry/;
        $request->error($err) if $err;
        return;
    }

    if ( $self->_wait_requests($request) ) {
         $request->status("requested","Server loaded, queuing request");
         return;
     }

    $request->status('working','');
    if (!$self->{fork_manager}) {
        my $fm = Parallel::ForkManager->new($request->requests_limit('priority'));
        $self->{fork_manager} = $fm;
    }
    $self->{fork_manager}->reap_finished_children;
    my $pid = $self->{fork_manager}->start;
    die "I can't fork" if !defined $pid;

    if ( $pid == 0 ) {
        my $t0 = [gettimeofday];
        $self->_do_execute_command($sub, $request);
        $self->{fork_manager}->finish; # Terminates the child process
        my $elapsed = tv_interval($t0,[gettimeofday]);
        $request->run_time($elapsed) if !$request->run_time();
        exit;
    }
    $request->pid($pid);
    $self->{fork_manager}->reap_finished_children;
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

    my $t0 = [gettimeofday];
    eval {
        $sub->($self,$request);
    };
    my $err = ( $@ or '');
    my $elapsed = tv_interval($t0,[gettimeofday]);
    $request->run_time($elapsed);
    $request->error($err)   if $err;
    $request->status('done')
        if $request->status() ne 'done'
            && $request->status() !~ /^retry/i;

}

sub _cmd_domdisplay {
    my $self = shift;
    my $request = shift;

    my $name = $request->args('name');
    confess "Unknown name for request ".Dumper($request)  if!$name;
    my $domain = $self->search_domain($request->args->{name});
    my $user = Ravada::Auth::SQL->search_by_id( $request->args->{uid});
    $request->error('');
    my $display = $domain->display($user);
    $request->result({display => $display});

}

sub _cmd_screenshot {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->args('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);
    my $bytes = 0;
    if (!$domain->can_screenshot) {
        die "I can't take a screenshot of the domain ".$domain->name;
    } else {
        $bytes = $domain->screenshot($request->args('filename'));
        $bytes = $domain->screenshot($request->args('filename'))    if !$bytes;
    }
    $request->error("No data received") if !$bytes;
}

sub _cmd_copy_screenshot {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->args('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);

    my $id_base = $domain->id_base;
    my $base = $self->search_domain_by_id($id_base);

    if (!$domain->file_screenshot) {
        die "I don't have the screenshot of the domain ".$domain->name;
    } else {

        my $base_screenshot = $domain->file_screenshot();

        $base_screenshot =~ s{(.*)/\d+\.(\w+)}{$1/$id_base.$2};
        $base->_post_screenshot($base_screenshot);

        copy($domain->file_screenshot, $base_screenshot);
    }
}

sub _cmd_create{
    my $self = shift;
    my $request = shift;

    $request->status('creating domain');
    warn "$$ creating domain ".Dumper($request->args)   if $DEBUG;
    my $domain;

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

sub _wait_requests {
    my $self = shift;
    my $req = shift or confess "Missing request";

    # don't wait for priority requests
    return if $req->type eq 'priority';

    my $try = 0;
    for ( 1 .. $SECONDS_WAIT_CHILDREN ) {

        my $msg;

        my $n_pids = $req->count_requests();

        $msg = $req->command
                ." waiting for processes to finish $n_pids"
                ." of ".$req->requests_limit;
        return if $n_pids < $req->requests_limit();
        return 1 if $n_pids > $req->requests_limit + 2;
        sleep 1;

        next if $try++;

        $req->error($msg);
        $req->status('waiting') if $req->status() !~ 'waiting';
    }
    return 1;
}

sub _set_req_done {
    my $self = shift;
    my $pid = shift;

    my $id_request = $self->{pids}->{$pid};
    return if !$id_request;

    my $req = Ravada::Request->open($id_request);
    $req->status('done')    if $req->status =~ /working/i;
}

sub _cmd_remove {
    my $self = shift;
    my $request = shift;

    confess "Unknown user id ".$request->args->{uid}
        if !defined $request->args->{uid};

    $self->remove_domain(name => $request->args('name'), uid => $request->args('uid'));

}

sub _cmd_pause {
    my $self = shift;
    my $request = shift;

    my $name = $request->args('name');
    my $domain = $self->search_domain($name);
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

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
    my $domain = Ravada::Domain->open($request->args('id_domain'));

    my @args = ( request => $request);
    push @args, ( memory => $request->args('memory'))
        if $request->defined_arg('memory');

    my $user = Ravada::Auth::SQL->search_by_id($request->args('uid'))
        or die "Error: User missing, id: ".$request->args('uid');
    push @args,(user => $user);
    $domain->clone(
        name => $request->args('name')
        ,@args
    );

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
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $domain->start(user => $user, remote_ip => $request->args('remote_ip'));
    my $msg = 'Domain '
            ."<a href=\"/machine/view/".$domain->id.".html\">"
            .$domain->name."</a>"
            ." started"
        ;
    $request->status('done', $msg);

}

sub _cmd_prepare_base {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->id_domain   or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $domain->prepare_base($user);

}

sub _cmd_remove_base {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->id_domain or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $domain->_vm->disconnect();
    $self->_disconnect_vm();
    $domain->remove_base($user);

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
    my $number = $request->args('number');
    
    my $domain = $self->search_domain_by_id($id_domain);
    
    my $user = Ravada::Auth::SQL->search_by_id($uid);
    
    $domain->set_controller($hardware, $number);
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
    }

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
    my ($active_domain, $active_vm) = $self->_refresh_active_domains($request);
    $self->_refresh_down_domains($active_domain, $active_vm);

    $self->_clean_requests('refresh_vms', $request);
    $self->_refresh_volatile_domains();
}

sub _cmd_change_max_memory($self, $request) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain');
    my $memory = $request->args('ram');
    
    my $domain = $self->search_domain_by_id($id_domain);
    $domain->set_max_mem($memory);
}

sub _cmd_change_curr_memory($self, $request) {
    my $uid = $request->args('uid');
    my $id_domain = $request->args('id_domain');
    my $memory = $request->args('ram');
    
    my $domain = $self->search_domain_by_id($id_domain);
    $domain->set_memory($memory);
}

sub _clean_requests($self, $command, $request=undef) {
    my $query = "DELETE FROM requests "
        ." WHERE command=? "
        ."   AND status='requested'";

    if ($request) {
        confess "Wrong request" if !ref($request) || ref($request) !~ /Request/;
        $query .= "   AND id <> ?";
    }
    my $sth = $CONNECTOR->dbh->prepare($query);

    if ($request) {
        $sth->execute($command, $request->id);
    } else {
        $sth->execute($command);
    }
}

sub _refresh_active_domains($self, $request=undef) {
    my $id_domain;
    $id_domain = $request->defined_arg('id_domain')  if $request;

    my %active_domain;
    my %active_vm;
    for my $vm ($self->list_vms) {
        if ( !$vm->is_active ) {
            $active_vm{$vm->id} = 0;
            $vm->disconnect();
            next;
        }
        $active_vm{$vm->id} = 1;
        if ($id_domain) {
            my $domain = $vm->search_domain_by_id($id_domain);
            $self->_refresh_active_domain($vm, $domain, \%active_domain) if $domain;
         } else {
            for my $domain ($vm->list_domains( active => 1)) {
                next if $active_domain{$domain->id};
                next if $domain->is_hibernated;
                $self->_refresh_active_domain($vm, $domain, \%active_domain);
            }
        }
    }
    return \%active_domain, \%active_vm;
}

sub _refresh_active_domain($self, $vm, $domain, $active_domain) {
    return if $domain->is_hibernated();

    my $is_active = $domain->is_active();

    my $status = 'shutdown';
    if ( $is_active ) {
        $status = 'active';
        $domain->_data(id_vm => $vm->id)
            if !defined$domain->_data('id_vm')
                || $domain->_data('id_vm') != $vm->id;
    }
    $domain->_set_data(status => $status);
    $active_domain->{$domain->id} = $is_active;

}

sub _refresh_down_domains($self, $active_domain, $active_vm) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, id_vm FROM domains WHERE status='active'"
    );
    $sth->execute();
    while ( my ($id_domain, $name, $id_vm) = $sth->fetchrow ) {
        next if exists $active_domain->{$id_domain};

        my $domain = Ravada::Domain->open($id_domain) or next;
        next if $domain->is_hibernated;

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

sub _refresh_volatile_domains($self) {
   my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, name, id_vm FROM domains WHERE is_volatile=1"
    );
    $sth->execute();
    while ( my ($id_domain, $name, $id_vm) = $sth->fetchrow ) {
        my $domain = Ravada::Domain->open(id => $id_domain, _force => 1);
        if ( !$domain || $domain->status eq 'down' || !$domain->is_active) {
            $domain->_post_shutdown(user => $USER_DAEMON);
            $domain->remove($USER_DAEMON);
            my $sth_del = $CONNECTOR->dbh->prepare("DELETE FROM domains WHERE id=?");
            $sth_del->execute($id_domain);
            $sth_del->finish;

            $sth_del = $CONNECTOR->dbh->prepare("DELETE FROM requests where id_domain=?");
            $sth_del->execute($id_domain);
            $sth_del->finish;
        }
    }
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
    my $domain = $self->search_domain_by_id($id_domain);

    die "USER $uid not authorized to set base vm"
        if !$user->is_admin;

    $domain->set_base_vm(
            id_vm => $id_vm
            ,user => $user
           ,value => $value
         ,request => $request
     );
}

sub _cmd_cleanup($self, $request) {
    $self->enforce_limits( request => $request);
    $self->_clean_volatile_machines( request => $request);
    $self->_clean_requests('cleanup', $request);
    $self->_wait_pids($request);
}

sub _wait_pids($self) {
    $self->{fork_manager}->reap_finished_children   if $self->{fork_manager};
    my $procs = `ps -eo "pid cmd"`;
    for my $line (split /\n/, $procs ) {
        my ($pid, $cmd) = $line =~ m{\s*(\d+)\s+.*(rvd_back).*defunct};
        next if !$pid;
        next if $cmd !~ /rvd_back/;
        my $kid = waitpid($pid , WNOHANG);
    }
}

sub _req_method {
    my $self = shift;
    my  $cmd = shift;

    my %methods = (

          clone => \&_cmd_clone
         ,start => \&_cmd_start
         ,pause => \&_cmd_pause
        ,create => \&_cmd_create
        ,remove => \&_cmd_remove
        ,resume => \&_cmd_resume
       ,cleanup => \&_cmd_cleanup
      ,download => \&_cmd_download
      ,shutdown => \&_cmd_shutdown
     ,hybernate => \&_cmd_hybernate
    ,set_driver => \&_cmd_set_driver
    ,domdisplay => \&_cmd_domdisplay
    ,screenshot => \&_cmd_screenshot
    ,copy_screenshot => \&_cmd_copy_screenshot
   ,cmd_cleanup => \&_cmd_cleanup
   ,remove_base => \&_cmd_remove_base
   ,set_base_vm => \&_cmd_set_base_vm
   ,refresh_vms => \&_cmd_refresh_vms
  ,ping_backend => \&_cmd_ping_backend
  ,prepare_base => \&_cmd_prepare_base
 ,rename_domain => \&_cmd_rename_domain
 ,open_iptables => \&_cmd_open_iptables
 ,list_vm_types => \&_cmd_list_vm_types
,enforce_limits => \&_cmd_enforce_limits
,force_shutdown => \&_cmd_force_shutdown
,refresh_storage => \&_cmd_refresh_storage
,refresh_vms => \&_cmd_refresh_vms
,domain_autostart=> \&_cmd_domain_autostart
,change_owner => \&_cmd_change_owner
,add_hardware => \&_cmd_add_hardware
,remove_hardware => \&_cmd_remove_hardware
,change_max_memory => \&_cmd_change_max_memory
,change_curr_memory => \&_cmd_change_curr_memory

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

    my $vms = $self->_create_vm();

    for my $vm (@$vms) {
        return $vm if ref($vm) eq $class && $vm->host eq $host;
    }
    return;
}

sub vm($self) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms "
    );
    $sth->execute();
    my @vms;
    while ( my ($id) = $sth->fetchrow()) {
        my $vm = Ravada::VM->open($id);
        eval { $vm->vm };
        if ( $@ ) {
            warn $@;
            next;
        }
        push @vms, ( $vm );
    };
    return [@vms] if @vms;
    return $self->_create_vms();

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

    my $vm_name = $args{vm} or die "ERROR: mandatory argument vm required";
    my $name = $args{name} or die "ERROR: mandatory argument domain name required";
    my $user_name = $args{user} or die "ERROR: mandatory argument user required";
    my $spinoff_disks = delete $args{spinoff_disks};
    $spinoff_disks = 1 if !defined $spinoff_disks;

    my $vm = $self->search_vm($vm_name) or die "ERROR: unknown VM '$vm_name'";
    my $user = Ravada::Auth::SQL->new(name => $user_name);
    die "ERROR: unknown user '$user_name'" if !$user || !$user->id;

    my $domain;
    eval { $domain = $self->search_domain($name) };
    die "ERROR: Domain '$name' already in RVD"  if $domain;

    return $vm->import_domain($name, $user, $spinoff_disks);
}

sub _cmd_enforce_limits($self, $request=undef) {
    _enforce_limits_active($self, $request);
}

sub _enforce_limits_active($self, $request) {

    if (my $id_recent = $request->done_recently(30)) {
        die "Command ".$request->command." run recently by $id_recent.\n";
    }
    my $timeout = ($request->defined_arg('timeout') or 10);

    my %domains;
    for my $domain ($self->list_domains( active => 1 )) {
        push @{$domains{$domain->id_owner}},$domain;
        $domain->client_status();
    }
    for my $id_user(keys %domains) {
        next if scalar @{$domains{$id_user}}<2;
        my $user = Ravada::Auth::SQL->search_by_id($id_user);
        next if $user->is_admin;

        my @domains_user = sort { $a->start_time <=> $b->start_time
                                    || $a->id <=> $b->id }
                        @{$domains{$id_user}};

#        my @list = map { $_->name => $_->start_time } @domains_user;
        my $last = pop @domains_user;
        DOMAIN: for my $domain (@domains_user) {
            #TODO check the domain shutdown has been already requested
            for my $request ($domain->list_requests) {
                next DOMAIN if $request->command =~ /shutdown/;
            }
            if ($domain->can_hybernate && !$domain->is_volatile) {
                $domain->hybernate($USER_DAEMON);
            } else {
                $domain->shutdown(timeout => $timeout, user => $USER_DAEMON );
            }
        }
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
        next if $domain_real->domain && $domain_real->is_active;
        $domain_real->_post_shutdown();
        $domain_real->remove($USER_DAEMON);

        $sth_remove->execute($domain->{id});
    }
}

sub DESTROY($self) {
    $self->{fork_manager}->reap_finished_children   if $self->{fork_manager}
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
