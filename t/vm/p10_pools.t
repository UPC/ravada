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

my $BASE_NAME = "zz-test-base-alpine";
my $BASE;

sub test_duplicate_req {
        my $req = Ravada::Request->manage_pools(uid => user_admin->id);
        my $req_dupe = Ravada::Request->manage_pools(uid => user_admin->id);
        is($req_dupe->id, $req->id);
        my $req_dupe_user =Ravada::Request->manage_pools(uid => Ravada::Utils::user_daemon->id);
        is($req_dupe_user->id, $req->id);
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

    my @clones0 = $domain->clones(is_pool => 1 );
    for my $clone_data (@clones0) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->shutdown_now(user_admin);
    }

    $domain->pool_start($n_start);
    is($domain->pool_start, $n_start);
    _remove_enforce_limits();
    wait_request(skip => ['set_time','enforce_limits']);

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
        ."WHERE command = 'enforce_limits' OR command = 'set_time'"
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
    my $user = create_user(new_domain_name().$base->type,'carter');
    my @clones = $base->clones();
    wait_request();
    _remove_enforce_limits();
    _set_clones_client_status($base);

    my $name = new_domain_name();

    my $remote_ip ='9.9.9.4';
    my $req = Ravada::Request->create_domain(
                id_owner => $user->id
             ,start => 1
             ,name => $name
             ,id_base => $base->id
         ,remote_ip => $remote_ip
    );
    ok($req);
    delete_request('refresh_machine_ports');
    wait_request(debug => 0,skip => ['enforce_limits','set_time','refresh_machine_ports']);
    _remove_enforce_limits();
    is($req->status,'done');
    is($req->error,'');

    my @clones2 = $base->clones();
    is(scalar(@clones2), scalar(@clones));

    my ($clone) = grep { $_->{id_owner} == $user->id } @clones2;
    ok($clone,"Expecting clone that belongs to ".$user->name);
    is($clone->{client_status},$remote_ip, $clone->{name}) or exit;
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
    wait_request(debug => 0,skip => ['enforce_limits','set_time']);
    _remove_enforce_limits();
    is($req->status,'done');
    is($req->error,'');

    my @clones2 = $base->clones();
    is(scalar(@clones2), scalar(@clones));

    my ($clone) = grep { $_->{id_owner} == $user->id } @clones2;
    ok($clone,"Expecting clone that belongs to ".$user->name);
    like($clone->{client_status},qr'^(1.2.3.4|connect)', $clone->{name}) or exit;
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
    my $n_active = 0;
    for ( 1 .. 3 ) {
        wait_request(debug => 0);
        @clones = $base->clones(is_pool => 1 );
        $n_active = grep { $_->is_active}
        map { Ravada::Domain->open($_->{id}) }
        @clones;
        last if $n_active > $n_start;
        Ravada::Request->manage_pools(uid => user_admin->id, _force => 1);
    }
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
    wait_request( skip => ['enforce_limits','set_time']);
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
    my $base = create_domain_v2(vm=> $vm);
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

sub import_base($vm) {
    if ($vm->type eq 'KVM') {
        $BASE = import_domain($vm->type, $BASE_NAME, 1);
        confess "Error: domain $BASE_NAME is not base" unless $BASE->is_base;

        confess "Error: domain $BASE_NAME has exported ports that conflict with the tests"
        if $BASE->list_ports;
    } else {
        $BASE = create_domain_v2(vm => $vm);
    }
}

sub test_exposed_port($vm) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);

    $base->pools(1);
    $base->volatile_clones(1);
    my $n = 3;
    $base->pool_clones($n);
    $base->pool_start($n);
    $base->expose(22);

    my $req = Ravada::Request->manage_pools(uid => user_admin->id , _no_duplicate => 1);
    wait_request( debug => 0, skip => 'set_time' );
    is($req->status, 'done');
    is($req->error,'');
    is($base->is_base,1) or exit;

    my $req_refresh = Ravada::Request->refresh_vms( _no_duplicate => 1);
    wait_request( debug => 0 ,skip => 'set_time' );
    is($req_refresh->status, 'done');
    is(scalar($base->clones), $n);

    my $clone = $base->clone(name => new_domain_name(), user => user_admin);

    for my $clone ( $base->clones ) {
        Ravada::Domain->open($clone->{id})->remove(user_admin);
    }
    $base->remove(user_admin);

}

sub test_remove_clone($vm) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);

    $base->pools(1);
    $base->volatile_clones(1);

    my $n = 5;
    $base->pool_clones($n);
    $base->pool_start($n);
    my $req = Ravada::Request->manage_pools(uid => user_admin->id , _no_duplicate => 1);
    wait_request( debug => 0);
    is($req->status, 'done');

    my $req_refresh = Ravada::Request->refresh_vms( _no_duplicate => 1);
    wait_request( debug => 0);
    is($req_refresh->status, 'done');

    my @clones = $base->clones();
    is(scalar @clones, $n);
    Ravada::Domain->open($clones[0]->{id})->remove(user_admin);
    is(scalar($base->clones()),$n-1);

    $req = Ravada::Request->manage_pools(uid => user_admin->id, _no_duplicate => 1);
    wait_request();
    is($req->status, 'done');
    ok(Dumper([map { $_->{name} } $base->clones]));
    for my $clone ( $base->clones ) {
        like($clone->{name},qr/-\d+$/);
        Ravada::Domain->open($clone->{id})->remove(user_admin);
    }
    $base->remove(user_admin);

}

