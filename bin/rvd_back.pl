#!/usr/bin/perl

use warnings;
use strict;

use lib './lib';

use Data::Dumper;
use Getopt::Long;
use POSIX ":sys_wait_h";
use Proc::PID::File;

use Ravada;
use Ravada::Auth::SQL;
use Ravada::Auth::LDAP;
use Ravada::Utils;

$|=1;

my $help;

my ($DEBUG, $ADD_USER );

my $VERBOSE = $ENV{TERM};

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
my $TEST_LDAP;

my $URL_ISOS;
my $ALL;
my $HIBERNATED;
my $DISCONNECTED;

my $LIST;

my $HIBERNATE_DOMAIN;
my $START_DOMAIN;
my $SHUTDOWN_DOMAIN;
my $REBASE;

my $IMPORT_DOMAIN_OWNER;

my $ADD_LOCALE_REPOSITORY;

my $USAGE = "$0 "
        ." [--debug] [--config=$FILE_CONFIG_DEFAULT] [--add-user=name] [--add-user-ldap=name]"
        ." [--change-password] [--make-admin=username] [--import-vbox=image_file.vdi]"
        ." [--test-ldap] "
        ." [-X] [start|stop|status]"
        ." [--rebase MACHINE]"
        ."\n"
        ." --add-user : adds a new db user\n"
        ." --add-user-ldap : adds a new LDAP user\n"
        ." --change-password : changes the password of an user\n"
        ." --import-domain : import a domain\n"
        ." --import-domain-owner : owner of the domain to import\n"
        ." --make-admin : make user admin\n"
        ." --config : config file, defaults to $FILE_CONFIG_DEFAULT"
        ." --no-fork : start in foreground\n"
        ." --url-isos=(URL|default)\n"
        ." --import-vbox : import a VirtualBox image\n"
        .' --add-locale-repository LOCALE : adds ISO repositories for this locale'
        ."\n"
        ."Operations on Virtual Machines:\n"
        ." --list\n"
        ." --start\n"
        ." --hibernate machine\n"
        ." --shutdown machine\n"
        ."\n"
        ."Operations modifiers:\n"
        ." --all : execute on all virtual machines\n"
        ."          For hibernate, it is executed on all the actives\n"
        ." --hibernated: execute on hibernated machines\n"
        ." --disconnected: execute on disconnected machines\n"
        ."\n"
    ;

$START = 0 if scalar @ARGV && $ARGV[0] ne '&';

