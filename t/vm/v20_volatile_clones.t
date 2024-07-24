use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Mojo::JSON qw(decode_json);
use POSIX qw(WNOHANG);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

use lib 't/lib';
use Test::Ravada;

init();

$Ravada::Domain::TTL_REMOVE_VOLATILE = 1;

######################################################################3
sub test_volatile_clone_req {
    my $vm = shift;
    my $remote_ip = '127.0.0.1';

    my $domain = create_domain($vm->type);
    ok($domain);

    is($domain->volatile_clones, 0);

    $domain->volatile_clones(1);
    is($domain->volatile_clones, 1);
    my $clone_name = new_domain_name();

    $domain->prepare_base(user_admin);
    my $req = Ravada::Request->create_domain(
        name => $clone_name
        ,id_owner => user_admin->id
        ,id_base => $domain->id
        ,remote_ip => $remote_ip
        ,start => 1
    );
    rvd_back->_process_requests_dont_fork();

    my $clone = rvd_back->search_domain($clone_name);
    is($clone->is_active, 1);
    is($clone->is_volatile, 1);

    $domain->volatile_clones(0);
    is($domain->volatile_clones, 0);

    my $clone_name2 = new_domain_name();

    my $req2 = Ravada::Request->create_domain(
        name => $clone_name2
        ,id_owner => user_admin->id
        ,id_base => $domain->id
        ,remote_ip => $remote_ip
        ,start => 1
    );
    wait_request();

    my $clone2 = rvd_back->search_domain($clone_name2);
    is($clone2->is_active, 1);
    is($clone2->is_volatile, 0);

    $clone2->remove(user_admin);
    $clone->remove(user_admin);
    $domain->remove(user_admin);

}


sub test_volatile_clone {
    my $vm = shift;
    my $remote_ip = '127.0.0.1';

    my $domain = create_domain($vm->type);
    ok($domain);

    is($domain->volatile_clones, 0);

    $domain->volatile_clones(1);
    is($domain->volatile_clones, 1);
    my $clone_name = new_domain_name();

    $domain->prepare_base(user_admin);
    my $clone = $domain->_vm->create_domain(
        name => $clone_name
        ,id_owner => user_admin->id
        ,id_base => $domain->id
        ,remote_ip => $remote_ip
    );

    is($clone->is_active, 1);
    is($clone->is_volatile, 1);
    is($clone->_has_builtin_display,1);

    $clone->start(user_admin)   if !$clone->is_active;
    wait_request();

    is($clone->is_active, 1) && do {

        my $clonef = Ravada::Front::Domain->open($clone->id);
        ok($clonef);
        isa_ok($clonef, 'Ravada::Front::Domain');
        is($clonef->is_active, 1);
        like($clonef->display(user_admin),qr'.');
        like($clone->remote_ip,qr(.),$clone->name) or exit;
        like($clone->client_status,qr(.));

        my $domains = rvd_front->list_machines(user_admin);
        my ($clone_listed) = grep {$_->{name} eq $clonef->name } @$domains;
        ok($clone_listed,"Expecting to find ".$clonef->name." in ".Dumper($domains))
            and do {
                is($clone_listed->{can_hibernate},0);
                ok(exists $clone_listed->{client_status},"Expecting client_status field");
                like($clone_listed->{client_status},qr(.));
            };


        like($clone->display(user_admin),qr'\w+://');

        $clonef = rvd_front->search_domain($clone_name);
        ok($clonef);
        isa_ok($clonef, 'Ravada::Front::Domain');
        is($clonef->is_active, 1,"[".$vm->type."] expecting active $clone_name") or exit;
        like($clonef->display(user_admin),qr'\w+://');

        is($clone->spice_password, undef);
        my $list = rvd_front->list_domains();

        my @volumes = $clone->list_volumes();

        my $req = Ravada::Request->shutdown_domain( id_domain => $clone->id
                ,uid => user_admin->id
            );
        $clone->shutdown_now(user_admin);

        eval { $clone->is_active };
        is(''.$@,'');

        is($clone->is_removed, 1);

        for my $vol (@volumes) {
            ok( ! -e $vol,"Expecting $vol removed");
        }

        my $clone2 = $vm->search_domain($clone_name);
        ok(!$clone2, "[".$vm->type."] volatile clone should be removed on shutdown");

        my $sth = connector->dbh->prepare("SELECT * FROM domains where name=?");
        $sth->execute($clone_name);
        my $row = $sth->fetchrow_hashref;
        is($row,undef);

        eval { rvd_back->_process_all_requests_dont_fork() };
        is($@,'');
        is($req->status,'done');
        is($req->error, '');
    };

    $clone->remove(user_admin)  if !$clone->is_removed;
    $domain->remove(user_admin);
}

