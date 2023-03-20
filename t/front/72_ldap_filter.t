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
use Ravada::Utils;

###############################################################

sub _create_data() {
    my @data;
    for ( 1 .. 2 ) {
        my $name = new_domain_name();
        my $surname = Ravada::Utils::random_name(4);
        my $data = {
            cn => "$name.$surname"
        };
        push @data,($data);
    }
    return @data;
}

sub _init_ldap($field) {

    my @data = _create_data();
    my @userb;
    for my $data (@data) {
        my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
        my $user = create_ldap_user($data->{cn},1);
        my $msg= $user->add(objectClass => ['groupOfNames'])->update($ldap);
        $msg->code and die $msg->error;

        $msg = $user->add(member=> ['CN=service-vdi,dc=example,dc=com'])
        ->update($ldap);
        $msg->code and die $msg->error;

        foreach my $attr ( 'cn','givenName', 'sn' ) {
            my @value=$user->get_value( $attr );
            # diag(Dumper([$attr,\@value] ));
            #            is(scalar(@value),1) or exit;
        }


        my $name = $user->get_value($field);

        my $login = Ravada::Auth::login($name,1);
        ok($login);

        my $userb = Ravada::Auth::SQL->new(name => $name);

        push @userb,($userb);
        ok($userb->ldap_entry, "Expecting LDAP entry for $field=$name") or next;

        my $user2 = $userb->ldap_entry;
        foreach my $attr ( 'cn','givenName', 'sn' ) {
            my @value=$user2->get_value( $attr );
            #       diag(Dumper([$attr,\@value] ));
            #            is(scalar(@value),1) or exit;
        }


    }

    return @userb;
}

sub test_access($vm, $user1, $user2) {

    return if !$user1->ldap_entry || !$user2->ldap_entry;

    my $domain = create_domain($vm);
    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    $domain->allow_ldap_access('cn' => $user1->ldap_entry->get_value('cn'),0);
    $domain->allow_ldap_access('cn' => $user2->ldap_entry->get_value('cn'),1,1);

    $domain->default_access('ldap',0);

    is($user2->allowed_access($domain->id),1) or exit;
    is($user1->allowed_access($domain->id),0);

    my $list1 = rvd_front->list_machines_user($user1);
    my $list2 = rvd_front->list_machines_user($user2);
    is(scalar(@$list1),0);
    is(scalar(@$list2),1);

    my $clone;
    eval {
        $clone = $domain->clone(name => new_domain_name()
            ,user => $user1
        );
    };
    like($@,qr/user.*can not clone/);
    ok(!$clone);

    remove_domain($domain);
}

###############################################################
init(init_ldap_config());
remove_old_users_ldap();


for my $with_filter( 0,1 ) {

    for my $field ( 'cn', 'givenName', 'sn' ) {

        diag("Test with filter=$with_filter, field=$field");

        my $filter = { filter=> 'member=CN=service-vdi,dc=example,dc=com' };
        $filter = {} if !$with_filter;

        $filter->{field} = $field;

        my $fly_config = init_ldap_config(
            undef,undef,undef,$filter
        );

        init($fly_config);

        for my $vm_name ( 'Void' ) {
            my $vm = rvd_back->search_vm($vm_name);
            die "Error: no $vm_name engine found" if !$vm;

            test_access($vm
                ,_init_ldap($field)
            );
        }

    }
}

end();
done_testing();
