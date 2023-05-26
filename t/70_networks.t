use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
use_ok('Ravada::Network');

use lib 't/lib';
use Test::Ravada;

my $rvd_back = rvd_back('t/etc/ravada.conf');
my $RVD_FRONT = rvd_front();

my $vm = $rvd_back->search_vm('Void');
my $USER = create_user('foo','bar', 1);
my $ID_NETWORK_DEFAULT = _id_network('default');

########################################################################3

sub test_allow_all {
    my $domain = shift;

    my $ip = '192.168.1.2/32';
    my $net = Ravada::Network->new(address => $ip);
    ok(!$net->allowed($domain->id),"Expecting not allowed from unknown network");

    #check list bases, default allowed
    my $id_network = 90;
    allow_everything_any();
    test_allowed_domain_network($domain, $id_network,1, 0);
    deny_everything_any();
    test_allowed_domain_network($domain, $id_network,0, 0);

    my $sth = connector->dbh->prepare("INSERT INTO networks (id, name,address,all_domains) "
        ." VALUES ( ?,?,?,?) ");

    $sth->execute($id_network, 'foo', '192.168.1.0/24', 1);
    $sth->finish;

    # check default again, now there is a network
    allow_everything_any();
    test_allowed_domain_network($domain, $id_network,1, 0);
    deny_everything_any();
    test_allowed_domain_network($domain, $id_network,0, 0);

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


    my $sth = connector->dbh->prepare("INSERT INTO networks "
        ." (id, name,address,all_domains, no_domains) "
        ." VALUES (?,?,?,?,?) ");

    my $id_network = 100;
    $sth->execute($id_network,'foo', '10.1.1.0/24', 0,0);
    $sth->finish;

    allow_everything_any();
    test_allowed_domain_network($domain, $id_network, 1, 0);
    deny_everything_any();

    $sth = connector->dbh->prepare("INSERT INTO domains_network "
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


    allow_everything_any();
    test_allowed_domain_network($domain, $id_network, 1, 0);
    test_allowed_domain_network($domain, $ID_NETWORK_DEFAULT, 1, 0);

    deny_everything_any();
    test_allowed_domain_network($domain, $id_network, 1, 0);
    test_allowed_domain_network($domain, $ID_NETWORK_DEFAULT, 0, 0);

    $sth = connector->dbh->prepare("UPDATE domains_network "
        ." SET allowed=0 "
        ." WHERE id_domain=? AND id_network=?");

    $sth->execute($domain->id, $id_network);

    ok(!$net->allowed($domain->id),"Expecting not allowed from known network");
    ok(!$net->allowed_anonymous($domain->id)
        ,"Expecting not allowed anonymous from known network");
    test_allowed_domain_network($domain, $id_network, 0, 0);

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok(!$n_found, "Expecting 0 anon bases, got '$n_found'");
    }

    $sth = connector->dbh->prepare("UPDATE domains_network "
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

    $sth = connector->dbh->prepare("UPDATE domains_network "
        ." SET allowed=1, anonymous=1 "
        ." WHERE id_domain=? AND id_network=?");
    $sth->execute($domain->id, $id_network);

    ok($net->allowed($domain->id),"Expecting allowed from known network");
    ok($net->allowed_anonymous($domain->id)
        ,"Expecting allowed anonymous from known network");
    test_allowed_domain_network($domain, $id_network, 1, 1);

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        my $n_found = scalar (@$list_bases);
        ok($n_found == 1, "Expecting 1 anon bases, got '$n_found'");
    }

    $sth = connector->dbh->prepare("UPDATE domains_network "
        ." SET allowed=1, anonymous=0 "
        ." WHERE id_domain=? AND id_network=?");
    $sth->execute($domain->id, $id_network);

    is($net->allowed($domain->id),1,"Expecting allowed from known network");
    is($net->allowed_anonymous($domain->id),0
        ,"Expecting not allowed anonymous from known network");
    test_allowed_domain_network($domain, $id_network, 1, 0);

    { # test list bases anonymous
        my $list_bases = $RVD_FRONT->list_bases_anonymous($ip);
        is(scalar (@$list_bases) , 0);
    }

}

