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

}


##########################################################

test_defaults();

done_testing();
