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

my $rvd_back = rvd_back( $test->connector , 't/etc/ravada.conf');
my $RVD_FRONT = rvd_front( $test->connector , 't/etc/ravada.conf');

my $vm = $rvd_back->search_vm('Void');
my $USER = create_user('foo','bar');

########################################################################3

sub test_allow_all {
    my $domain = shift;

    my $ip = '192.168.1.2/32';
    my $net = Ravada::Network->new(address => $ip);
    ok(!$net->allowed($domain->id),"Expecting not allowed from unknown network");

    my $sth = $test->dbh->prepare("INSERT INTO networks (name,address,all_domains) "
        ." VALUES (?,?,?) ");

    $sth->execute('foo', '192.168.1.0/24', 1);
    $sth->finish;

    ok(!$net->allowed_anonymous($domain->id),"Expecting denied anonymous from known network");
    ok($net->allowed($domain->id),"Expecting allowed from known network");

    my $net2 = Ravada::Network->new(address => '192.168.1.22/32');
    ok($net2->allowed($domain->id),"Expecting allowed from known network");
    ok(!$net2->allowed_anonymous($domain->id),"Expecting denied anonymous from known network");
    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

}

sub test_allow_domain {
    my $domain = shift;

    my $ip = '10.1.1.1/32';
    my $net = Ravada::Network->new(address => $ip);
    ok(!$net->allowed($domain->id),"Expecting not allowed from unknown network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }


    my $sth = $test->dbh->prepare("INSERT INTO networks "
        ." (id, name,address,all_domains, no_domains) "
        ." VALUES (?,?,?,?,?) ");

    my $id_network = 100;
    $sth->execute($id_network,'foo', '10.1.1.0/24', 0,0);
    $sth->finish;

    $sth = $test->dbh->prepare("INSERT INTO domains_network "
        ." (id_domain, id_network, allowed)"
        ." VALUES (?,?,?) ");

    $sth->execute($domain->id, $id_network, 1);
    $sth->finish;

    ok($net->allowed($domain->id),"Expecting allowed from known network");
    ok(!$net->allowed_anonymous($domain->id)
        ,"Expecting not allowed anonymous from known network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

    $sth = $test->dbh->prepare("UPDATE domains_network "
        ." SET allowed=0 "
        ." WHERE id_domain=? AND id_network=?");

    $sth->execute($domain->id, $id_network);

    ok(!$net->allowed($domain->id),"Expecting not allowed from known network");
    ok(!$net->allowed_anonymous($domain->id)
        ,"Expecting not allowed anonymous from known network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

    $sth = $test->dbh->prepare("UPDATE domains_network "
        ." SET allowed=0, anonymous=1 "
        ." WHERE id_domain=? AND id_network=?");
    $sth->execute($domain->id, $id_network);

    ok(!$net->allowed($domain->id),"Expecting not allowed from known network");

    ok(!$net->allowed_anonymous($domain->id)
        ,"Expecting not allowed anonymous from known network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

    $sth = $test->dbh->prepare("UPDATE domains_network "
        ." SET allowed=1, anonymous=1 "
        ." WHERE id_domain=? AND id_network=?");
    $sth->execute($domain->id, $id_network);

    ok($net->allowed($domain->id),"Expecting allowed from known network");
    ok($net->allowed_anonymous($domain->id)
        ,"Expecting allowed anonymous from known network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok($n_found == 1, "Expecting 1 anon bases, got '$n_found'");
    }


}


sub test_deny_all {
    my $domain = shift;

    my $ip = '10.0.0.2/32';

    my $net = Ravada::Network->new(address => $ip);
    ok(!$net->allowed($domain->id),"Expecting not allowed from unknown network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

    my $sth = $test->dbh->prepare("INSERT INTO networks (name,address,no_domains) "
        ." VALUES (?,?,?) ");

    $sth->execute('bar', '10.0.0.0/16', 1);
    $sth->finish;

    ok(!$net->allowed($domain->id),"Expecting denied from known network");
    ok(!$net->allowed_anonymous($domain->id),"Expecting denied anonymous from known network");

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

}

########################################################################3
#
#
remove_old_domains();
remove_old_disks();

my $domain_name = new_domain_name();
my $domain = $vm->create_domain( name => $domain_name
            , id_iso => 1 , id_owner => $USER->id);

$domain->prepare_base($USER);

my $net = Ravada::Network->new(address => '127.0.0.1/32');
ok($net->allowed($domain->id));

my $net2 = Ravada::Network->new(address => '10.0.0.0/32');
ok(!$net2->allowed($domain->id), "Address unknown should not be allowed to anything");

test_allow_all($domain);
test_deny_all($domain);

test_allow_domain($domain);

remove_old_domains();
remove_old_disks();

done_testing();
