use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw(lock_hash);
use Test::More;

use lib 't/lib';
use Test::Ravada;

use feature qw(signatures);
no warnings "experimental::signatures";


use_ok('Ravada');

######################################################################

sub test_upgrade_grants($domain, $grant_name, $allowed=undef, $base=undef) {

    my $usera = create_user();
    user_admin->make_admin($usera->id);
    my $user = create_user();
    $usera->grant_user_permissions($user);

    my $clone;
    if ($base) {
        is($user->can_clone(),1) or exit;
        $clone = $base->clone(
            name => new_domain_name
            ,user => $user
        );
    }

    is($usera->can_do($grant_name),1);

    if ($clone) {
        is($user->can_do_domain($grant_name, $clone),$allowed,"Expecting user can do $grant_name")
    }
    is($user->can_do($grant_name),$allowed,"Expecting user can do $grant_name")
        or exit;

    my $sth = connector->dbh->prepare(
        "SELECT * FROM grant_types"
        ." WHERE name=?"
    );
    $sth->execute($grant_name);
    my $grant = $sth->fetchrow_hashref;
    lock_hash(%$grant);
    die "Error: unknonwn grant_types=$grant" if !$grant->{id};

    my $sth_remove = connector->dbh->prepare(
        "DELETE FROM grants_user WHERE id_grant=? AND id_user=?"
    );
    $sth_remove->execute($grant->{id}, $usera->id);
    $sth_remove->execute($grant->{id}, $user->id);

    my $sth_undefine = connector->dbh->prepare(
        " UPDATE grant_types SET enabled=NULL "
        ." WHERE id=?"
    );
    $sth_undefine->execute($grant->{id});
    my $grant2 = $sth->fetchrow_hashref;
    is($grant2->{enabled},undef);

    rvd_back->_install_grants();

    $sth->execute($grant_name);
    my $grant3 = $sth->fetchrow_hashref;
    is($grant3->{enabled},1);

    my $sth_user = connector->dbh->prepare(
        "SELECT * FROM grants_user WHERE id_grant=? AND id_user=?"
    );
    $sth_user->execute($grant->{id}, $usera->id);
    my $gu = $sth_user->fetchrow_hashref();
    ok($gu, "Expecting grant for id_grant=$grant->{id}, id_user=".$usera->id);
    is($gu->{allowed},1,"Expecting admin ".$usera->name." [ ".$usera->id." ] can $grant_name");

    $sth_user->execute($grant->{id}, $user->id);
    $gu = $sth_user->fetchrow_hashref();
    ok($gu, "Expecting grant for id_grant=$grant->{id}, id_user=".$user->id);

    my $granted = ( $allowed or 0);
    is($gu->{allowed},$granted,"Expecting no admin can not $grant_name");

}

sub test_default_user() {
    my $user = create_user();
    for my $name (qw( clone change_settings remove shutdown screenshot reboot hibernate )) {

        my $sth = connector->dbh->prepare("SELECT enabled,default_user"
            ." FROM grant_types WHERE name=?"
        );
        $sth->execute($name);
        my ($enabled,$default_user) = $sth->fetchrow;
        is($enabled,1,"Expecting enabled for $name");
        is($default_user,1,"Expecting default user for $name");
        exit if !$enabled || !$default_user;

        is($user->can_do($name),1) or die "Expecting user can $name";
    }
}

sub test_upgrade_default_user() {
    my $sth = connector->dbh->prepare(
        "alter table grant_types drop column default_user"
    );
    $sth->execute();

    rvd_back->_install();

    my $user = create_user();
    is($user->can_clone(),1);
    is($user->can_change_settings(),1);
    is($user->can_remove(),1);
    is($user->can_screenshot(),1);
    is($user->can_shutdown(),1);
    is($user->can_reboot(),1);
    is($user->can_hibernate(),1);

}
######################################################################

init();

my $vm_name = 'Void';
my $vm;
eval { $vm = rvd_back->search_vm($vm_name) };
diag($@) if $@;

my $domain = create_domain($vm);
$domain->prepare_base(user_admin);
$domain->is_public(1);

test_default_user();
test_upgrade_default_user();

test_upgrade_grants($domain,'hibernate_all');
test_upgrade_grants($domain,'hibernate_clone');
test_upgrade_grants($domain,'hibernate_clone_all');
test_upgrade_grants($domain,'screenshot_all');

test_upgrade_grants($domain,'screenshot',1,$domain);

end();
done_testing();
