use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use feature qw(signatures);
no warnings "experimental::signatures";


use_ok('Ravada');

my @VMS = vm_names();
init();

#########################################################3

sub test_defaults {
    my $user= create_user("foo","bar");
#    my $rvd_back = rvd_back();

    ok($user->can_clone);
    ok($user->can_change_settings);
#    ok($user->can_screenshot);

    ok($user->can_remove);

    ok(!$user->can_remove_clones);

#    ok(!$user->can_clone_all);
    ok(!$user->can_change_settings_all);
    ok(!$user->can_change_settings_clones);


    is($user->can_screenshot, 1);
#    ok(!$user->can_screenshot_all);
    ok(!$user->can_grant);

    ok(!$user->can_create_base);
    ok(!$user->can_create_machine);
#    ok(!$user->can_remove_all);
    ok(!$user->can_remove_clone_all);

#    ok(!$user->can_shutdown_clone);
    ok(!$user->can_shutdown_all);

#    ok(!$user->can_hibernate_clone);
#    ok(!$user->can_hibernate_all);
#    ok(!$user->can_hibernate_clone_all);
    
    ok(!$user->can_manage_users);

    for my $perm (user_admin->list_permissions) {
        $perm = $perm->[0];
        if ( $perm =~ m{^(clone|change_settings|screenshot|remove|shutdown|reboot)$}) {
            is($user->can_do($perm),1,$perm);
        } else {
            is($user->can_do($perm),undef,$perm);
        }
    }

    my %grants = $user->grants();
    my %grants_info = $user->grants_info();
    for my $key ( keys %grants ) {
        is($grants_info{$key}->[0],$grants{$key}, $key);
        if ($key eq 'start_limit' || $key =~ /^quota/) {
            is($grants_info{$key}->[1],"int" , $key);
        } else {
            is($grants_info{$key}->[1],"boolean" , $key);
        }
    }


    $user->remove();
}

sub test_admin {
    my $user = create_user(new_domain_name()." foo$$","bar",1);
    ok($user->is_admin);
    for my $perm ($user->list_all_permissions) {
        if ($perm->{name} eq 'start_limit') {
            is($user->can_do($perm->{name}),undef,$perm->{name});
            next;
        }
        is($user->can_do($perm->{name}),1,$user->name." ".$perm->{name}) or exit;
    }
    $user->remove();
}

sub test_grant {
    my $user = create_user("bar$$","bar",1);
    ok($user->is_admin);
    for my $perm ($user->list_all_permissions) {
        user_admin()->grant($user,$perm->{name});
        ok($user->can_do($perm->{name}));
        user_admin()->grant($user,$perm->{name});
        ok($user->can_do($perm->{name}));

        user_admin()->revoke($user,$perm->{name});
        is($user->can_do($perm->{name}),0, $perm->{name}) or exit;
        user_admin()->revoke($user,$perm->{name});
        is($user->can_do($perm->{name}),0, $perm->{name}) or exit;

        user_admin()->grant($user,$perm->{name});
        ok($user->can_do($perm->{name}));
        user_admin()->revoke($user,$perm->{name});
        is($user->can_do($perm->{name}),0, $perm->{name});

    }

    $user->remove();
}

sub test_alias {
    my @list_permissions = user_admin->list_permissions;
    my @list_all_permissions = user_admin->list_all_permissions;

    my $sth = connector->dbh->prepare("SELECT name, alias FROM grant_types_alias");
    $sth->execute;
    while ( my ($name, $alias) = $sth->fetchrow) {
        eval { is(user_admin->can_do($name),1, $name) };
        is($@,'',$name);

        eval { is(user_admin->can_do($alias),1, $alias) };
        is($@,'',$alias);

        ok(grep({ $_->[0] eq $alias } @list_permissions), $alias);
        ok(grep({ $_->{name} eq $alias } @list_all_permissions), $alias);
    }

}

