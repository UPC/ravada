use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(DumpFile);

use Ravada::Utils;

use lib 't/lib';
use Test::Ravada;


no warnings "experimental::signatures";
use feature qw(signatures);

sub test_duplicate_req {
        my $req = Ravada::Request->manage_pools(uid => user_admin->id);
        ok(! Ravada::Request->manage_pools(uid => user_admin->id));
        ok(! Ravada::Request->manage_pools(uid => Ravada::Utils::user_daemon->id));
}

sub test_pool($domain) {
    is($domain->pools,0);
    $domain->pools(1);
    is($domain->pools,1);

    is($domain->pool_clones,0);
    wait_request(debug => 0);
}

sub test_request() {
    my $req = Ravada::Request->manage_pools(uid => user_admin->id);
    wait_request();

    is($req->status,'done');
    is($req->error, '');
}

sub test_clones($domain, $n_clones) {
    wait_request();
    $domain->pool_clones($n_clones);
    is($domain->pool_clones, $n_clones);
    wait_request(debug => 0);
    is($domain->is_base,1);
    is($domain->clones(), $n_clones) or exit;
    is($domain->clones(is_pool => 1), $n_clones);

    my $clone = $domain->clone(name => new_domain_name, user => user_admin, from_pool => 0);
    ok($clone);
    is($domain->clones(), $n_clones+1) or exit;
    is($domain->clones(is_pool => 1), $n_clones);

    my $clone_f = Ravada::Front::Domain->open($clone->id);
    my $info = $clone_f->info(user_admin);
    is($info->{id_base}, $domain->id,Dumper($info)) or exit;
}

sub test_active($domain, $n_start) {
    is($domain->pool_start,0);
    $domain->pool_start($n_start);
    is($domain->pool_start, $n_start);
    _remove_enforce_limits();
    wait_request(skip => 'enforce_limits');

    Ravada::Request->manage_pools(uid => user_admin->id);
    _remove_enforce_limits();
    wait_request();

    my @clones = $domain->clones(is_pool => 1 );
    my $n_active = grep { $_->is_active}
    map { Ravada::Domain->open($_->{id}) }
    @clones;
    is($n_active, $n_start) or exit;
}

sub _remove_enforce_limits {
    my $sth = connector->dbh->prepare("DELETE FROM requests "
        ."WHERE command = 'enforce_limits'"
    );
    $sth->execute();
    $sth->finish;
}

sub _set_clones_client_status($base) {
    my $sth = connector->dbh->prepare(
        "UPDATE domains set client_status=?, client_status_time_checked=?"
        ." WHERE id_base=? AND status='active'"
    );
    $sth->execute('Disconnected',time,$base->id);
    $sth->finish;
}

sub test_user_create($base, $n_start) {
    $base->is_public(1);
    my $user = create_user('kevin','carter');
    my @clones = $base->clones();
    wait_request();
    _remove_enforce_limits();
    _set_clones_client_status($base);

    my $req = Ravada::Request->create_domain(
                id_owner => $user->id
             ,start => 1
             ,name => new_domain_name()
           ,id_base => $base->id
         ,remote_ip => '1.2.3.4'
    );
    ok($req);
    wait_request(debug => 0,skip => 'enforce_limits');
    _remove_enforce_limits();
    is($req->status,'done');
    is($req->error,'');

    my @clones2 = $base->clones();
    is(scalar(@clones2), scalar(@clones));

    my ($clone) = grep { $_->{id_owner} == $user->id } @clones2;
    ok($clone,"Expecting clone that belongs to ".$user->name);
    like($clone->{client_status},qr'^1.2.3.4$', $clone->{name}) or exit;
    is($clone->{is_pool},1) or exit;

    $user->remove();
}

