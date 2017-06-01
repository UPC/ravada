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

##########################################################

test_defaults();
test_admin();
test_grant();

done_testing();
