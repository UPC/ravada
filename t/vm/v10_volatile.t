#!/usr/bin/perl
# test volatile anonymous domains kiosk mode

use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Network');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
init($test->connector);

my $IP = "10.0.0.1";
my $NETWORK = $IP;
$NETWORK =~ s{(.*\.).*}{$1.0/24};

################################################################################

sub create_network {

    my $sth = $test->dbh->prepare(
        "INSERT INTO networks (name, address) "
        ." VALUES (?,?)"
    );
    $sth->execute('foo',$NETWORK);
    $sth->finish;
}

sub delete_network {
    my $sth = $test->dbh->prepare(
        "DELETE FROM networks WHERE address=?"
    );
    $sth->execute($NETWORK);
    $sth->finish;
}

sub id_network {
    my $address = shift;

    my $sth = $test->dbh->prepare(
        "SELECT id FROM networks WHERE address=?"
    );
    $sth->execute($address);
    my ($id) = $sth->fetchrow;

    return $id;
}

sub allow_anonymous {
    my $base = shift;

    my $id_network = id_network($NETWORK);
    my $sth = $test->dbh->prepare(
        "INSERT INTO domains_network "
        ." (id_domain, id_network, anonymous )"
        ." VALUES (?,?,?) "
    );
    $sth->execute($base->id, $id_network, 1);
    $sth->finish;
}

sub test_volatile {
}
################################################################################

clean();


for my $vm_name ('Void', 'KVM') {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing timeout for $vm_name");

        create_network();

        my $base= create_domain($vm_name);
        $base->prepare_base(user_admin());
        allow_anonymous($base);

        test_volatile($vm_name);

        delete_network();
    }

}

clean();

