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

my $USAGE = "$0 "
        ." [--debug] [--file-config=$FILE_CONFIG] [--add-user=name] [--add-user-ldap=name]"
        ." [-X] [start|stop|status]"
        ."\n"
        ." --add-user : adds a new db user\n"
        ." --add-user-ldap : adds a new LDAP user\n"
        ." -X : start in foreground\n"
    ;

GetOptions (       help => \$help
                 ,debug => \$DEBUG
             ,'config=s'=> \$FILE_CONFIG
           ,'add-user=s'=> \$ADD_USER
      ,'add-user-ldap=s'=> \$ADD_USER_LDAP
);

#####################################################################
#
# check arguments
#
if ($help) {
    print $USAGE;
    exit;
}

$Ravada::DEBUG=1    if $DEBUG;
###################################################################

our ($FH_DOWNLOAD, $DOWNLOAD_TOTAL);

my $RAVADA = Ravada->new( config => $FILE_CONFIG );
my $REMOTE_VIEWER;
###################################################################
#

sub start {
    warn "Starting daemon mode\n";
    for (;;) {
        $RAVADA->process_requests();
        sleep 1;
    }
}

sub add_user {
    my $login = shift;

    print "password : ";
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

#################################################################
if ($ADD_USER) {
    add_user($ADD_USER);
    exit;
} elsif ($ADD_USER_LDAP) {
    add_user($ADD_USER_LDAP);
    exit;
}
die "Already started" if Proc::PID::File->running();
start();
