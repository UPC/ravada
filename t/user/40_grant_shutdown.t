#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

##############################################################################

sub test_shutdown_admin {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    $domain->start(user_admin)  if !$domain->is_active();

    is(user_admin->can_shutdown($domain->id), 1);
    is($domain->is_active,1)    or return;

    eval { $domain->shutdown( user => user_admin ) };
    is($@,'');

    $domain->start(user_admin)  if !$domain->is_active();
    is($domain->is_active,1)    or return;

    $domain->shutdown_now( user_admin );
    is($domain->is_active,0
        ,"[".$domain->type."] expecting domain down");

    $domain->remove(user_admin);
}

sub test_shutdown_own {
    my $vm = shift;

    my $user = create_user("kevin.garvey","sleepwalk");
    user_admin->grant($user,'create_machine');

    my $base = create_domain($vm->type, $user);
    $base->start(user_admin)  if !$base->is_active();

    # can shutdown by default
    is($user->can_remove_machine($base), 1);
    is($user->can_shutdown($base), 1);

    $base->shutdown_now( $user );

    is($base->is_active,0,"[".$base->type."] expecting base down");

    $base->remove( user_admin );

    $user->remove();

}

sub test_shutdown_all {
    my $vm = shift;

    my $base = create_domain($vm->type);
    $base->start(user_admin)    if !$base->is_active;
    is($base->is_active, 1) or BAIL_OUT();

    my $user = create_user("kevin.garvey","sleepwalk");

    is($user->can_shutdown($base), 0);

    eval { $base->shutdown_now( $user ) };
    like($@, qr'.');

    is($base->is_active, 1);

    user_admin->grant($user, 'shutdown_all');
    is($user->can_shutdown_all,1);

    $base->start(user_admin)    if !$base->is_active;

    is($user->can_shutdown($base), 1);
    eval { $base->shutdown_now( $user ) };
    is($@, '');

    $base->start(user_admin)    if !$base->is_active;

    is($user->can_shutdown($base), 1);
    eval { $base->hibernate( $user ) };
    is($@, '');

    $base->remove( user_admin );# if $base2;

    $user->remove();

}

sub test_shutdown_clones_from_own_base {
    my $vm = shift;

    my $user = create_user("kevin.garvey","sleepwalk");

    user_admin->grant($user, 'create_machine');
    my $base = create_domain($vm->type, $user);
    $base->start(user_admin)    if !$base->is_active;
    is($base->is_active, 1) or BAIL_OUT();
    $base->shutdown_now(user_admin);

    my $clone = $base->clone(
          name => new_domain_name
        , user => user_admin
    );
    $clone->start(user_admin);
    is($clone->is_active, 1);

    is($user->can_shutdown($clone->id), 0);

    user_admin->grant($user,'shutdown_clones');

    is($user->can_shutdown($clone->id), 1);
    is($user->is_operator,1);

    eval { $clone->shutdown_now($user)};
    is($@, '');
    is($clone->is_active, 0);

    $clone->start(user_admin)     if !$clone->is_active;
    eval { $clone->hibernate($user)};
    is($@, '');
    is($clone->is_hibernated, 1);

    eval { $clone->shutdown_now($user)};
    is($@, '');
    is($clone->is_active, 0);

    $clone->remove(user_admin);
    $base->remove(user_admin);

    $user->remove();

}