sub test_pool_with_nested_bases($vm, $volatile_clones) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    Ravada::Request->prepare_base(
                uid => user_admin->id
                ,id_domain => $base->id
    );
    wait_request();
    $base->is_public(1);

    $base->_data('shutdown_disconnected', 1);

    my $n_bases = 2;

    for ( 1 .. $n_bases ) {
        Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $base->id
            ,name => new_domain_name()."-base"
        );
    }
    wait_request(debug => 0);
    for my $clone ( $base->clones() ) {
        Ravada::Request->prepare_base(
            uid => user_admin->id
            ,id_domain => $clone->{id}
        );
    }
    wait_request(debug => 0);
    $base->pools(1);
    my $n = 5;
    my $started = 3;
    $base->_data('volatile_clones', $volatile_clones);

    $base->pool_clones($n);
    $base->pool_start($started);
    my $req = Ravada::Request->manage_pools(uid => user_admin->id
        ,_no_duplicate => 1);
    wait_request( debug => 0);
    is($req->status, 'done');
    is($req->error,'');

    my @clones0 = $base->clones();
    my $n_expected = $n + $n_bases;
    $n_expected = $started + $n_bases if $volatile_clones;
    is(scalar @clones0, $n_expected)
        or die Dumper([map {$_->{name} } @clones0]);

    my @clones_avail = grep { !$_->{is_base} } $base->clones ;
    my $n_available = $n;
    $n_available = $started if $volatile_clones;

    is(scalar @clones_avail, $n_available);

    remove_domain($base);
}

sub test_pool_with_nested_bases_owned($vm, $volatile_clones) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    Ravada::Request->prepare_base(
                uid => user_admin->id
                ,id_domain => $base->id
    );
    wait_request();
    $base->is_public(1);

    $base->_data('shutdown_disconnected', 1);

    my $n_bases = 2;
    my @users;
    for ( 1 .. $n_bases ) {
        my $user = create_user();
        Ravada::Request->clone(
            uid => $user->id
            ,id_domain => $base->id
            ,name => new_domain_name()."-base"
        );
        push @users,($user);
    }
    wait_request(debug => 0);
    is($base->clones,2);
    for my $clone ( $base->clones() ) {
        Ravada::Request->prepare_base(
            uid => user_admin->id
            ,id_domain => $clone->{id}
        );
    }
    wait_request(debug => 0);
    $base->_data('volatile_clones', $volatile_clones);
    $base->pools(1);
    my $n = 5;
    my $started = 3;

    $base->pool_clones($n);
    $base->pool_start($started);
    wait_request();
    for my $clone ($base->clones() ) {
        next if !$clone->{is_base};
        Ravada::Request->shutdown_domain(name => $clone->{name}
            ,uid => user_admin->id
            ,timeout => 1
        );
    }
    wait_request(debug => 0);
    for my $user (@users) {
        my $req = Ravada::Request->clone(
            uid => $user->id
            ,id_domain => $base->id
        );
        wait_request();
        is($req->status,'done');
        is($req->error,'');

    }

    my $n_expected = $n + $n_bases;
    $n_expected = $started + $n_bases if $volatile_clones;
    my @clones0 = $base->clones();
    is(scalar @clones0, $n_expected)
        or die Dumper([map {$_->{name} } @clones0]);

    my @clones_avail = grep { !$_->{is_base} } $base->clones ;
    my $n_available = $n;
    $n_available = $started if $volatile_clones;

    is(scalar @clones_avail, $n_available);


    remove_domain($base);
}