sub test_allowed_domain_network($domain, $id_network, $exp_allowed, $exp_anonymous) {
    my $list_bases = rvd_front->list_bases_network($id_network);
    my ($base) = grep({ $_->{name} eq $domain->name } @$list_bases);
    ok($base,"Expecting ".$domain->name." in list bases network ".Dumper($list_bases))
        or confess;

    is($base->{allowed},$exp_allowed, "Expecting base: $base->{id} in network $id_network allowed=$exp_allowed") or confess;
    is($base->{anonymous},$exp_anonymous) or confess;
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

    my $sth = connector->dbh->prepare("INSERT INTO networks (name,address,no_domains) "
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
sub allow_everything_any {
    my $sth = connector->dbh->prepare(
        "UPDATE networks set all_domains=1 where address='0.0.0.0/0'"
    );
    $sth->execute;
}


sub deny_everything_any {
    my $sth = connector->dbh->prepare(
        "UPDATE networks set all_domains=0 where address='0.0.0.0/0'"
    );
    $sth->execute;
}

sub _id_network {
    my $name = shift;
    my $sth = connector->dbh->prepare(
        "SELECT id FROM networks WHERE name=? "
    );
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    return $id;
}

sub test_conflict_allowed {
    my $sth = connector->dbh->prepare(
        "INSERT INTO networks (name, address, all_domains, no_domains) "
        ." VALUES ( ? , ?, ?, ?  )"
    );
    my $name = 'all';
    $sth->execute($name, '91.2.3.4/24', 1 , 1);

    $sth = connector->dbh->prepare(
        "SELECT all_domains, no_domains FROM networks WHERE name=?"
    );
    $sth->execute($name);
    my ($all,$no) = $sth->fetchrow;
    TODO: {
        local $TODO = "Requires trigger to avoid all_domains=1 and no_domains=1";
        isnt($all,$no);
    };
}

sub test_initial_networks($vm) {
    my $sth = connector->dbh->prepare("SELECT * FROM networks");
    $sth->execute();

    my ($localhost, $internal, $default);
    while (my $row = $sth->fetchrow_hashref) {
        $localhost = $row if $row->{address} =~ /^127.0.0/;
        $default = $row if $row->{address} =~ /^0.0.0.0/;
        $internal = $row if $row->{name} =~ /^internal/;
    }
    ok($localhost);
    like($localhost->{address},qr/^127.0.0/);
    ok($default);
    like($default->{address},qr/^0.0.0.0/);

    ok($internal);
    unlike($internal->{address},qr/^127.0.0/);
    unlike($internal->{address},qr/^0.0.0.0/);

    my $sth_del=connector->dbh->prepare("DELETE FROM networks WHERE name like 'internal%'");
    $sth_del->execute;

    create_domain($vm);

    rvd_back->_add_internal_network();

    $sth=connector->dbh->prepare("SELECT * FROM networks WHERE name like 'internal%'");
    $sth->execute;
    my $found = $sth->fetchrow_hashref;
    ok(!$found) or die Dumper($found);

}

########################################################################3
#
#
remove_old_domains();
remove_old_disks();

test_initial_networks($vm);

my $domain_name = new_domain_name();
my $domain = $vm->create_domain( name => $domain_name
            , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

$domain->prepare_base(user_admin);
$domain->is_public(1);

test_conflict_allowed();

my $net = Ravada::Network->new(address => '127.0.0.1/32');
ok($net->allowed($domain->id));

deny_everything_any();
my $net2 = Ravada::Network->new(address => '10.0.0.0/32');
ok(!$net2->allowed($domain->id), "Address unknown should not be allowed to anything");

test_allow_all($domain);
test_deny_all($domain);

test_allow_domain($domain);

end();
done_testing();