sub test_enforce_limits {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    ok($domain);

    $domain->volatile_clones(1);
    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    my $user = create_user("limit$$",'bar');

    my $clone_name = new_domain_name();
    my $clone = $domain->clone(
        name => $clone_name
        ,user => $user
    );

    is($clone->is_active, 1);
    is($clone->is_volatile, 1);

    sleep 1;
    my $clone2 = $domain->clone(
        name => new_domain_name
        ,user => $user
    );
    is($clone2->is_active, 1);
    is($clone2->is_volatile, 1);

    my $req = Ravada::Request->enforce_limits( timeout => 1, _force => 1 );
    eval { rvd_back->_enforce_limits_active($req) };
    is(''.$@,'');
    for ( 1 .. 10 ){
        last if !$clone->is_active;
        sleep 1;
    }

    is($clone->is_active,0,"[".$vm->type."] expecting clone ".$clone->name." inactive")
        or exit;
    is($clone2->is_active,1 );

    for ( 1 .. 3 ) {
        my $clone0_2 = $vm->search_domain($clone_name);

        my $clone0_f;
        eval { $clone0_f = rvd_front->search_domain($clone_name) };

        last if !$clone0_2 && !$clone0_f;
        Ravada::Request->refresh_machine(uid => user_admin->id
            ,id_domain =>  $clone->id, _force => 1);
        wait_request(debug => 1);
    }
    my $clone0_2 = $vm->search_domain($clone_name);
    is($clone0_2, undef);
    $clone0_2 = rvd_back->search_domain($clone_name);
    is($clone0_2, undef);

    rvd_back->_cmd_refresh_vms();

    my $clone0_f;
    eval { $clone0_f = rvd_front->search_domain($clone_name) };
    is($clone0_f, undef);

    my $list_domains = rvd_front->list_domains();
    ($clone0_f) = grep { $_->{name} eq $clone_name } @$list_domains;
    is($clone0_f, undef);

    eval { $clone2->remove(user_admin) };
    is(''.$@,'');

    remove_domain($domain);

    $user->remove();
}

sub test_internal_shutdown {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    $domain->volatile_clones(1);

    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    my $clone_name = new_domain_name();
    my $user = create_user('Roland','Pryzbylewski');
    my $clone = $domain->clone( user => $user , name => $clone_name);
    is($clone->is_volatile,1);

    my @volumes = $clone->list_volumes();

    sleep 1;
    shutdown_domain_internal($clone);

    rvd_back->_cmd_refresh_vms();
    for ( 1 .. 3 ) {
        my $clone0_2 = $vm->search_domain($clone_name);
        last if !$clone0_2;
        Ravada::Request->refresh_machine(uid => user_admin->id
            ,id_domain =>  $clone->id, _force => 1);
        wait_request(debug => 0);
    }

    my $clone0_f;
    for ( 1 .. 5 ) {
        my $clone0_2 = $vm->search_domain($clone_name);
        eval { $clone0_f = rvd_front->search_domain($clone_name) };

        last if !$clone0_2 && !$clone0_f;

        Ravada::Request->refresh_machine(uid => user_admin->id
            ,id_domain =>  $clone->id, _force => 1);
        wait_request(debug => 1);
    }

    eval { $clone0_f = rvd_front->search_domain($clone_name) };
    is($clone0_f, undef) or die $clone_name;

    my $list_domains = rvd_front->list_domains();
    ($clone0_f) = grep { $_->{name} eq $clone_name } @$list_domains;
    is($clone0_f, undef);

    for my $vol ( @volumes ) {
        ok(!-e $vol,"Expecting $vol removed") or exit;
    }

    my $domain2 = rvd_back->search_domain($clone_name);
    ok(!$domain2,"[".$vm->type."] expecting domain $clone_name removed");

    test_auto_remove($clone);

    $domain2->remove(user_admin)    if $domain2;

    $user->remove();
}