sub test_operator {
    my $usero = create_user("oper$$","bar");
    ok(!$usero->is_operator);
    ok(!$usero->is_admin);

    my $usera = create_user("admin$$","bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);

    $usera->grant($usero,'shutdown_clones');
    ok($usero->is_operator);
    ok(!$usero->is_admin);

    $usero->remove();
    $usera->remove();
}

sub test_remove_clone {
    my $vm_name = shift;

    my $user = create_user("oper_rm$$","bar");
    my $usera = create_user("admin_rm$$","bar",'is admin');

    $usera->grant($user, 'create_machine');
    my $domain = create_domain($vm_name, $user);
    $domain->prepare_base($usera);
    ok($domain->is_base) or return;

    my $clone = $domain->clone(user => $usera,name => new_domain_name());
    eval { $clone->remove($user); };
    like($@,qr(.));

    my $clone2;
    eval { $clone2 = rvd_back->search_domain($clone->name) };
    ok($clone2, "Expecting ".$clone->name." not removed");

    $usera->grant($user,'remove_clones');
    is($user->can_remove_clones, 1);
    eval { $clone->remove($user); };
    is($@,'');

    eval { $clone2 = rvd_back->search_domain($clone->name) };
    ok(!$clone2, "Expecting ".$clone->name." removed");

    # revoking remove clone permission

    $clone = $domain->clone(user => $usera,name => new_domain_name());
    $usera->revoke($user,'remove_clones');

    eval { $clone->remove($user); };
    like($@,qr(.));

    eval { $clone2 = rvd_back->search_domain($clone->name) };
    ok($clone2, "Expecting ".$clone->name." not removed");

    $clone->remove($usera);
    $domain->remove($usera);
    for my $clone3 ( $domain->clones ) {
        $clone3->remove($usera);
    }

    $user->remove();
    $usera->remove();
}

sub test_view_clones {
    my $vm_name = shift;
    my $user = create_user("oper_rm$$.".time,"bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);
    my $usera = create_user("admin_rm$$.".time,"bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);
    
    my $domain = create_domain($vm_name, $usera);
    $domain->prepare_base($usera);
    ok($domain->is_base) or return;
    
    my $clones;
    eval{ $clones = rvd_front->list_clones() };
    is($@,'');
    is(scalar @$clones,0, Dumper($clones)) or return;
    
    my $clone = $domain->clone(user => $usera,name => new_domain_name());
    eval{ $clones = rvd_front->list_clones() };
    is(scalar @$clones, 1) or return;
    
    $clone->prepare_base($usera);
    eval{ $clones = rvd_front->list_clones() };
    is(scalar @$clones, 1) or return;

    $clone->remove(user_admin);
    $domain->remove(user_admin);

    $usera->remove();
    $user->remove();
}

sub test_shutdown_clone {
    my $vm_name = shift;

    my $user = create_user("oper$$","bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);

    my $usera = create_user("admin$$","bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);

    $usera->grant($user, 'create_machine');
    my $domain = create_domain($vm_name, $user);
    $domain->prepare_base($usera);
    ok($domain->is_base) or return;

    my $clone = $domain->clone(user => $usera,name => new_domain_name());
    $clone->start($usera)   if !$clone->is_active;

    is($clone->is_active,1) or return;

    eval { $clone->shutdown_now($user); };
    like($@,qr(.));
    is($clone->is_active,1);

    is($clone->is_active,1) or return;

    $usera->grant($user,'shutdown_clones');
    is($user->can_shutdown_clones,1);

    eval { $clone->shutdown_now($user); };
    is($@,'');
    is($clone->is_active,0);


    $clone->start($usera)   if !$clone->is_active;
    is($clone->is_active,1);

    $usera->revoke($user,'shutdown_clones');
    eval { $clone->shutdown_now($user); };
    like($@,qr(.));
    is($clone->is_active,1);

    $clone->remove($usera);
    $domain->remove($user);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->start($user);
    $domain2->shutdown_now($user);
    $domain2->remove($user);

    $user->remove();
    $usera->remove();
}

sub test_remove {
    my $vm_name = shift;

    my $user = create_user("oper_r$$.$vm_name","bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);

    user_admin()->revoke($user,'remove');
    user_admin()->grant($user,'create_machine');

    is($user->can_remove,0) or return;

    # user can't remove own domains
    my $domain = create_domain($vm_name, $user);
    eval { $domain->remove($user)};
    like($@,qr'.');

    # user can't remove domains from others
    my $domain2 = create_domain($vm_name, user_admin());
    eval { $domain2->remove($user)};
    like($@,qr'.');

    # user is granted remove
    user_admin()->grant($user,'remove');
    eval { $domain->remove($user)};
    is($@,'');

    # but can't remove domains from others
    eval { $domain2->remove($user)};
    like($@,qr'.');

    # admin can remove the domain
    eval { $domain2->remove(user_admin())};
    is($@,'');

    $user->remove();
}

sub test_shutdown_all {
    my $vm_name = shift;

    my $user = create_user("oper_sa$$","bar");
    is($user->can_shutdown_all,undef) or return;

    my $usera = create_user("admin_sa$$","bar",1);
    is($usera->can_shutdown_all,1);

    my $domain = create_domain($vm_name, $usera);
    $domain->start($usera)      if !$domain->is_active;
    is($domain->is_active,1)    or return;

    eval { $domain->shutdown_now($user)};
    like($@,qr'.');
    is($domain->is_active,1)    or return;

    $usera->grant($user,'shutdown_all');
    is($user->can_shutdown_all,1) or return;

    eval { $domain->shutdown_now($user)};
    is($@,'');

    is($domain->is_active,0);

    # revoke the grant
    $domain->start($usera)      if !$domain->is_active;
    is($domain->is_active,1);

    $usera->revoke($user,'shutdown_all');
    eval { $domain->shutdown_now($user)};
    like($@,qr'.');
    is($domain->is_active,1);

    $domain->remove($usera);
    $user->remove();
    $usera->remove();
}

sub test_remove_clone_all {
    my $vm_name = shift;
    my $user = create_user("oper_rca$$","bar");
    is($user->can_remove_clone_all(),undef) or return;
    is($user->is_operator, 0);

    my $usera = create_user("admin_rca$$","bar",1);
    is($usera->can_remove_clone_all(),1) or return;

    my $domain = create_domain($vm_name, $usera);
    my $clone_name = new_domain_name();

    my $clone = $domain->clone(user => $usera, name => $clone_name);

    eval { $clone->remove($user); };
    like($@,qr'.');

    my $clone2 = rvd_back->search_domain($clone_name);
    ok($clone2,"[$vm_name] domain $clone_name shouldn't be removed") or return;

    $usera->grant($user,'remove_clone_all');
    is($user->can_remove_clone_all(),1);
    is($user->is_operator,1);

    eval { $clone->remove($user); };
    is($@,'');
    
    my $domain2 = create_domain($vm_name, $usera);
    eval { $domain2->remove($user); };
    like($@,qr'.');
    
    $clone2 = rvd_back->search_domain($clone_name);
    ok(!$clone2,"[$vm_name] domain $clone_name must be removed") or return;

    $clone_name = new_domain_name();
    $clone = $domain->clone(user => $usera, name => $clone_name);

    my $other_domain = create_domain($vm_name);
    ok($other_domain);

    is($user->is_admin, 0);
    is($user->can_list_clones, 1);
    my $list = rvd_front->list_machines($user);
    is(scalar@$list,4);
    ok( grep { $_->{name} eq $other_domain->name } @$list);

    $usera->revoke($user,'remove_clone_all');

    eval { $clone->remove($user); };
    like($@,qr'.');
    $clone2 = rvd_back->search_domain($clone_name);
    ok($clone2,"[$vm_name] domain $clone_name shouldn't be removed") or return;

    $clone->remove($usera);
    $domain->remove($usera);
    $domain2->remove($usera);
    $other_domain->remove($usera);

    $user->remove();
    $usera->remove();
}

sub test_prepare_base {
    my $vm_name = shift;

    my $user = create_user("oper_pb$$","bar");
    my $usera = create_user("admin_pb$$","bar",1);

    $usera->grant($user, 'create_machine');

    my $domain = create_domain($vm_name, $user);
    is($domain->is_base,0) or return;

    eval{ $domain->prepare_base($user) };
    like($@,qr'.');
    is($domain->is_base,0);
    $domain->remove($usera);

    $domain = create_domain($vm_name, $user);

    $usera->grant($user,'create_base');

    is($user->is_operator, 1);
    is($user->can_list_own_machines, 1);

    is($user->can_create_base,1);
    eval{ $domain->prepare_base($user) };
    is($@,'');
    is($domain->is_base,1);
    $domain->is_public(1);

    my $clone;
    eval { $clone = $domain->clone(user=>$user, name => new_domain_name) };
    is($@, '');
    ok($clone);

    $usera->revoke($user,'create_base');
    is($user->can_create_base,0);

    eval { $clone->prepare_base() };
    like($@,qr'.');
    is($clone->is_base,0);

    $clone->remove($usera);
    $domain->remove($usera);

    $usera->remove();
    $user->remove();

}

sub test_frontend {
    my $vm_name = shift;

    my $user = create_user("oper_pb$$","bar");
    my $usera = create_user("admin_pb$$","bar",1);

    my $domain = create_domain($vm_name, $usera );
    $domain->prepare_base( $usera );
    $domain->is_public( $usera );

    my $clone = $domain->clone( user => $user, name => new_domain_name );
    is($user->can_list_machines, 0);
    is($user->can_list_own_machines, 0);

    $usera->grant($user, 'create_base');
    is($user->can_list_machines, 0);
    is($user->can_list_own_machines, 1);

    my $list_domains = rvd_front->list_domains( id_owner => $user->id );
    is (scalar @$list_domains, 1 );
    ok($list_domains->[0]->{name} eq $clone->name);

    my $list_machines = rvd_front->list_machines( $user );
    is (scalar @$list_machines, 2 );
    if (defined $list_machines->[1]) {
        ok($list_machines->[1]->{name} eq $clone->name);
        is($list_machines->[1]->{can_manage}, 1);
        is($list_machines->[0]->{can_manage}, 0);
    }

    $usera->revoke($user, 'create_base');
    is($user->can_list_machines, 0);
    is($user->can_list_own_machines, 0);

    $usera->grant($user, 'create_machine');
    is($user->can_list_machines, 0);
    is($user->can_list_own_machines, 1);

    $list_machines = rvd_front->list_domains( id_owner => $user->id );
    is (scalar @$list_machines, 1 );

    my $domain_other = create_domain($vm_name, $user);
    $list_machines = rvd_front->list_domains( id_owner => $user->id );
    is (scalar @$list_machines, 2 );

    $clone->remove( $usera );
    $domain->remove( $usera );
    $domain_other->remove( $usera );

    $usera->remove;
    $user->remove;
}

sub test_create_domain {
    my $vm_name = shift;

    diag("test create domain");

    my $vm = rvd_back->search_vm($vm_name);

    my $user = create_user("oper_cr$$","bar");
    my $usera = create_user("admin_cr$$","bar",1);

    my $base = create_domain($vm_name);
    $base->prepare_base($usera);
    $base->is_public(1);

    $usera->revoke($user,'create_machine');
    is($user->can_create_machine, undef) or return;
    is($user->can_clone,1) or return;

    my $domain_name = new_domain_name();

    my %create_args = (
            id_iso => search_id_iso('alpine')
            ,id_owner => $user->id
            ,name => $domain_name
            ,disk => 1024 * 1024
   );


    my $domain;
    eval { $domain = $vm->create_domain(%create_args)};
    like($@,qr'not allowed'i);

    my $domain2 = $vm->search_domain($domain_name);
    ok(!$domain2);
    eval { $domain2->remove($usera)    if $domain2 };
    is($@,'');

    my $clone;
    my $clone_name = new_domain_name();
    eval { $clone = $base->clone(name => $clone_name, user => $user) };
    is($@,'');
    ok($clone, "Expecting can clone, but not create");

    eval { $clone->remove($usera)    if $clone };
    is($@,'');

    $usera->grant($user,'create_machine');
    is($user->can_create_machine,1) or return;

    $domain_name = new_domain_name();
    $create_args{name} = $domain_name;
    eval { $domain = $vm->create_domain(%create_args)};
    is($@,'');

    my $domain3 = $vm->search_domain($domain_name);
    ok($domain3);

    is($user->can_change_settings($domain3),1);

    my $list_machines = rvd_front->list_machines($user);
    is (scalar @$list_machines, 1 );

    eval { $domain3->remove($usera)  if $domain3 };
    is($@,'');

    eval { $domain->remove($usera)   if $domain->is_known() };
    is($@,'');

    eval { $base->remove($usera)   if $domain };
    is($@,'');

    $base->remove(user_admin)   if !$base->is_removed;
    $clone->remove(user_admin) if !$clone->is_removed;
    $domain->remove(user_admin) if !$domain->is_removed;

    $user->remove();
    $usera->remove();
    diag("done  test create");
}

sub test_grant_clone {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $user = create_user("oper_c$$","bar");

    is($user->can_clone,1) or return;

    my $usera = create_user("admin_c$$","bar",1);
    is($usera->can_clone,1);
    my $domain = create_domain($vm_name, $usera);
    $domain->prepare_base($usera);
    ok($domain->is_base);
    is($domain->is_public,0) or return;

    my $clone_name = new_domain_name();
    my $clone;
    eval { $clone = $domain->clone(name => $clone_name, user => $user)};
    like($@,qr(.));

    my $clone2 = $vm->search_domain($clone_name);
    is($clone2,undef);

    $domain->is_public(1);
    is($domain->is_public,1) or return;

    $clone_name = new_domain_name();
    my $cloneb;
    eval { $cloneb = $domain->clone(name => $clone_name, user => $user)};
    is($@,'');
    ok($cloneb,"Expecting $clone_name exists");

    $clone2 = $vm->search_domain($clone_name);
    ok($clone2,"Expecting $clone_name exists");

    $clone->remove($usera)  if $clone;
    $cloneb->remove($usera) if $cloneb;

    eval { $domain->remove($usera) };
    is($@,'',"Remove base domain");

    $user->remove();
    $usera->remove();
}

sub test_create_domain2 {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $user = create_user("oper_c$$","bar");
    my $usera = create_user("admin_c$$","bar",1);

    is($user->can_create_machine, undef) or return;

    my $domain_name = new_domain_name();
    my $domain;
    eval { $domain = $vm->create_domain(name => $domain_name, id_owner => $user->id
            ,disk => 1024 * 1024 )};
    like($@,qr'not allowed');

    my $domain2 = $vm->search_domain($domain_name);
    ok(!$domain2);
    $domain2->remove($usera)    if $domain2;

    $usera->grant($user, 'create_machine');
    is($user->can_create_machine,1) or return;

    $domain_name = new_domain_name();
    eval { $domain = $vm->create_domain(name => $domain_name, id_owner => $user->id
        , disk => 1024 * 1024
        , id_iso => search_id_iso('alpine'))};
    is($@,'');

    my $domain3 = $vm->search_domain($domain_name);
    ok($domain3);
    $domain3->remove(user_admin)    if $domain3;
    $domain2->remove(user_admin)    if $domain2;
    $domain->remove(user_admin)    if $domain;

    $user->remove();
    $usera->remove();
}

sub test_expose_ports($vm_name) {
    my $vm = rvd_back->search_vm($vm_name);

    my $user = create_user("oper_cs$$","bar");
    my $usera = create_user("admin_cs$$","bar",1);

    is($user->can_expose_ports(), undef);
    is($usera->can_expose_ports(), 1);

    is($user->can_expose_ports_clones(), undef);
    is($usera->can_expose_ports_clones(), 1);


    my $base = create_domain($vm_name, $usera);
    $base->prepare_base(user_admin);
    $base->is_public(1);
    my $req =Ravada::Request->clone( id_domain => $base->id
        ,uid => $user->id
    );
    wait_request();
    my ($domain_d) = $base->clones;
    my $domain = Ravada::Domain->open($domain_d->{id});

    is($user->can_expose_ports($domain->id), 0);
    is($usera->can_expose_ports($domain->id), 1);

    my %args = (
                        'id_domain' => $domain->id
                        ,'port' => 22
                        ,'name' => 'ssh'
    );
    $req = Ravada::Request->expose(%args, uid => $user->id);
    wait_request(check_error => 0);
    like($req->error,qr'access denied'i);

    $req = Ravada::Request->expose(%args, uid => $usera->id);
    wait_request($req);
    is($req->error,'');

    Ravada::Request->clone(id_domain => $base->id
        ,uid => $usera->id
    );
    wait_request();
    my ($domain_da) = grep { $_->{id_owner} == $usera->id } $base->clones;
    $req = Ravada::Request->expose(id_domain=> $domain_da->{id}
        ,uid => $user->id
        ,port => 22
    );
    wait_request(check_error => 0);
    like($req->error,qr'access denied'i);

    remove_domain($base);
    $user->remove();
    $usera->remove();


}

sub test_change_settings($vm_name) {
    my $vm = rvd_back->search_vm($vm_name);

    my $user = create_user("oper_cs$$","bar");
    my $usera = create_user("admin_cs$$","bar",1);

    # settings grant on fresh users ###########################################

    is($user->can_change_settings(), 1);
    is($usera->can_change_settings(), 1);

    is($user->can_change_settings_all(), undef);
    is($usera->can_change_settings_all(), 1);

    is($user->can_change_settings_clones(), undef);
    is($usera->can_change_settings_clones(), 1);

    # settings grant on domain owned by admin ##################################

    my $domain = create_domain($vm_name, $usera);

    is($user->can_change_settings($domain->id), 0);
    is($usera->can_change_settings($domain->id), 1);

    # settings grant on clone owned by user ##################################

    $domain->prepare_base($usera);
    $domain->is_public(1);
    my $clone = $domain->clone( name => new_domain_name, user => $user );

    is($user->can_change_settings($clone->id), 1);
    is($usera->can_change_settings($clone->id), 1);

    $usera->revoke($user,'change_settings');
    is($user->can_change_settings(), 0);
    is($user->can_change_settings($clone->id), 0);

    $clone->remove(user_admin);
    $domain->remove(user_admin);

    $user->remove();
    $usera->remove();

}

sub test_grant_grant {
    my $usero = create_user("oper$$","bar");
    is($usero->can_grant, undef);

    user_admin->grant($usero,'grant');
    is($usero->can_grant,1);

    is($usero->is_operator,1);

    $usero->remove();
}

sub test_clone_all {
    diag("TODO test clone all");
}

sub test_start_many{
    my $user = create_user("oper_start","bar");
    my $usera = create_user("admin_start","bar",'is admin');
    is($user->can_start_many,undef);
    is($usera->can_start_many,1);

    is($user->can_start_limit,undef);
    is($usera->can_start_limit,undef);

    $user->remove();
    $usera->remove();
}

sub test_start_limit_upgrade{
    my $sth = connector->dbh->prepare("SELECT id FROM grant_types WHERE name='start_limit'");
    $sth->execute();
    my ($id) = $sth->fetchrow;

    $sth = connector->dbh->prepare("DELETE FROM grants_user WHERE id_grant=?");
    $sth->execute($id);

    $sth = connector->dbh->prepare("DELETE FROM grant_types WHERE id=?");
    $sth->execute($id);

    my $user = create_user("oper_start","bar");
    my $usera = create_user("admin_start","bar",'is admin');
    rvd_back->{_null_grants}=0;
    rvd_back->_install();
    is($user->can_start_limit,0);
    is($usera->can_start_limit,0);

    $user->remove();
    $usera->remove();
}

sub test_view_all_upgrade
{
    my $sth = connector->dbh->prepare("SELECT id FROM grant_types WHERE name='view_all'");
    $sth->execute();
    my ($id) = $sth->fetchrow;

    $sth = connector->dbh->prepare("DELETE FROM grants_user WHERE id_grant=?");
    $sth->execute($id);

    $sth = connector->dbh->prepare("DELETE FROM grant_types WHERE id=?");
    $sth->execute($id);

    my $user = create_user("oper_start","bar");
    my $usera = create_user("admin_start","bar",'is admin');
    rvd_back->{_null_grants}=0;
    rvd_back->_install();
    is($user->can_view_all,0);
    is($usera->can_view_all,1);

    $user->remove();
    $usera->remove();
}

sub test_start_many_upgrade{
    my $user = create_user("oper_startm","bar");
    my $usera = create_user("admin_startm","bar",1);
    my $sth = connector->dbh->prepare("SELECT id FROM grant_types WHERE name='start_many'");
    $sth->execute();
    my ($id) = $sth->fetchrow;

    $sth = connector->dbh->prepare("DELETE FROM grants_user WHERE id_grant=?");
    $sth->execute($id);

    $sth = connector->dbh->prepare("DELETE FROM grant_types WHERE id=?");
    $sth->execute($id);

    rvd_back->{_null_grants}=0;
    rvd_back->_install();

    $user->_reload_grants();
    $usera->_reload_grants();
    is($user->can_start_many,0);
    is($usera->can_start_many,1);

    $user->remove();
    $usera->remove();
}

sub test_view_all($vm) {
    my $domain;
    if ($vm->type eq 'KVM') {
        my $base = import_domain($vm);
        $domain = $base->clone(name => new_domain_name, user => user_admin);
    } else {
        $domain = create_domain($vm);
    }
    $domain->expose(22);
    my $user = create_user();
    user_admin->grant($user,'view_all');
    my $req_start = Ravada::Request->start_domain(
        uid => $user->id
        ,id_domain => $domain->id
        ,remote_ip => '192.0.2.1'
    );
    my $req_prepare = Ravada::Request->prepare_base(
        uid => $user->id
        ,id_domain => $domain->id
    );
    my $req_remove = Ravada::Request->remove_domain(
        uid => $user->id
        ,name => $domain->name
    );
    my $req_refresh = Ravada::Request->refresh_machine(
        uid => $user->id
        ,id_domain => $domain->id
    );
    wait_request( check_error => 0, debug => 0);
    my $req_start_admin = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => '192.0.2.1'
    );
    wait_request();

    my $req_refresh_ports = Ravada::Request->refresh_machine_ports(
        uid => $user->id
        ,id_domain => $domain->id
        ,after_request => $req_start_admin->id
    );

    my $req_shutdown= Ravada::Request->shutdown_domain(
        uid => $user->id
        ,id_domain => $domain->id
        ,after_request => $req_start_admin->id
    );
    wait_request(check_error => 0, debug => 0);

    my $req_prepare_admin = Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    my $req_remove_base = Ravada::Request->remove_base(
        uid => $user->id
        ,id_domain => $domain->id
    );

    wait_request( check_error => 0, debug => 0);
    for my $req ($req_prepare, $req_remove_base, $req_shutdown) {
        is($req->status,'done');
        like($req->error,qr'User.* (can.t |not allowed)', $req->command);
    }
    for my $req ( $req_start_admin, $req_prepare_admin, $req_start
    ,$req_refresh, $req_refresh_ports) {
        diag($req->command);
        is($req->status,'done');
        next if $req->command =~ /refresh_machine_ports/i;
        is($req->error,'', $req->command) or exit;
    }

    $domain->remove(user_admin);
}

##########################################################

test_start_many();
test_start_limit_upgrade();
test_start_many_upgrade();

test_view_all_upgrade();

test_defaults();
test_admin();
test_grant();

test_alias();

test_grant_grant();

test_operator();

clean();

for my $vm_name (vm_names()) {
    next if $vm_name eq 'KVM' && $>;

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };
    diag($@) if $@;
    next if !$vm;

    diag("Testing VM $vm_name");
    test_view_all($vm);
    test_expose_ports($vm_name);
    test_change_settings($vm_name);

    test_shutdown_clone($vm_name);
    test_shutdown_all($vm_name);

    test_remove($vm_name);
    test_remove_clone($vm_name);
    #test_remove_all($vm_name);

    test_remove_clone_all($vm_name);

    test_prepare_base($vm_name);
    test_frontend($vm_name);
    test_create_domain($vm_name);
    test_create_domain2($vm_name);
    test_view_clones($vm_name);

    test_prepare_base($vm_name);
    test_frontend($vm_name);
    test_create_domain($vm_name);
    test_create_domain2($vm_name);
    test_view_clones($vm_name);
    test_clone_all($vm_name);

}
end();
done_testing();
