#!/usr/bin/perl

use warnings;
use strict;

use lib './lib';

use Data::Dumper;
use Getopt::Long;
use Proc::PID::File;

use Ravada;
use Ravada::Auth::SQL;
use Ravada::Auth::LDAP;

my $help;

my ($DEBUG, $ADD_USER );

my $FILE_CONFIG_DEFAULT = "/etc/ravada.conf";
my $FILE_CONFIG;

my $ADD_USER_LDAP;
my $IMPORT_DOMAIN;
my $IMPORT_VBOX;
my $CHANGE_PASSWORD;
my $NOFORK;
my $MAKE_ADMIN_USER;
my $REMOVE_ADMIN_USER;
my $START = 1;

my $URL_ISOS;


my $USAGE = "$0 "
        ." [--debug] [--config=$FILE_CONFIG_DEFAULT] [--add-user=name] [--add-user-ldap=name]"
        ." [--change-password] [--make-admin=username] [--import-vbox=image_file.vdi]"
        ." [-X] [start|stop|status]"
        ."\n"
        ." --add-user : adds a new db user\n"
        ." --add-user-ldap : adds a new LDAP user\n"
        ." --change-password : changes the password of an user\n"
        ." --import-domain : import a domain\n"
        ." --make-admin : make user admin\n"
        ." --config : config file, defaults to $FILE_CONFIG_DEFAULT"
        ." -X : start in foreground\n"
        ." --url-isos=(URL|default)\n"
        ." --import-vbox : import a VirtualBox image\n"
    ;

$START = 0 if scalar @ARGV && $ARGV[0] ne '&';

GetOptions (       help => \$help
                 ,debug => \$DEBUG
              ,'no-fork'=> \$NOFORK
             ,'config=s'=> \$FILE_CONFIG
           ,'add-user=s'=> \$ADD_USER
           ,'url-isos=s'=> \$URL_ISOS
        ,'make-admin=s' => \$MAKE_ADMIN_USER
      ,'remove-admin=s' => \$REMOVE_ADMIN_USER
      ,'change-password'=> \$CHANGE_PASSWORD
      ,'add-user-ldap=s'=> \$ADD_USER_LDAP
      ,'import-domain=s' => \$IMPORT_DOMAIN
      ,'import-vbox=s' => \$IMPORT_VBOX
) or exit;

$START = 1 if $DEBUG || $FILE_CONFIG || $NOFORK;

#####################################################################
#
# check arguments
#
if ($help) {
    print $USAGE;
    exit;
}

die "Only root can do that\n" if $> && ( $ADD_USER || $ADD_USER_LDAP || $IMPORT_DOMAIN);
die "ERROR: Missing file config $FILE_CONFIG\n"
    if $FILE_CONFIG && ! -e $FILE_CONFIG;

my %CONFIG;
%CONFIG = ( config => $FILE_CONFIG )    if $FILE_CONFIG;

$Ravada::DEBUG=1    if $DEBUG;
$Ravada::CAN_FORK=0    if $NOFORK;
###################################################################

my $PID_LONGS;
###################################################################
#

sub do_start {
    warn "Starting rvd_back v".Ravada::version."\n";
    my $old_error = ($@ or '');
    my $cnt_error = 0;

    clean_killed_requests();

    start_process_longs() if !$NOFORK;

    my $ravada = Ravada->new( %CONFIG );
    for (;;) {
        my $t0 = time;
        $ravada->process_requests();
        $ravada->process_long_requests(0,$NOFORK)   if $NOFORK;
        sleep 1 if time - $t0 <1;
    }
}

sub start_process_longs {
    my $pid = fork();
    die "I can't fork" if !defined $pid;
    if ( $pid ) {
        $PID_LONGS = $pid;
        return;
    }
    
    warn "Processing long requests in pid $$\n" if $DEBUG;
    my $ravada = Ravada->new( %CONFIG );
    for (;;) {
        my $t0 = time;
        $ravada->process_long_requests();
        sleep 1 if time - $t0 <1;
    }
}

sub clean_killed_requests {
    my $ravada = Ravada->new( %CONFIG );
    $ravada->clean_killed_requests();
}

sub start {
    {
        my $ravada = Ravada->new( %CONFIG );
        $Ravada::CONNECTOR->dbh;
        for my $vm (@{$ravada->vm}) {
            $vm->id;
            $vm->vm;
        }
    }
    for (;;) {
        my $pid = fork();
        die "I can't fork $!" if !defined $pid;
        if ($pid == 0 ) {
            do_start();
            exit;
        }
        warn "Waiting for pid $pid\n";
        waitpid($pid,0);
    }
}

