#!/usr/bin/perl
# test volatile anonymous domains kiosk mode

use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
use_ok('Ravada::Route');

use lib 't/lib';
use Test::Ravada;

init();

my $IP = "10.0.0.1";
my $NETWORK = $IP;
$NETWORK =~ s{(.*)\..*}{$1.0/24};

################################################################################

sub create_network {

    my $sth = connector->dbh->prepare(
        "INSERT INTO networks (name, address) "
        ." VALUES (?,?)"
    );
    $sth->execute('foo',$NETWORK);
    $sth->finish;
}

sub delete_network {
    my $sth = connector->dbh->prepare(
        "DELETE FROM networks WHERE address=?"
    );
    $sth->execute($NETWORK);
    $sth->finish;
}

sub id_network {
    my $address = shift;

    my $sth = connector->dbh->prepare(
        "SELECT id FROM networks WHERE address=?"
    );
    $sth->execute($address);
    my ($id) = $sth->fetchrow;

    return $id;
}

sub allow_anonymous {
    my $base = shift;

    my $id_network = id_network($NETWORK);
    my $sth = connector->dbh->prepare(
        "INSERT INTO domains_network "
        ." (id_domain, id_network, anonymous )"
        ." VALUES (?,?,?) "
    );
    $sth->execute($base->id, $id_network, 1);
    $sth->finish;
}

sub _cleanup_info($user_id) {
    delete_request('cleanup');
    my $req = Ravada::Request->cleanup( );
    wait_request(debug => 0);
    my $sth = connector->dbh->prepare("SELECT name,date_created FROM users where id=?");
    $sth->execute($user_id);

    return $sth->fetchrow;
}

sub test_volatile_cleanup ($base) {
    return if $base->type ne 'KVM';
    my $user = Ravada::Auth::SQL::add_user(name => "user_".new_domain_name(), is_temporary => 1);
    my $user_id = $user->id;

    my ($name, $date_created) = _cleanup_info($user_id);
    ok($name);

    my $sth_update = connector->dbh->prepare("UPDATE users set date_created=? WHERE id=?");
    my $date = _date();
    $sth_update->execute($date,$user_id);

    ($name, $date_created) = _cleanup_info($user_id);
    ok($name, "date $date_created");

    $sth_update->execute(_date(time - 25 * 3600),$user_id);
    my $clone = $base->clone(
        user => $user
        , name => new_domain_name
    );
    $clone->start($user)                if !$clone->is_active;

    ($name, $date_created) = _cleanup_info($user_id);
    ok($name, "date $date_created");

    my $clone_id = $clone->id;
    my $sth_deldom = connector->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth_deldom->execute($clone->id);

    ($name, $date_created) = _cleanup_info($user_id);
    ok(!$name);

    shutdown_domain_internal($clone);

    for my $table ( 'domain_displays' , 'domain_ports', 'volumes', 'domains_void', 'domains_kvm', 'domain_instances', 'bases_vm', 'domain_access', 'base_xml', 'file_base_images', 'iptables', 'domains_network') {
        my $sth = connector->dbh->prepare("DELETE FROM $table WHERE id_domain=?");
        $sth->execute($clone_id);
    }

}

sub _date($time = time) {
    my @now = localtime($time);
    $now[5]+=1900;
    $now[4]++;
    for ( 0 .. 4 ) {
        $now[$_] = "0$now[$_]" if length($now[$_]) < 2;
    }
    return "$now[5]-$now[4]-$now[3] $now[2]:$now[1]:$now[0]";
}