sub test_auto_remove($clone) {
    my $removed;
    eval { $removed = Ravada::Domain->open($clone->id) };
    like($@,qr/Domain not found/);
    ok(!$removed);

}

sub test_old_machine {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    $domain->volatile_clones(1);

    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    my $clone_name = new_domain_name();
    my $user = create_user('Roland','Pryzbylewski');
    my $clone = $domain->clone( user => $user , name => $clone_name);

    my $sth = connector->dbh->prepare("DELETE FROM domains_kvm");
    $sth->execute();

    $sth = connector->dbh->prepare("DELETE FROM domains_void ");
    $sth->execute();

    my $clone2 = Ravada::Domain->open($clone->id);
    is($clone2->name, $clone_name);
    ok($clone2->is_known);
    ok($clone2->is_known_extra,"Expecting extra on $clone_name") or exit;

    shutdown_domain_internal($clone);

    eval { $clone2->remove(user_admin) };
    is($@,'',"Expecting no error on remove $clone_name");

    $clone2 = $vm->search_domain($clone_name);
    ok(!$clone2);

    eval { $domain->remove(user_admin) };
    is($@,'',"Expecting no error on remove ".$domain->name);

    my $base2 = $vm->search_domain($domain->name);
    ok(!$base2);

    $user->remove();
    $clone->remove(user_admin)  if !$clone->is_removed;
    $domain->remove(user_admin);
}

sub test_old_machine_req {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    $domain->volatile_clones(1);

    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    my $clone_name = new_domain_name();
    my $user = create_user('Roland','Pryzbylewski');
    my $clone = $domain->clone( user => $user , name => $clone_name);

    my $sth = connector->dbh->prepare("DELETE FROM domains_kvm");
    $sth->execute();
    $sth->finish;

    $sth = connector->dbh->prepare("DELETE FROM domains_void ");
    $sth->execute();
    $sth->finish;

    my $clone_noextra = $vm->search_domain($clone_name);
    is($clone_noextra->is_known_extra, 1
        ,"[".$vm->type."] Expecting clone extra in $clone_name") or exit;

    shutdown_domain_internal($clone);

    my $req = Ravada::Request->remove_domain(
        name => $clone->name
        ,uid => user_admin->id
    );

    rvd_back->_process_requests_dont_fork();
    is($req->status,'done');
    is($req->error,'');

    my $clone2 = $vm->search_domain($clone_name);
    ok(!$clone2);

    $req = Ravada::Request->remove_domain(
        name => $domain->name
        ,uid => user_admin->id
    );
    rvd_back->_process_requests_dont_fork();
    is($req->status,'done');
    is($req->error,'');

    my $base2 = $vm->search_domain($domain->name);
    ok(!$base2);

    $user->remove();
    $clone->remove(user_admin)  if !$clone->is_removed;
    $domain->remove(user_admin);
}

sub _search_ips {
    my $out = `ip -4 -j route`;
    my $info = decode_json($out);
    my @ips;
    my %net;
    for my $ip (@$info) {
        my ($down) = grep /^linkdown$/,@{$ip->{flags}};
        next if $down;
        next if !$ip->{prefsrc};
        my $dst = $ip->{dst};
        my $metric = $ip->{metric};
        my $metric_old = ($net{$dst}->[1] or 0 );
        next if $metric_old && $metric>$metric_old;
        $net{$dst} = [$ip->{prefsrc}, $metric];
    }
    for (keys %net) {
        push @ips,($net{$_}->[0]);
    }
    return @ips;
}

