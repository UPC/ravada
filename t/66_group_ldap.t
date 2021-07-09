use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Auth::LDAP');

sub _create_group($oc=['top','groupOfNames']) {
    my $g_name="group_".new_domain_name();
    my $group = Ravada::Auth::LDAP::search_group(name => $g_name);

    if ($group) {
        Ravada::Auth::LDAP::remove_group($g_name);
        $group = undef;
    }

    if (!$group) {
        Ravada::Auth::LDAP::add_group( $g_name
            ,undef
            ,$oc
        );
    }
    $group = Ravada::Auth::LDAP::search_group(name => $g_name);
    ok($group);
    return $group;
}

init('t/etc/ravada_ldap.conf');

for my $oc (
    ['top','groupOfUniqueNames','nsMemberOf','posixGroup']
    ,['top','groupOfNames']
    ,['top','posixGroup','groupOfUniqueNames']
    ,['top','groupOfUniqueNames','groupOfNames']) {
    my $group = _create_group($oc);
    is( scalar(Ravada::Auth::LDAP::group_members($group)),0);
    my $user = create_ldap_user(new_domain_name(),"$$");
    Ravada::Auth::LDAP::add_to_group($user->dn, $group->get_value('cn'));

    $group = Ravada::Auth::LDAP::search_group(name => $group->get_value('cn'));
    ok($group,"Expecting group ".$group->dn." exists") or next;

    my @members = Ravada::Auth::LDAP::group_members($group);
    is(scalar(@members),1);
    @members = Ravada::Auth::LDAP::group_members($group->get_value('cn'));
    is(scalar(@members),1);
    is(Ravada::Auth::LDAP::is_member($user->get_value('cn'), $group),1);
    is(Ravada::Auth::LDAP::is_member($user->dn, $group),1);

    my $user2 = create_ldap_user(new_domain_name(),"$$");
    is(Ravada::Auth::LDAP::is_member($user2->get_value('cn'), $group),0);
    is(Ravada::Auth::LDAP::is_member($user2->dn, $group),0);

    delete $Ravada::CONFIG->{ldap}->{ravada_posix_group};
    my $login;
    eval { $login = Ravada::Auth::LDAP->new(name => $user2->get_value('cn'),password => "$$") };
    is($@,'') or exit;
    ok($login);

    $Ravada::CONFIG->{ldap}->{group}=$group->get_value('cn');

    $login =undef;
    eval { $login = Ravada::Auth::LDAP->new(name => $user2->get_value('cn'),password => "$$") };
    like($@,qr'.');
    ok(!$login,"Expecting no login with ".$user2->get_value('cn'));

    $login =undef;
    eval { $login = Ravada::Auth::LDAP->new(name => $user->get_value('cn'),password => "$$") };
    is($@,'');
    ok($login);

    Ravada::Auth::LDAP::remove_from_group($user->dn, $group->get_value('cn'));
    $group = Ravada::Auth::LDAP::search_group(name => $group->get_value('cn'));
    is(Ravada::Auth::LDAP::is_member($user->get_value('cn') , $group),0
    ,"Expecting ".$user->get_value('cn')." not member of ".$group->get_value('cn'))
        or die Dumper([Ravada::Auth::LDAP::group_members($group)]);

    delete $Ravada::CONFIG->{ldap}->{group};
}
done_testing();