sub test_volatile {
    my ($vm_name, $base) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $name = new_domain_name();

    my $user_name = "user_".new_domain_name();
    my $user_id;
    {
        my $user = Ravada::Auth::SQL::add_user(name => $user_name, is_temporary => 1);
        is($user->is_temporary,1);
        $user_id = $user->id;

        my $req = Ravada::Request->clone(
            uid => $user->id
            , id_domain => $base->id
            , name => $name
            ,remote_ip => '192.0.9.1/32'
        );
        wait_request(debug => 0);
        my $clone = $vm->search_domain($name);
        is($clone->is_active,1,"[$vm_name] Expecting clone active");

        like($clone->spice_password,qr{..+},"[$vm_name] ".$clone->name)
        if $vm_name eq 'KVM';

        is($clone->is_volatile,1,"[$vm_name] Expecting is_volatile");

        my $clone2 = rvd_back->search_domain($name);
        is($clone2->is_volatile,1,"[$vm_name] Expecting is_volatile");

        my $clone3 = $vm->search_domain($name);
        is($clone3->is_volatile,1,"[$vm_name] Expecting is_volatile");

        my @volumes = $clone->list_volumes();

        is($clone->is_active, 1);
        eval { $clone->shutdown_now(user_admin)    if $clone->is_active};
        is(''.$@,'',"[$vm_name] Expecting no error after shutdown");

        is($clone->is_active, 0);
        # test out of the DB
        my $sth = connector->dbh->prepare("SELECT id,name FROM domains WHERE name=?");
        $sth->execute($name);
        my $row = $sth->fetchrow_hashref;
        ok(!$row,"Expecting no domain info in the DB, found ".Dumper($row))    or exit;

        # search for the removed domain
        my $domain2 = $vm->search_domain($name);
        ok(!$domain2,"[$vm_name] Expecting domain $name removed after shutdown\n"
            .Dumper($domain2)) or exit;

        is(rvd_front->domain_exists($name),0,"[$vm_name] Expecting domain removed after shutdown")
            or exit;

        my $user2 = Ravada::Auth::SQL->new(name => $user_name);
        ok(!$user2->id,"Expecting user '$user_name' removed");

        my $domain_b = rvd_back->search_domain($name);
        ok(!$domain_b,"[$vm_name] Expecting domain removed after shutdown");

        my $domains_f = rvd_front->list_domains();
        ok(!grep({ $_->{name} eq $name } @$domains_f),"[$vm_name] Expecting $name not listed");

        $name = undef;

        $vm->refresh_storage_pools();
        $vm->refresh_storage();
        for my $file ( @volumes ) {
            ok(! -e $file,"[$vm_name] Expecting volume $file removed") or BAIL_OUT();
        }
    }

    # now a normal clone
    my $name2 = new_domain_name();
    my $clone_normal = $base->clone(
        user => user_admin,
        name => $name2
    );

    is($clone_normal->is_volatile,0,"[$vm_name] Expecting not volatile");

    $clone_normal->shutdown_now(user_admin);

    my $domain_n2 = $vm->search_domain($name2);
    ok($domain_n2,"[$vm_name] Expecting domain $name2 there after shutdown") or exit;

    my $domain_nf = rvd_front->search_domain($name2);
    ok($domain_nf,"[$vm_name] Expecting domain there after shutdown");

    my $domain_nb = rvd_back->search_domain($name2);
    ok($domain_nb,"[$vm_name] Expecting domain there after shutdown");

    my $domains_nf = rvd_front->list_domains();
    ok(grep({ $_->{name} eq $name2 } @$domains_nf),"[$vm_name] Expecting $name2 listed");

    $clone_normal->remove(user_admin);

    my $clone_removed = rvd_back->search_domain($name);
    is($clone_removed,undef);

    my $user_removed = Ravada::Auth::SQL->search_by_id($user_id);
    is($user_removed,undef,"User ".$user_id." should be removed") or exit;

}

