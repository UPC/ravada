use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

###############################################################

sub _init_ldap() {

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $user_name = new_domain_name();
    my $user = create_ldap_user($user_name,$$);

    my $user_name2 = new_domain_name();
    my $user2 = create_ldap_user($user_name2,$$);

    my $msg= $user->add(objectClass => ['groupOfNames'])->update($ldap);
    $msg->code and die $msg->error;
    my $msg= $user2->add(objectClass => ['groupOfNames'])->update($ldap);
    $msg->code and die $msg->error;


    $msg = $user->add(member=> ['CN=service-vdi,dc=example,dc=com'])
    ->update($ldap);
    $msg->code and die $msg->error;

    $msg = $user2->add(member=> ['CN=service-vdi,dc=example,dc=com'])
    ->update($ldap);
    $msg->code and die $msg->error;

    my $login = Ravada::Auth::login($user_name,$$);
    ok($login);

    my $userb1 = Ravada::Auth::SQL->new(name => $user_name);
    ok($userb1->ldap_entry) or die "No LDAP entry for $user_name";
    my $userb2 = Ravada::Auth::SQL->new(name => $user_name2);
    ok($userb2->ldap_entry) or die "No LDAP entry for $user_name2";

    return ($userb1, $userb2);
}

sub test_access($vm, $user1, $user2) {

    my $domain = create_domain($vm);
    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    $domain->allow_ldap_access('cn' => $user1->name,0);
    $domain->allow_ldap_access('cn' => $user2->name,1,1);

    $domain->default_access('ldap',0);

    is($user2->allowed_access($domain->id),1) or exit;
    is($user1->allowed_access($domain->id),0);

    my $list1 = rvd_front->list_machines_user($user1);
    my $list2 = rvd_front->list_machines_user($user2);
    is(scalar(@$list1),0);
    is(scalar(@$list2),1);

    remove_domain($domain);
}

###############################################################
init(init_ldap_config());
remove_old_users_ldap();


for my $with_filter( 0,1 ) {

    diag("Test with filter=$with_filter");

    my $filter = { filter=> 'member=CN=service-vdi,dc=example,dc=com' };
    $filter = undef if !$with_filter;

    my $fly_config = init_ldap_config(
        undef,undef,undef,$filter
    );

    init($fly_config);


    for my $vm_name ( 'Void' ) {
        my $vm = rvd_back->search_vm($vm_name);
        die "Error: no $vm_name engine found" if !$vm;

        test_access($vm
            ,_init_ldap()
        );
    }
}

end();
done_testing();
