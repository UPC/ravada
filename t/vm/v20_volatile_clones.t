use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

use_ok('Ravada');

use lib 't/lib';
use Test::Ravada;

init();

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
    rvd_back->_process_requests_dont_fork();

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

    $clone->start(user_admin)   if !$clone->is_active;

    is($clone->is_active, 1) && do {

        my $clonef = Ravada::Front::Domain->open($clone->id);
        ok($clonef);
        isa_ok($clonef, 'Ravada::Front::Domain');
        is($clonef->is_active, 1);
        like($clonef->display(user_admin),qr'.');
        like($clone->remote_ip,qr(.)) or exit;
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
        is($req->error, undef);
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

    eval { $clone->remove(user_admin) if !$clone->is_removed() };
    is(''.$@,'');
    $domain->remove(user_admin);

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

    my @volumes = $clone->list_volumes();

    shutdown_domain_internal($clone);

    rvd_back->_cmd_refresh_vms();

    my $clone0_f;
    eval { $clone0_f = rvd_front->search_domain($clone_name) };
    is($clone0_f, undef);

    my $list_domains = rvd_front->list_domains();
    ($clone0_f) = grep { $_->{name} eq $clone_name } @$list_domains;
    is($clone0_f, undef);

    for my $vol ( @volumes ) {
        ok(!-e $vol,"Expecting $vol removed");
    }

    my $domain2 = rvd_back->search_domain($clone_name);
    ok(!$domain2,"[".$vm->type."] expecting domain $clone_name removed");

    $domain2->remove(user_admin)    if $domain2;

    $user->remove();
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

        test_volatile_clone_req($vm);
        test_volatile_clone($vm);

        test_old_machine($vm);
        test_old_machine_req($vm);

        test_volatile_clone($vm);
        test_enforce_limits($vm);
        test_internal_shutdown($vm);

    }
}

clean();

done_testing();
