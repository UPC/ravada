#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector);

##############################################################################

sub test_remove_admin {
    my $vm = shift;

    my $domain = create_domain($vm->type);

    is(user_admin->can_remove_machine($domain->id), 1);
    $domain->remove( user_admin );

    my $domain2 = $vm->search_domain( $domain->name );
    ok(!$domain2,"[".$domain->type."] expecting domain already removed");

}

sub test_remove_own_clone {
    my $vm = shift;

    my $base = create_domain($vm->type);

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $user = create_user("kevin.garvey","sleepwalk");
    my $clone = $base->clone(
          name => new_domain_name
        , user => $user
    );

    # can remove by default
    is($user->can_remove_machine($clone), 1);
    $clone->remove( $user );

    my $clone2 = $vm->search_domain( $clone->name );
    ok(!$clone2,"[".$base->type."] expecting clone already removed");

    $clone = $base->clone(
          name => new_domain_name
        , user => $user
    );

    # revoked grant can't remove
    user_admin->revoke($user, 'remove');
    is($user->can_remove_machine($clone), 0);

    eval { $clone->remove( $user ); };
    like($@,qr'.');

    $clone2 = $vm->search_domain( $clone->name );
    ok($clone2,"[".$base->type."] expecting clone not removed");

    # grant remove again
    user_admin->grant($user, 'remove');
    is($user->can_remove_machine($clone), 1);

    eval { $clone->remove( $user ); };
    is($@,'');

    $clone2 = $vm->search_domain( $clone->name );
    ok(!$clone2,"[".$base->type."] expecting clone removed");

    # done
    $base->remove( user_admin );
    my $base2 = $vm->search_domain( $base->name );
    ok(!$base2,"[".$base->type."] expecting domain already removed");

    $user->remove();

}

sub test_remove_all {
    my $vm = shift;

    my $base = create_domain($vm->type);

    my $user = create_user("kevin.garvey","sleepwalk");
    is($user->can_remove_machine($base), 0);
    eval { $base->remove( $user ) };
    like($@, qr'.');

    my $base2 = $vm->search_domain( $base->name );
    ok($base2,"[".$base->type."] expecting base not removed");

    user_admin->grant($user, 'remove_all');
    is($user->can_remove_machine($base), 1);
    eval { $base->remove( $user ) };
    is($@, '');

    $base2 = $vm->search_domain( $base->name );
    ok(!$base2,"[".$base->type."] expecting base removed");

    $base->remove( user_admin ) if $base2;

    $user->remove();

}

sub test_remove_others_clone {
    my $vm = shift;
    my $base = create_domain($vm->type);

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $user = create_user("kevin.garvey","sleepwalk");
    my $clone = $base->clone(
          name => new_domain_name
        , user => user_admin
    );

    is($user->can_remove_machine($clone), 0);
    eval { $clone->remove( $user ) };

    my $clone2 = $vm->search_domain( $clone->name );
    ok($clone2,"[".$base->type."] expecting clone already there");

    user_admin->grant($user, 'remove_clone_all');

    is($user->can_remove_clone_all,1);
    eval { $clone->remove($user)};
    is($@, '');

    $clone2 = $vm->search_domain( $clone->name );
    ok(!$clone2,"[".$base->type."] expecting clone removed");

    $clone->remove( user_admin )    if $clone2;
    $base->remove( user_admin );

    $user->remove();

}

sub test_remove_clones_from_own_base {
    my $vm = shift;
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

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'remove_all');
    is($user->can_list_machines, 1);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 2);

    $user->remove();
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_list_clones_from_own_base {
    my $vm = shift;
    my $user = create_user("kevin.garvey","sleepwalk");

    user_admin->grant($user,'create_machine');
    my $base = create_domain($vm->type, $user);

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $clone = $base->clone(
          name => new_domain_name
        , user =>user_admin
    );

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'remove_clone');
    is($user->can_list_machines, 0);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 2) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $clone->name, Dumper($list->[1]));
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

    user_admin->grant($user, 'remove_clone');
    is($user->can_list_machines, 0);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 3) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $clone->name, Dumper($list->[1]));
        is($list->[2]->{name}, $clone2->name, Dumper($list->[2]));
    };

    #####################################################################3
    #
    # another base
    my $base2 = create_domain($vm->type, $user);
    $base2->prepare_base(user_admin);
    $base2->is_public(1);

    my $clone3 = $base2->clone(
          name => new_domain_name
        , user =>user_admin
    );
    $list = rvd_front->list_machines($user);
    is(scalar @$list , 5) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $base2->name);
        is($list->[2]->{name}, $clone->name, Dumper($list->[2]));
        is($list->[3]->{name}, $clone2->name, Dumper($list->[3]));
        is($list->[4]->{name}, $clone3->name, Dumper($list->[4]));
    };

    for my $m (@$list) {
        is($user->can_manage_machine($m->{id}), 1);
        next if !$m->{id_base};

        my $machine = $vm->search_domain($m->{name});
        eval { $machine->remove($user) };
        is($@,'');

        my $machine_d = $vm->search_domain($machine->name);
        ok(!$machine_d);
        $machine->remove(user_admin)    if $machine_d;
    }

    $user->remove();
    $base->remove(user_admin);
    $base2->remove(user_admin);
}

sub test_list_others_clone {
    my $vm = shift;

    my $base = create_domain($vm->type );

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $user = create_user("kevin.garvey","sleepwalk");
    my $clone = $base->clone(
          name => new_domain_name
        , user =>user_admin
    );

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'remove_clone_all');
    is($user->can_list_machines, 0);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 2 ) and do {
        is($list->[0]->{name}, $base->name);
        is($list->[1]->{name}, $clone->name, Dumper($list->[1]));
    };
    is($user->can_manage_machine($base->id), 0);
    is($user->can_manage_machine($clone->id), 1);

    eval { $clone->remove($user) };
    is($@ , '');

    my $clone_d = $vm->search_domain($clone->name);
    ok(!$clone_d);

    $user->remove();
    $clone->remove(user_admin)  if $clone_d;
    $base->remove(user_admin);
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

    my $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    user_admin->grant($user, 'remove_clone');
    is($user->can_list_machines, 0);
    is($user->can_list_clones_from_own_base, 1);

    $list = rvd_front->list_machines($user);
    is(scalar @$list , 0);

    is($user->can_manage_machine($base->id), 0);
    is($user->can_manage_machine($clone->id), 0);

    eval { $clone->remove($user)};
    like($@,qr'.');
    my $clone_d = $vm->search_domain($clone->name);
    ok($clone_d);

    $user->remove();
    $clone->remove(user_admin)  if $clone_d;
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
        skip $msg       if !$vm;

        diag("Testing remove on $vm_name");

        test_remove_admin($vm);
        test_remove_all($vm);
        test_remove_own_clone($vm);
        test_remove_clones_from_own_base($vm);
        test_remove_others_clone($vm);

        test_list_all($vm);
        test_list_clones_from_own_base($vm);
        test_list_clones_from_own_base_2($vm);
        test_list_clones_from_own_base_deny($vm);
        test_list_others_clone($vm);

    }
}

clean();

done_testing();
