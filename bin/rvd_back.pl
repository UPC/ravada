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
my $CHANGE_PASSWORD;
my $NOFORK;
my $MAKE_ADMIN_USER;
my $REMOVE_ADMIN_USER;
my $START = 1;
my $TEST_LDAP;

my $URL_ISOS;


my $USAGE = "$0 "
        ." [--debug] [--config=$FILE_CONFIG_DEFAULT] [--add-user=name] [--add-user-ldap=name]"
        ." [--change-password] [--make-admin=username]"
        ." [--test-ldap] "
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
    ;

$START = 0 if scalar @ARGV && $ARGV[0] ne '&';

GetOptions (       help => \$help
                 ,debug => \$DEBUG
              ,'no-fork'=> \$NOFORK
             ,'config=s'=> \$FILE_CONFIG
            ,'test-ldap'=> \$TEST_LDAP
           ,'add-user=s'=> \$ADD_USER
           ,'url-isos=s'=> \$URL_ISOS
        ,'make-admin=s' => \$MAKE_ADMIN_USER
      ,'remove-admin=s' => \$REMOVE_ADMIN_USER
      ,'change-password'=> \$CHANGE_PASSWORD
      ,'add-user-ldap=s'=> \$ADD_USER_LDAP
      ,'import-domain=s' => \$IMPORT_DOMAIN
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
                || ($domain_name && $domain->name eq $domain_name)) {
            $found++;
            if (!$domain->is_active) {
                warn "WARNING: Virtual machine ".$domain->name
                    ." is already down.\n";
                next;
            }
            if ($domain->can_hibernate) {
                $domain->hibernate();
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
        if !$all && !$found;
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
            eval { $domain->start(user => $Ravada::USER_DAEMON) };
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
    for my $domain ($rvd_back->list_domains) {
        if ((defined $domain_name && $domain->name eq $domain_name)
            || ($hibernated && $domain->is_hibernated)
            || $all ){
            $found++;
            if (!$domain->is_active && !$domain->is_hibernated) {
                warn "WARNING: Virtual machine ".$domain->name
                    ." is already down.\n"
                        if !$all;
                next;
            }
            if ($domain->is_hibernated) {
                $domain->start(user => $Ravada::USER_DAEMON);
            }
            $domain->shutdown(user => $Ravada::USER_DAEMON, timeout => 60);
            print "Shutting down ".$domain->name.".\n";
            $down++;
        }
    }
    warn "ERROR: Domain $domain_name not found.\n"
        if $domain_name && !$found;
    print "$down domains shut down.\n";
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

sub DESTROY {
    return if !$PID_LONGS;
    warn "Killing pid: $PID_LONGS";

    my $cnt = kill 15 , $PID_LONGS;
    return if !$cnt;

    kill 9 , $PID_LONGS;
    
}

#################################################################
add_user($ADD_USER)                 if $ADD_USER;
add_user_ldap($ADD_USER_LDAP)       if $ADD_USER_LDAP;
change_password()                   if $CHANGE_PASSWORD;
import_domain($IMPORT_DOMAIN)       if $IMPORT_DOMAIN;
make_admin($MAKE_ADMIN_USER)        if $MAKE_ADMIN_USER;
remove_admin($REMOVE_ADMIN_USER)    if $REMOVE_ADMIN_USER;
set_url_isos($URL_ISOS)             if $URL_ISOS;
test_ldap                           if $TEST_LDAP;

if ($START) {
    die "Already started" if Proc::PID::File->running( name => 'rvd_back');
    start();
}