sub test_user($base, $n_start) {
    # TODO : test $domain->_data('comment');
    $base->is_public(1);
    my $user = create_user('kevin','carter');
    my @clones = $base->clones();
    wait_request();
    _remove_enforce_limits();
    _set_clones_client_status($base);

    my $req = Ravada::Request->clone(
                uid => $user->id
             ,start => 1
         ,id_domain => $base->id
         ,remote_ip => '1.2.3.4'
    );
    ok($req);
    wait_request(debug => 0,skip => 'enforce_limits');
    _remove_enforce_limits();
    is($req->status,'done');
    is($req->error,'');

    my @clones2 = $base->clones();
    is(scalar(@clones2), scalar(@clones));

    my ($clone) = grep { $_->{id_owner} == $user->id } @clones2;
    ok($clone,"Expecting clone that belongs to ".$user->name);
    like($clone->{client_status},qr'^connect', $clone->{name}) or exit;
    is($clone->{is_pool},1) or exit;

    my $clone2 = $base->_search_pool_clone($user);
    ok($clone2);
    is($clone2->id, $clone->{id});
    is($clone2->is_pool,1) or exit;

    my $clone_f = Ravada::Front::Domain->open($clone2->id);
    my $info = $clone_f->info(user_admin);
    is($info->{pools},0);
    is($info->{is_pool},1) or die Dumper($clone_f);
    is($info->{comment},$user->name);

    # now we should have another active
    wait_request(debug => 0);
    wait_request(debug => 0);
    @clones = $base->clones(is_pool => 1 );
    my $n_active = grep { $_->is_active}
    map { Ravada::Domain->open($_->{id}) }
    @clones;
    ok($n_active >= $n_start+1,"Expecting active > $n_start, got $n_active ") or exit;

    is($n_active, $n_start+1,"Expecting active == ".(1+ $n_start)
        .", got $n_active ") or exit;

    my $user_r = create_user('paul','robeson');
    $req = Ravada::Request->clone(
                uid => $user_r->id
             ,start => 1
         ,id_domain => $base->id
         ,remote_ip => '2.2.2.5'
    );
    ok($req);
    _remove_enforce_limits();
    wait_request( skip => 'enforce_limits');
    is($req->status,'done');
    is($req->error,'');

    my $clone_r = $base->_search_pool_clone($user_r);
    isnt($clone_r->id,$clone2->id);

    $user->remove();
    $user_r->remove();
}

sub test_clone_regular($base, $add_to_pool) {
    is($base->pools,1) or confess "Base ".$base->name." has no pools";
    my $name = new_domain_name();
    my $req = Ravada::Request->clone(
        name => $name
        ,id_domain => $base->id
        ,uid => user_admin->id
        ,add_to_pool => $add_to_pool
        ,from_pool => 0
    );
    ok($req) or exit;

    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'');

    my $domain = rvd_back->search_domain($name);
    ok($domain,"Expecting clone from ".$base->name) or exit;
    is($domain->is_pool, $add_to_pool);

    $domain->pools(1);
    # copy the clone
    my $name_clone = new_domain_name();
    $req = Ravada::Request->clone(
        name => $name_clone
        ,id_domain => $domain->id
        ,uid => user_admin->id
        ,add_to_pool => $add_to_pool
        ,from_pool => 0
    );
    ok($req) or exit;
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'') or exit;

    my $clone = rvd_back->search_domain($name_clone);
    ok($clone,"Expecting clone from ".$name) or exit;
    is($clone->is_pool, $add_to_pool) or exit;

    $domain->remove(user_admin);


}

sub test_no_pool($vm) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);

    my $clone_name = new_domain_name();

    my $clone;
    eval {
        $clone = rvd_back->create_domain(
            id_base => $base->id
            ,name => $clone_name
            ,add_to_pool => 1
            ,id_owner => user_admin->id
        );
    };
    like($@,qr(this base has no pools)i);
    ok(!$clone);

    my $clone2 = rvd_back->search_domain($clone_name);
    ok(!$clone2);

    $clone->remove(user_admin) if $clone;

    $clone_name = new_domain_name();
    eval {
        $clone = $base->clone(
             name => $clone_name
            ,user => user_admin
            ,add_to_pool => 1
        );
    };
    like($@,qr(this base has no pools)i);
    $clone2 = rvd_back->search_domain($clone_name);
    ok(!$clone);
    ok(!$clone2);

    $clone->remove(user_admin) if $clone;
    $base->remove(user_admin);
    wait_request( debug => 0);
}

init();
clean();

for my $vm_name (reverse vm_names() ) {
    my $vm;
    eval {
        $vm = rvd_back->search_vm($vm_name);
    };
    SKIP: {
        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("*** Testing pools in $vm_name ***");

        test_duplicate_req();

        test_no_pool($vm);

        my $domain = create_domain($vm);

        my $n_clones = 6;
        my $n_start = 2;

        test_pool($domain);
        test_request();
        test_clones($domain, $n_clones);
        test_active($domain, $n_start);

        test_user($domain, $n_start);
        test_user_create($domain, $n_start);

        # add the clone to the pool => 1 <=
        test_clone_regular($domain   , 1);
        # do not add the clone to the pool
        test_clone_regular($domain, 0);

        _remove_enforce_limits();
   }
}

end();
done_testing();