GetOptions (       help => \$help
                   ,all => \$ALL
                  ,list => \$LIST
                 ,debug => \$DEBUG
                ,verbose => \$VERBOSE
                ,rebase => \$REBASE
              ,'no-fork'=> \$NOFORK
             ,'start=s' => \$START_DOMAIN
             ,'config=s'=> \$FILE_CONFIG
           ,'hibernated'=> \$HIBERNATED
            ,'test-ldap'=> \$TEST_LDAP
           ,'add-user=s'=> \$ADD_USER
           ,'url-isos=s'=> \$URL_ISOS
           ,'shutdown:s'=> \$SHUTDOWN_DOMAIN
          ,'hibernate:s'=> \$HIBERNATE_DOMAIN
         ,'disconnected'=> \$DISCONNECTED
        ,'make-admin=s' => \$MAKE_ADMIN_USER
      ,'remove-admin=s' => \$REMOVE_ADMIN_USER
      ,'change-password'=> \$CHANGE_PASSWORD
      ,'add-user-ldap=s'=> \$ADD_USER_LDAP
      ,'import-domain=s' => \$IMPORT_DOMAIN
      ,'import-vbox=s' => \$IMPORT_VBOX
,'import-domain-owner=s' => \$IMPORT_DOMAIN_OWNER

    ,'add-locale-repository=s' => \$ADD_LOCALE_REPOSITORY
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

die "ERROR: Shutdown requires a domain name, or --all , --hibernated , --disconnected\n"
    if defined $SHUTDOWN_DOMAIN && !$SHUTDOWN_DOMAIN && !$ALL && !$HIBERNATED
                                && !$DISCONNECTED;

die "ERROR: Hibernate requires a domain name, or --all , --disconnected\n"
    if defined $HIBERNATE_DOMAIN && !$HIBERNATE_DOMAIN && !$ALL && !$DISCONNECTED;

die "ERROR: Missing the machine name or id\n$USAGE"
    if $REBASE && !@ARGV;

my %CONFIG;
%CONFIG = ( config => $FILE_CONFIG )    if $FILE_CONFIG;

$Ravada::DEBUG=1    if $DEBUG;
$Ravada::VERBOSE=1      if $VERBOSE;
$Ravada::CAN_FORK=0    if $NOFORK;

###################################################################

###################################################################
#

sub do_start {
    warn "Starting rvd_back v".Ravada::version."\n";
    my $old_error = ($@ or '');
    my $cnt_error = 0;


    my $t_refresh = 0;

    my $ravada = Ravada->new( %CONFIG );
    #    Ravada::Request->enforce_limits();
    #Ravada::Request->refresh_vms();
    for (;;) {
        my $t0 = time;
        $ravada->process_priority_requests();
        $ravada->process_long_requests();
        $ravada->process_requests();

        if ( time - $t_refresh > 60 ) {
            Ravada::Request->cleanup();
            Ravada::Request->refresh_vms()      if rand(5)<3;
            Ravada::Request->enforce_limits()   if rand(5)<2;
            $t_refresh = time;
        }
        sleep 1 if time - $t0 <1;
    }

}

sub clean_old_requests {
    my $ravada = Ravada->new( %CONFIG );
    $ravada->clean_old_requests();
}

sub start {
    {
        my $ravada = Ravada->new( %CONFIG );
        $Ravada::CONNECTOR->dbh;
        $ravada->_install();
        for my $vm (@{$ravada->vm}) {
            $vm->id;
        }
        $ravada->_wait_pids();
    }
    clean_old_requests();
    for (;;) {
        eval { do_start() };
        warn $@ if $@;
    }
}

sub add_user {
    my $login = shift;

    my $ravada = Ravada->new( %CONFIG);
    $ravada->_install();

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

    my $ravada = Ravada->new( %CONFIG);

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

    Ravada::Utils::user_daemon()->make_admin($user->id);
    print "USER $login granted admin permissions\n";
}

sub remove_admin {
    my $login = shift;

    my $ravada = Ravada->new( %CONFIG);
    my $user = Ravada::Auth::SQL->new(name => $login);
    die "ERROR: Unknown user '$login'\n" if !$user->id;

    Ravada::Utils::user_daemon()->remove_admin($user->id);
    print "USER $login removed admin permissions, granted normal user permissions.\n";
}


sub import_domain {
    my $name = shift;
    print "Virtual Manager: KVM\n";
    my $user = $IMPORT_DOMAIN_OWNER;
    if (!$user) {
        print "User name that will own the domain in Ravada : ";
        $user = <STDIN>;
        chomp $user;
    }
    my $ravada = Ravada->new( %CONFIG );
    $ravada->import_domain(name => $name, vm => 'KVM', user => $user);
}

sub import_vbox {
    my $file_vdi = shift;
    my $rvd = Ravada->new(%CONFIG);
    my $kvm = $rvd->search_vm('KVM');
    my $default_storage_pool = $kvm->storage_pool();
    if ($file_vdi =~ /\.vdi$/i) {
        print "Import VirtualBox image from vdi file\n";
        print "Name for the new domain : ";
        my $name = <STDIN>;
        chomp $name;
        print "Change default storage pool in /var/lib/libvirt/images/ [y/N]:";
        my $default_pool_q = <STDIN>;
        my $storage_pool = "/var/lib/libvirt/images";

        if ( $default_pool_q =~ /y/i ) {
            print "Insert storage pool path : ";
            $storage_pool = <STDIN>;
            chomp $storage_pool;
        }
        print "STORAGE POOL IS $storage_pool \n";
        print "DEFAULT STORAGE POOL IS $default_storage_pool \n";

        if ( $name && $file_vdi ) {
            my @cmd = ("qemu-img convert -p -f vdi -O qcow2 $file_vdi $storage_pool/$name.qcow2");
            system(@cmd);
        }
        print "Warning: Missing args! \n";
        #new machine xml change source file
        #remove swap
        #remove cdrom

        exit;
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

sub list {
    my $all = shift;
    my $rvd_back = Ravada->new(%CONFIG);

    my $found = 0;
    for my $domain ($rvd_back->list_domains) {
        next if !$all && !$domain->is_active && !$domain->is_hibernated;
        $found++;
        print $domain->name."\t";
        if ($domain->is_active) {
            print "active";
            my $status = $domain->client_status;
            if ( $domain->remote_ip ) {
                $status .= " , "    if $status;
                $status .= $domain->remote_ip;
            }
            print " ( $status ) " if $status;
        } elsif ($domain->is_hibernated) {
            print "hibernated";
        } else {
            print "down";
        }
        print "\n";
    }
    print "$found machines found.\n";
}

sub hibernate {
    my $domain_name = shift;
    my $all = shift;

    my $rvd_back = Ravada->new(%CONFIG);

    my $down = 0;
    my $found = 0;
    for my $domain ($rvd_back->list_domains) {
        if ( ($all && $domain->is_active)
                || ($domain_name && $domain->name eq $domain_name)
                || ($DISCONNECTED && $domain->client_status
                        && $domain->client_status eq 'disconnected')
           ) {
            $found++;
            if (!$domain->is_active) {
                warn "WARNING: Virtual machine ".$domain->name
                    ." is already down.\n";
                next;
            }
            if ( $DISCONNECTED && $domain->client_status
                    && $domain->client_status eq 'disconnected') {
                next if _verify_connection($domain);
            }
            if ($domain->can_hibernate) {
                $domain->hibernate( Ravada::Utils::user_daemon() );
                $down++;
            } else {
                warn "WARNING: Virtual machine ".$domain->name
                    ." can't hibernate because it is not supported in ".$domain->type
                    ." domains."
                    ."\n";
            }
        }
    }
    print "$down machines hibernated.\n";
    warn "ERROR: Domain $domain_name not found.\n"
        if !$domain_name && !$found;
}

sub start_domain {
    my $domain_name = shift;

    my $rvd_back = Ravada->new(%CONFIG);

    my $up= 0;
    my $found = 0;
    for my $domain ($rvd_back->list_domains) {
        if ($domain->name eq $domain_name) {
            $found++;
            if ($domain->is_active) {
                warn "WARNING: Virtual machine ".$domain->name
                    ." is already up.\n";
                next;
            }
            eval { $domain->start(user => Ravada::Utils::user_daemon() ) };
            if ($@) {
                warn $@;
                next;
            }
            print $domain->name." started.\n"
                if $domain->is_active;
        }
    }
    warn "ERROR: Domain $domain_name not found.\n"
        if !$found;
}

sub shutdown_domain {
    my $domain_name = shift;
    my ($all,$hibernated) = @_;

    my $rvd_back = Ravada->new(%CONFIG);

    my $down = 0;
    my $found = 0;
    DOMAIN:
    for my $domain_data ($rvd_back->list_domains_data) {
        my $domain = Ravada::Front::Domain->open($domain_data->{id});
        if ((defined $domain_name && $domain->name eq $domain_name)
            || ($hibernated && $domain->is_hibernated)
            || ($DISCONNECTED
                    && ( $domain->client_status && $domain->client_status eq 'disconnected' ))
            || $all ){
            $found++;
            if (!$domain->is_active && !$domain->is_hibernated) {
                warn "WARNING: Virtual machine ".$domain->name
                    ." is already down.\n"
                        if !$all;
                next;
            }
            if ($domain->is_hibernated) {
                print "Starting ".$domain->name."\n";
                eval { $domain->start(user => Ravada::Utils::user_daemon()) };
                warn $@ if $@;
                sleep 5 if !$@;

            }
            if ($DISCONNECTED && $domain->client_status
                    && $domain->client_status eq 'disconnected') {

                next DOMAIN if _verify_connection($domain);
            }
            print "Shutting down ".$domain->name.".\n";
            Ravada::Request->shutdown_domain(uid => Ravada::Utils::user_daemon()->id
                ,id_domain => $domain->id
                , timeout => 300
            );
            $down++;
            warn $@ if $@;
        }
    }
    warn "ERROR: Domain $domain_name not found.\n"
        if $domain_name && !$found;
    print "$down domains shut down.\n";
}

sub _verify_connection {
    my $domain = shift;
    print "Verifying connection for ".$domain->name
                        ." ".($domain->remote_ip or '')." "
        if $VERBOSE;
    for ( 1 .. 25 ) {
        if ( $domain->client_status(1)
                            && $domain->client_status(1) ne 'disconnected' ) {
            print "\n\t".$domain->client_status." ".$domain->remote_ip
                            ." Shutdown dismissed.\n";
            return 1;
        }
        print "." if $VERBOSE && !($_ % 5);
        sleep 1;
     }
     print "\n" if $VERBOSE;
    return 0;
}

sub test_ldap {
    my $rvd_back = Ravada->new(%CONFIG);
    eval { Ravada::Auth::LDAP::_init_ldap_admin() };
    die "No LDAP connection, error: $@\n" if $@;
    print "Connection to LDAP ok\n";
    print "login: ";
    my $name=<STDIN>;
    chomp $name;
    print "password: ";
    my $password = <STDIN>;
    chomp $password;
    my $ok= Ravada::Auth::login( $name, $password);
    if ($ok) {
        print "LOGIN OK $ok->{_auth}\n";
    } else {
        print "LOGIN FAILED\n";
    }
    exit;
}

sub add_locale_repository {
    my $locale = shift;
    for my $lang ( split /,/, $locale ) {
        print "Adding locales for $lang.\n";
        my $found = Ravada::Repository::ISO::insert_iso_locale($lang, 'verbose');
        print "$found found.\n";
    }
}

sub rebase {
    my ($domain_name) = $ARGV[0];
    my $rvd_back = Ravada->new(%CONFIG);
    my $domain;
    if ($domain_name =~ /^\d+$/) {
        $domain = Ravada::Domain->open($domain_name);
    } else {
        $domain = $rvd_back->search_domain($domain_name);
    }
    die "Error: Unknown domain $domain_name\n"      if !$domain;
    die "Error: ".$domain->name." is not a clone\n" if !$domain->id_base;

    my $base = Ravada::Domain->open($domain->id_base);
    $base->rebase(Ravada::Utils::user_daemon, $domain);
}

sub DESTROY {
}

#################################################################

{

my $rvd_back = Ravada->new(%CONFIG);

add_user($ADD_USER)                 if $ADD_USER;
add_user_ldap($ADD_USER_LDAP)       if $ADD_USER_LDAP;
change_password()                   if $CHANGE_PASSWORD;
import_domain($IMPORT_DOMAIN)       if $IMPORT_DOMAIN;
import_vbox($IMPORT_VBOX)           if $IMPORT_VBOX;
make_admin($MAKE_ADMIN_USER)        if $MAKE_ADMIN_USER;
remove_admin($REMOVE_ADMIN_USER)    if $REMOVE_ADMIN_USER;
set_url_isos($URL_ISOS)             if $URL_ISOS;
test_ldap                           if $TEST_LDAP;
rebase()                            if $REBASE;

list($ALL)                          if $LIST;
hibernate($HIBERNATE_DOMAIN , $ALL) if defined $HIBERNATE_DOMAIN;
start_domain($START_DOMAIN)         if $START_DOMAIN;

shutdown_domain($SHUTDOWN_DOMAIN, $ALL, $HIBERNATED)
                                    if defined $SHUTDOWN_DOMAIN;

add_locale_repository($ADD_LOCALE_REPOSITORY) if $ADD_LOCALE_REPOSITORY;
}


if ($START) {
    die "Already started" if Proc::PID::File->running( name => 'rvd_back');
    start();
}
