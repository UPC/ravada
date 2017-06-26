use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);

#########################################################3

sub test_defaults {
    my $user= create_user("foo","bar");
    my $rvd_back = rvd_back();

    ok($user->can_clone);
    ok($user->can_change_settings);
    ok($user->can_screenshot);

    ok($user->can_remove);

    ok(!$user->can_remove_clone);

    ok(!$user->can_clone_all);
    ok(!$user->can_change_settings_all);
    ok(!$user->can_change_settings_clones);


    ok(!$user->can_screenshot_all);
    ok(!$user->can_grant);

    ok(!$user->can_create_domain);
    ok(!$user->can_remove_all);
    ok(!$user->can_remove_clone_all);

    ok(!$user->can_shutdown_clone);
    ok(!$user->can_shutdown_all);

    ok(!$user->can_hibernate_clone);
    ok(!$user->can_hibernate_all);

    for my $perm (user_admin->list_permissions) {
        if ( $perm =~ m{^(clone|change_settings|screenshot|remove)$}) {
            is($user->can_do($perm),1,$perm);
        } else {
            is($user->can_do($perm),undef,$perm);
        }
    }
}

sub test_admin {
    my $user = create_user("foo$$","bar",1);
    ok($user->is_admin);
    for my $perm ($user->list_all_permissions) {
        is($user->can_do($perm->{name}),1);
    }
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

}

sub test_operator {
    my $usero = create_user("oper$$","bar");
    ok(!$usero->is_operator);
    ok(!$usero->is_admin);

    my $usera = create_user("admin$$","bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);

    $usera->grant($usero,'shutdown_clone');
    ok($usero->is_operator);
    ok(!$usero->is_admin);

    $usero->remove();
    $usera->remove();
}

sub test_shutdown_clone {
    my $vm_name = shift;

    my $user = create_user("oper$$","bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);

    my $usera = create_user("admin$$","bar",'is admin');
    ok($usera->is_operator);
    ok($usera->is_admin);


    my $domain = create_domain($vm_name, $user);
    $domain->prepare_base($user);
    ok($domain->is_base) or return;

    my $clone = $domain->clone(user => $usera,name => new_domain_name());
    $clone->start($usera);

    is($clone->is_active,1) or return;

    eval { $clone->shutdown_now($user); };
    like($@,qr(.));

    is($clone->is_active,1) or return;

    $usera->grant($user,'shutdown_clone');

    eval { $clone->shutdown_now($user); };
    is($@,'');
    is($clone->is_active,0);

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

    my $user = create_user("oper_r$$","bar");
    ok(!$user->is_operator);
    ok(!$user->is_admin);

    user_admin()->revoke($user,'remove');

    ok(!$user->can_remove) or return;

    my $domain = create_domain($vm_name, $user);
    eval { $domain->remove($user)};
    ok($@,qr'.');

    my $domain2 = create_domain($vm_name, user_admin());
    eval { $domain2->remove($user)};
    ok($@,qr'.');

    user_admin()->grant($user,'remove');
    eval { $domain->remove($user)};
    ok($@,'');

    eval { $domain2->remove($user)};
    ok($@,qr'.');

    eval { $domain2->remove(user_admin())};
    ok($@,qr'.');

}

##########################################################

test_defaults();
test_admin();
test_grant();

test_operator();

test_shutdown_clone('Void');
test_remove('Void');

done_testing();