sub test_list_all{
    my $vm = shift;
    my $base = create_domain($vm->type);

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $user = create_user("kevin.garvey","sleepwalk");
    my $clone = $base->clone(
          name => new_domain_name
        , user => user_admin
    );
    $clone->start(user_admin)   if !$clone->is_active;

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'shutdown_all');
    is($user->can_list_machines, 1);
    is($user->is_operator, 1);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 2);

    for my $m (@$list) {
        is($user->can_shutdown($m->{id}) ,1);
        next if !$m->{id_base};

        my $machine = Ravada::Domain->open($m->{id});
        $machine->start(user_admin)     if !$machine->is_active;

        eval {$machine->shutdown_now($user)};
        is($@,'');
        is($machine->is_active, 0);

        $machine->start(user_admin)     if !$machine->is_active;
        eval {$machine->hibernate($user)};
        is($@,'');
        is($clone->is_hibernated, 1);
    }

    $user->remove();
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_list_clones_from_own_base {
    my $vm = shift;
    my $user = create_user("kevin.garvey","sleepwalk");

    user_admin->grant($user,'create_machine');
    my $base = create_domain($vm->type, $user);
    user_admin->revoke($user,'create_machine');

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $clone = $base->clone(
          name => new_domain_name
        , user =>user_admin
    );

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'shutdown_clones');
    is($user->can_list_machines, 0);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 2) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $clone->name, Dumper($list->[1]));
        is($list->[1]->{can_start}, 0, );
        is($list->[1]->{can_shutdown}, 1, );
    };

    $user->remove();
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_list_clones_from_own_base_2 {
    my $vm = shift;
    my $user = create_user("kevin.garvey","sleepwalk");

    user_admin->grant($user,'create_machine');
    my $base = create_domain($vm->type, $user);
    user_admin->revoke($user,'create_machine');

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $clone = $base->clone(
          name => new_domain_name
        , user =>user_admin
    );

    my $clone2 = $base->clone(
          name => new_domain_name
        , user =>user_admin
    );

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'shutdown_clones');
    is($user->can_list_machines, 0);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 3) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $clone->name, Dumper($list->[1]));
        is($list->[1]->{can_shutdown}, 1);
        is($list->[2]->{name}, $clone2->name, Dumper($list->[2]));
        is($list->[2]->{can_shutdown}, 1);
    };

    #####################################################################3
    #
    # another base
    user_admin->grant($user,'create_machine');
    my $base2 = create_domain($vm->type, $user);
    user_admin->revoke($user,'create_machine');
    $base2->prepare_base(user_admin);
    $base2->is_public(1);

    my $clone3 = $base2->clone(
          name => new_domain_name
        , user =>user_admin
    );
    $list = rvd_front->list_machines($user);
    is(scalar @$list , 5) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $clone->name);
        is($list->[2]->{name}, $clone2->name);
        is($list->[3]->{name}, $base2->name);
        is($list->[4]->{name}, $clone3->name);
    };

    for my $m (@$list) {
        next if !exists $m->{id_base} || !$m->{id_base};

        my $machine = $vm->search_domain($m->{name});
        $machine->start(user_admin) if !$machine->is_active;
        is($machine->is_active, 1);

        eval { $machine->shutdown_now($user) };
        is($@,'');
        is($machine->is_active, 0);
        $machine->remove(user_admin);
    }

    $user->remove();
    $base->remove(user_admin);
    $base2->remove(user_admin);
}

sub test_list_clones_from_own_base_deny {
    # User can't list becase base is not his
    my $vm = shift;
    my $user = create_user("kevin.garvey","sleepwalk");

    my $base = create_domain($vm->type);

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $clone = $base->clone(
          name => new_domain_name
        , user =>user_admin
    );
    $clone->start(user_admin)   if !$clone->is_active;

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'shutdown_clones');
    is($user->can_list_machines, 0);
    is($user->can_list_clones_from_own_base, 1);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    is($user->can_manage_machine($base->id), 0);
    is($user->can_manage_machine($clone->id), 0);

    eval { $clone->shutdown_now($user)};
    like($@,qr'.');
    is($clone->is_active, 1);

    $user->remove();
    $clone->remove(user_admin);
    $base->remove(user_admin);
}


##############################################################################

clean();

use_ok('Ravada');

for my $vm_name ( vm_names() ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing shutdown on $vm_name");

        test_shutdown_admin($vm);
        test_shutdown_own($vm);
        test_shutdown_all($vm);
        test_shutdown_clones_from_own_base($vm);

        test_list_all($vm);
        test_list_clones_from_own_base($vm);
        test_list_clones_from_own_base_2($vm);
        test_list_clones_from_own_base_deny($vm);

    }
}

end();
done_testing();