sub test_ips {
    my $vm = shift;

    my $public_ip = $vm->_data('public_ip');
    my @ips = _search_ips();

    for my $ip (@ips) {
        diag("Testing ip $ip");
        $vm->public_ip($ip);
        is($vm->_data('public_ip'),$ip);
        is($vm->public_ip, $ip);
        is($vm->listen_ip, $ip);
        is($vm->listen_ip($ip), $ip);

        my $vm2 = Ravada::VM->open($vm->id);
        is($vm2->_data('public_ip'),$ip);
        is($vm2->listen_ip, $ip);
        is($vm2->public_ip, $ip);

        my $domain = create_domain($vm);

        if ($vm->type ne 'Void') {
            my $xml = $domain->get_xml_base;
            my ($listen) = $xml =~ m{listen='(.*)'};
            my ($address) = $xml =~ m{listen.*address='(.*)'};
            is($listen, $ip);
            is($address, $ip);
        }

        $domain->volatile_clones(1);

        my $clone = $domain->clone(name => new_domain_name , user => user_admin);
        like($clone->display(user_admin), qr(^\w+://$ip));

        $clone->remove(user_admin);

        $vm->public_ip('');
        is($vm->public_ip,'');

        $domain = Ravada::Domain->open($domain->id);
        for my $ip2 (@ips) {
            is($vm->listen_ip($ip2), $ip2) or exit;
            my $clone2 = $domain->clone(name => new_domain_name , user => user_admin
                ,start => 1
                ,remote_ip => $ip2
            );
            if ($vm->type ne 'Void') {
                my $xml = $clone2->xml_description;
                my ($listen) = $xml =~ m{listen='(.*)'};
                my ($address) = $xml =~ m{listen.*address='(.*)'};
                is($listen, $ip2);
                is($address, $ip2);
            }
            my $display_info = $clone2->display_info(user_admin);

            #            like($display_info->{display}, qr(^\w+://$ip2),$clone2->name) or exit;
            is($display_info->{ip},$ip2,$clone2->name) or exit;

            $clone2->remove(user_admin);
        }
        $domain->remove(user_admin);
    }

    $vm->public_ip($public_ip);
}

sub test_req_volatile($vm) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    for my $set_volatile ( 1,0 ) {
        $base->volatile_clones($set_volatile);
        for my $volatile ( 0,1 ) {
            my $req = Ravada::Request->clone(
                id_domain => $base->id
                ,number => 3
                ,volatile => $volatile
                ,uid => user_admin->id
            );
            wait_request();
            for my $clone ( $base->clones ) {
                is($clone->{is_volatile}, $volatile
                    , "Expecting ".$clone->{name}." base_volatile=$set_volatile volatile=$volatile") or exit;

                _test_non_persistent($vm, $clone->{id}, $volatile);

                Ravada::Request->remove_domain(name => $clone->{name}
                    ,uid => user_admin->id
                );
            }
        }
    }
    remove_domain_and_clones_req($base,1,1);
}

sub _test_non_persistent($vm ,$id_domain, $volatile) {

    return if $vm->type ne 'KVM';

    my $clone = Ravada::Domain->open($id_domain);
    if ($volatile) {
        ok(!$clone->domain->is_persistent);
    } else {
        ok($clone->domain->is_persistent, "Expecting ".$clone->name
            ." is persistent") or exit;
    }

    if ($volatile) {
        $clone->domain->destroy if $clone->domain->is_active;

        my $cloneb = Ravada::Domain->open($id_domain);
        ok(!$cloneb);
    }
}

sub test_cleanup($vm) {
    my $user = create_user();
    user_admin->make_admin($user->id);
    my $user_name = $user->name;

    my $domain = create_domain_v2(vm => $vm, user => $user);
    my $id_domain = $domain->id;

    remove_domain_internal($domain);

    my $sth = connector->dbh->prepare("UPDATE domains set is_volatile=1 WHERE id=?");
    $sth->execute($id_domain);
    rvd_back->_refresh_volatile_domains();

    my $user2 = Ravada::Auth::SQL->new(name => $user_name);
    ok($user2->id);
}

######################################################################3
clean();

for my $vm_name ( vm_names() ) {
    ok($vm_name);
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing volatile clones for $vm_name");

        test_internal_shutdown($vm);

        test_cleanup($vm);

        test_req_volatile($vm);

        test_ips($vm);

        test_volatile_clone_req($vm);
        test_volatile_clone($vm);

        test_old_machine($vm);
        test_old_machine_req($vm);

        test_volatile_clone($vm);
        test_enforce_limits($vm);
        test_internal_shutdown($vm);

    }
}

end();
done_testing();