sub add_user {
    my $login = shift;

    my $ravada = Ravada->new( %CONFIG);

    print "$login password: ";
    my $password = <STDIN>;
    chomp $password;

    print "is admin ? : [y/n] ";
    my $is_admin_q = <STDIN>;
    my $is_admin = 0;

    $is_admin = 1 if $is_admin_q =~ /y/i;

    Ravada::Auth::SQL::add_user(      name => $login
                                , password => $password
                                , is_admin => $is_admin);
}

sub add_user_ldap {
    my $login = shift;

    print "password : ";
    my $password = <STDIN>;
    chomp $password;

    Ravada::Auth::LDAP::add_user($login, $password);
}

sub change_password {
    print "User login name : ";
    my $login = <STDIN>;
    chomp $login;
    return if !$login;

    my $ravada = Ravada->new( %CONFIG );
    
    my $user = Ravada::Auth::SQL->new(name => $login);
    die "ERROR: Unknown user '$login'\n" if !$user->id;

    print "password : ";
    my $password = <STDIN>;
    chomp $password;
    $user->change_password($password);
}

sub make_admin {
    my $login = shift;

    my $ravada = Ravada->new( %CONFIG);
    my $user = Ravada::Auth::SQL->new(name => $login);
    die "ERROR: Unknown user '$login'\n" if !$user->id;

    $Ravada::USER_DAEMON->make_admin($user->id);
    print "USER $login granted admin permissions\n";
}

sub remove_admin {
    my $login = shift;

    my $ravada = Ravada->new( %CONFIG);
    my $user = Ravada::Auth::SQL->new(name => $login);
    die "ERROR: Unknown user '$login'\n" if !$user->id;

    $Ravada::USER_DAEMON->remove_admin($user->id);
    print "USER $login removed admin permissions, granted normal user permissions.\n";
}


sub import_domain {
    my $name = shift;
    print "Virtual Manager: KVM\n";
    print "User name that will own the domain in Ravada : ";
    my $user = <STDIN>;
    chomp $user;
    my $ravada = Ravada->new( %CONFIG );
    $ravada->import_domain(name => $name, vm => 'KVM', user => $user);
}

sub import_vbox {
    my $file_vdi = shift;
    my $ravada = Ravada->new(%CONFIG);
    my $vm = $ravada->open_vm('kvm');

    if ($file_vdi =~ /\.vdi$/i) {
        print "Import VirtualBox image from vdi file\n";
        print "Name for the new domain : ";
        my $name = <STDIN>;
        chomp $name;

        my $path = $vm->dir_img."/".$name.".qcow2";

        if ( $name && -e $file_vdi ) {
            my @cmd = ("qemu-img convert -p -f vdi -O qcow2 $file_vdi $path");
            system(@cmd);
            print "Save image in default storage pool: $path \n";

            #new machine xml change source file
            my $id_iso;
            my $id_owner = 2;
            my $id_base = "NULL";
            my $domain = $vm->create_domain(    name => $name
                                            , id_iso => $id_iso
                                            , file_iso => '<NONE>'
                                            , id_owner => $id_owner
                                            , is_base => 0
                                            , id_base => $id_base);
            #remove cdrom
            $domain->remove_disks();
            #add new path
            $domain->add_volume( path => $path );
            exit;
        }
        print "Warning: Missing args or no such file! \n";
        exit
    }
    print "Warning: $file_vdi is not a vdi file \n";
    print "Check if the path has spaces, if so insert it in quotes \n";
}

sub set_url_isos {
    my $url = shift;
    my $rvd_back = Ravada->new(%CONFIG);
    if ($url =~ /^default$/i) {
        my $sth = $rvd_back->connector->dbh->prepare("DROP TABLE iso_images");
        $sth->execute;
        $sth->finish;
        my $rvd_back2 = Ravada->new(%CONFIG);
    } else {
        $rvd_back->_set_url_isos($url);
        print "ISO_IMAGES table URLs set from $url\n";
    }
}

sub DESTROY {
    return if !$PID_LONGS;
    warn "Killing pid: $PID_LONGS";

    my $cnt = kill 15 , $PID_LONGS;
    return if !$cnt;

    kill 9 , $PID_LONGS;
    
}

#################################################################
add_user($ADD_USER)                 if $ADD_USER;
add_user($ADD_USER_LDAP)            if $ADD_USER_LDAP;
change_password()                   if $CHANGE_PASSWORD;
import_domain($IMPORT_DOMAIN)       if $IMPORT_DOMAIN;
import_vbox($IMPORT_VBOX)           if $IMPORT_VBOX;
make_admin($MAKE_ADMIN_USER)        if $MAKE_ADMIN_USER;
remove_admin($REMOVE_ADMIN_USER)    if $REMOVE_ADMIN_USER;
set_url_isos($URL_ISOS)             if $URL_ISOS;

if ($START) {
    die "Already started" if Proc::PID::File->running( name => 'rvd_back');
    start();
}