# KVM volatiles get auto-removed
sub test_volatile_auto_kvm {
    my ($vm_name, $base) = @_;

    my $name = new_domain_name();

    my $user_name = "user_".new_domain_name();
    my $user = Ravada::Auth::SQL::add_user(name => $user_name, is_temporary => 1);

    $base->volatile_clones(1);
    is($base->volatile_clones,1) or exit;
    my $clone = $base->clone(
          user => $user
        , name => $name
    );
    is($clone->is_volatile,1) or exit;
    my $clone_extra = Ravada::Domain->open($clone->id);
    ok($clone_extra->_data_extra('xml'),"[$vm_name] expecting XML for ".$clone->name) or BAIL_OUT;
    ok($clone_extra->_data_extra('id_domain'),"[$vm_name] expecting id_domain for ".$clone->name) or BAIL_OUT;

    is( $clone->is_active, 1,"[$vm_name] volatile domains should clone started" );
    $clone->start($user)                if !$clone->is_active;
    is($clone->is_active,1,"[$vm_name] Expecting clone active");

    is($clone->is_volatile,1,"[$vm_name] Expecting is_volatile");
    is(''.$@,'',"[$vm_name] Expecting no error after shutdown");

    my $spice_password = $clone->spice_password();
    like($spice_password,qr(..+));

    my @volumes = $clone->list_volumes();
    ok($clone->_data_extra('xml'),"[$vm_name] expecting XML for ".$clone->name) or BAIL_OUT;
    $clone->domain->destroy();
    $clone=undef;

    my $clone_force = $base->_vm->search_domain($name, 1);
    ok($clone_force,"Expecting clone data still in db") or exit;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain2;
    for ( 1 .. 10 ) {
        $domain2 = $vm->search_domain($name);
        last if !$domain2;
        sleep 1;
    }
    ok(!$domain2,"[$vm_name] Expecting domain $name removed after shutdown");

    rvd_back->_clean_volatile_machines();

    rvd_back->_refresh_volatile_domains();
    my $domain_f;
    $domain_f = rvd_front->search_domain($name) if rvd_front->domain_exists($name);
    ok(!$domain_f,"[$vm_name] Expecting domain $name removed after shutdown "
        .Dumper($domain_f)) or exit;

    my $domain_b = rvd_back->search_domain($name);
    ok(!$domain_b,"[$vm_name] Expecting domain removed after shutdown");

    rvd_back->_cmd_refresh_storage();

    my $sth = connector->dbh->prepare("SELECT * FROM domains where name=?");
    $sth->execute($name);
    my $row = $sth->fetchrow_hashref;
    is(scalar keys %$row, 0, Dumper($row)) or exit;

    my $domains_f = rvd_front->list_domains();
    ok(!grep({ $_->{name} eq $name } @$domains_f),"[$vm_name] Expecting $name not listed")
        or exit;

    for my $file ( @volumes ) {
        ok(! -e $file,"[$vm_name] Expecting volume $file removed") or exit;
    }

    for my $file ( @volumes ) {
        ok(! -e $file,"[$vm_name] Expecting volume $file removed");
    }

    $user = Ravada::Auth::SQL::add_user(name => "$user_name.2", is_temporary => 1);
    my $clone2;
    eval {
        $clone2 = $base->clone(
            user => $user
            ,name => $name
        );
    };
    is(''.$@,'',"[$vm_name] Expecting clone called $name created");
    ok($clone2,"[".$vm->type."] expecting clone from ".$base->name) or exit;
    isnt($clone2->spice_password, $spice_password
            ,"[$vm_name] Expecting spice password different")   if $clone2;

    $clone2->start(user_admin)  if !$clone2->is_active;
    is($clone2->is_active,1,"[$vm_name] Expecting clone active");

    my $clone3= $vm->search_domain($name);
    ok($clone3,"[$vm_name] Expecting clone $name");

    eval { $clone2->remove(user_admin) if $clone2 };
    is(''.$@,'');

    $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=?");
    $sth->execute($name);
    $row = $sth->fetchrow_hashref;
    is(keys(%$row),0);
}

sub test_upgrade {
    my $user_name = "user_".new_domain_name();
    my $user = Ravada::Auth::SQL::add_user(name => $user_name, is_temporary => 1);


    my $sth = connector->dbh->prepare("DELETE FROM grants_user WHERE id_user=?");
    $sth->execute($user->id);

    rvd_back->_update_data();

    $sth = connector->dbh->prepare("SELECT id from grants_user WHERE id_user=?");
    $sth->execute($user->id);
    my ($found) = $sth->fetchrow;

    is($found,undef);

    $user->remove();
}
################################################################################

clean();

test_upgrade();

for my $vm_name ( vm_names() ) {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";

        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing volatile for $vm_name");

        init( $vm_name );

        create_network();

        my $base= create_domain($vm_name);
        $base->prepare_base(user_admin());
        $base->is_public(1);
        allow_anonymous($base);

        test_volatile_cleanup($base);
        test_volatile($vm_name, $base);
        test_volatile_auto_kvm($vm_name, $base) if $vm_name eq'KVM';

        delete_network();
        $base->remove(user_admin);
    }

}

end();
done_testing();