sub test_pool_with_volatiles($vm) {
    # Clones should be created.
    # As are volatile, only the started should be created
    # On shutdown they should be destroyed
    # In a while new clones should appear to honor the pool
    #
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    wait_request();
    Ravada::Request->prepare_base(uid => user_admin->id,
        id_domain => $base->id);
    $base->is_public(1);
    wait_request();

    $base->pools(1);
    $base->volatile_clones(1);
    $base->_data('shutdown_disconnected', 1);

    my $n = 5;
    my $started = 3;
    $base->pool_start($started);
    $base->pool_clones($n);

    my $req = Ravada::Request->clone(
        uid => create_user()->id
        , id_domain => $base->id
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'') or exit;
    my @clones0 = $base->clones();
    is(scalar @clones0, $started) or exit;
    my @clones;
    for my $c (@clones0) {
        push @clones,(Ravada::Domain->open($c->{id}));
        is($c->{status},'active');
        is($c->{is_volatile},1);
        is($c->{is_pool},1);
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $c->{id}
            ,remote_ip => '1.2.3.4'
        );
    }
    wait_request(debug => 0);
    delete_request('start','create','clone');
    for my $clone (@clones ) {
        $clone->_data('client_status','disconnected');
    }

    for ( 1 .. 60 ) {
        my $req_shutdown = Ravada::Request::_search_request(undef,
                'shutdown_domain'
        );
        wait_request(debug => 0);
        last if $req_shutdown || scalar($base->clones()) < $n;
        Ravada::Request->enforce_limits();
        wait_request(debug => 0);
        sleep 1;
    }
    ok(scalar($base->clones()) < $n, "Expecting less than $n up");

    #    $req = Ravada::Request->manage_pools(uid => user_admin->id
    #    ,_no_duplicate => 1);
    # wait_request( debug => 0);
    # is($req->status, 'done');

    is(scalar($base->clones()),$started);
    for my $clone ($base->clones) {
        is($clone->{is_pool},1);
    }

    _set_clones_client_status($base);
    _remove_enforce_limits();
    test_clones_assigned($base);

    _set_clones_client_status($base);
    test_create_more_clones_in_pool($base);

    remove_domain($base);

}

sub test_clones_assigned($base) {
    for my $clone ($base->clones()) {
        Ravada::Request->force_shutdown_domain(
            uid => user_admin->id
            ,id_domain => $clone->{id}
        );
    }
    my $n_clones_now;
    for ( 1 .. 10 ) {
        wait_request();
        $n_clones_now = scalar($base->clones());
        last if !$n_clones_now;
        sleep 1;
    }
    is($n_clones_now,0) or die $base->name;

    my $n_clones = $base->pool_clones();

    for my $n ( 0 .. $n_clones-1 ) {
        my $user_r = create_user(new_domain_name());
        my $req = Ravada::Request->clone(
            uid => $user_r->id
            ,id_domain => $base->id
            ,remote_ip => '2.2.2.'.$n
        );
        ok($req);
        wait_request(debug => 0);
        is($req->error,'');
        my ($clone) = grep { $_->{id_owner} == $user_r->id } $base->clones;
        ok($clone,"Expecting one clone belongs to ".$user_r->id)
            or die Dumper([map {[$_->{id_owner},$_->{client_status}] } $base->clones]);

    }
    my @clones = $base->clones;
    my $clone = Ravada::Front::Domain->open($clones[0]->{id});
    $clone->_data('client_status','disconnected');

    my $user_r = create_user();

    my $req = Ravada::Request->clone(
            uid => $user_r->id
            ,id_domain => $base->id
            ,remote_ip => '2.2.2.'.11
    );
    ok($req);
    wait_request(debug => 0, check_error => 0);
    like($req->error,qr/./);

    my ($clone_2) = grep { $_->{id_owner} == $user_r->id } $base->clones;
    ok(!$clone_2) or exit;

    $base->pool_clones($n_clones+1);
    is($base->pool_clones(),$n_clones+1) or exit;
    my $req2 = Ravada::Request->clone(
            uid => $user_r->id
            ,id_domain => $base->id
            ,remote_ip => '2.2.2.'.12
    );
    Ravada::Request->clone(
            uid => $user_r->id
            ,id_domain => $base->id
            ,remote_ip => '2.2.2.'.13
    );

    wait_request(check_error => 0);
    is($req2->error,'') or exit;

    ($clone_2) = grep { $_->{id_owner} == $user_r->id } $base->clones;
    ok($clone_2) or die $user_r->id;

    isnt($clone_2->{id},$clone->{id});

}


sub test_create_more_clones_in_pool($base) {

    my @clones = grep { !$_->{is_base} } $base->clones ;
    my $n_clones = scalar(@clones);
    for my $clone ( @clones ) {
        Ravada::Request->shutdown_domain(uid => user_admin->id
            ,id_domain => $clone->{id}
        );
    }
    wait_request();
    for my $n ( 0 .. $base->pool_clones()+2 - $n_clones ) {
        my $user_r = create_user(new_domain_name());
        my $req = Ravada::Request->clone(
            uid => $user_r->id
            ,id_domain => $base->id
            ,remote_ip => '2.2.2.'.$n
            ,retry => 3
        );
        ok($req);
        wait_request(debug => 0, check_error => 0);
        if ($n > $base->pool_clones) {
            like($req->error, qr/no free clones in pool/i);
        } else {
            is($req->error,'') or confess;
        }
        ok($base->clones <= $base->pool_clones, "Expecting no more than "
        .$base->pool_clones." clones");
    }
}

###############################################################

init();
clean();

for my $vm_name ( vm_names() ) {
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
        import_base($vm);

        test_pool_with_volatiles($vm);

        for my $volatile_clones ( 0,1) {
            test_pool_with_nested_bases($vm, $volatile_clones);
            test_pool_with_nested_bases_owned($vm, $volatile_clones);
        }

        test_exposed_port($vm);

        test_remove_clone($vm);
        test_duplicate_req();

        test_no_pool($vm);

        my $domain = create_domain_v2(vm => $vm);

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
