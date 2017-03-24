#!/usr/bin/perl

use warnings;
use strict;

use lib './lib';

use Getopt::Long;
use Proc::PID::File;

use Ravada;
use Ravada::Auth::SQL;
use Ravada::Auth::LDAP;

my $help;

my ($DEBUG, $ADD_USER );
my $FILE_CONFIG = "/etc/ravada.conf";
my $ADD_USER_LDAP;
my $IMPORT_DOMAIN;
my $CHANGE_PASSWORD;
my $NOFORK;

my $USAGE = "$0 "
        ." [--debug] [--file-config=$FILE_CONFIG] [--add-user=name] [--add-user-ldap=name]"
        ." [--change-password]"
        ." [-X] [start|stop|status]"
        ."\n"
        ." --add-user : adds a new db user\n"
        ." --add-user-ldap : adds a new LDAP user\n"
        ." --change-password : changes the password of an user\n"
        ." --import-domain : import a domain\n"
        ." -X : start in foreground\n"
    ;

GetOptions (       help => \$help
                 ,debug => \$DEBUG
              ,'no-fork'=> \$NOFORK
             ,'config=s'=> \$FILE_CONFIG
           ,'add-user=s'=> \$ADD_USER
      ,'change-password'=> \$CHANGE_PASSWORD
      ,'add-user-ldap=s'=> \$ADD_USER_LDAP
      ,'import-domain=s' => \$IMPORT_DOMAIN
) or exit;

#####################################################################
#
# check arguments
#
if ($help) {
    print $USAGE;
    exit;
}

die "Only root can do that\n" if $> && ( $ADD_USER || $ADD_USER_LDAP || $IMPORT_DOMAIN);

$Ravada::DEBUG=1    if $DEBUG;
$Ravada::CAN_FORK=0    if $NOFORK;
###################################################################

my $PID_LONGS;
###################################################################
#

sub do_start {
    warn "Starting rvd_back\n";
    my $old_error = ($@ or '');
    my $cnt_error = 0;

    clean_killed_requests();

    start_process_longs() if !$NOFORK;

    my $ravada = Ravada->new( config => $FILE_CONFIG );
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
    my $ravada = Ravada->new( config => $FILE_CONFIG );
    for (;;) {
        my $t0 = time;
        $ravada->process_long_requests();
        sleep 1 if time - $t0 <1;
    }
}

sub clean_killed_requests {
    my $ravada = Ravada->new( config => $FILE_CONFIG );
    $ravada->clean_killed_requests();
}

sub start {
    {
        my $ravada = Ravada->new( config => $FILE_CONFIG );
        $Ravada::CONNECTOR->dbh;
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

    my $user = Ravada::Auth::SQL->new(name => $login);
    die "ERROR: Unknown user '$login'\n" if !$user->id;

    print "password : ";
    my $password = <STDIN>;
    chomp $password;
    $user->change_password($password);
}

sub import_domain {
    my $name = shift;
    print "Virtual Manager: KVM\n";
    print "User name : ";
    my $user = <STDIN>;
    chomp $user;
    my $ravada = Ravada->new( config => $FILE_CONFIG );
    $ravada->import_domain(name => $name, vm => 'KVM', user => $user);
}

sub DESTROY {
    return if !$PID_LONGS;
    warn "Killing pid: $PID_LONGS";

    my $cnt = kill 15 , $PID_LONGS;
    return if !$cnt;

    kill 9 , $PID_LONGS;
    
}

#################################################################
if ($ADD_USER) {
    add_user($ADD_USER);
    exit;
} elsif ($ADD_USER_LDAP) {
    add_user($ADD_USER_LDAP);
    exit;
} elsif ($CHANGE_PASSWORD) {
    change_password();
    exit;
} elsif ($IMPORT_DOMAIN) {
    import_domain($IMPORT_DOMAIN);
    exit;
}
die "Already started" if Proc::PID::File->running( name => 'rvd_back');
start();
