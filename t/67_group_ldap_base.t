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

my  $BASE_USERS = "cn=users,cn=accounts,dc=example,dc=com";
my $BASE_GROUPS = 'cn=groups,cn=accounts,dc=example,dc=com';

our @OBJECT_CLASS = ('top'
                        ,'organizationalPerson'
                   ,'person'
                    ,'inetOrgPerson'
                   );

sub _init_base($base) {
    my $dn1 = $base;
    $dn1 =~ s/cn=\w+,(.*)/$1/;

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    for my $dn ( $dn1 , $base) {

        my ($filter,$base) = $dn =~ /(.*?),(.*)/;
        my $mesg = $ldap->search(      # Search for the user
            base => $base,
            filter => $filter,
            scope  => 'sub',
            typesonly => 0,
            attrs  => ['*']
        );

        confess "LDAP error ".$mesg->code." ".$mesg->error if $mesg->code;

        my @entries = $mesg->entries;
        if (!@entries) {
            my ($cn) = $dn =~ /^cn=(.*?),/;
            my %data = (
                cn => $cn
                ,sn => $cn
                ,objectclass => [@OBJECT_CLASS ]
            );
            warn $dn;
            $mesg = $ldap->add($dn, attr => [%data]);

            if ($mesg->code) {
                die "Error adding $dn ".$mesg->error;
            }
        }
    }
}

sub _create_group() {
    my $g_name="group_".new_domain_name();
    for my $base ( 'ou=groups,dc=example,dc=com', $BASE_GROUPS ) {
        my $group = Ravada::Auth::LDAP::search_group(name => $g_name, base => $base);

        if ($group) {
            my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
            $ldap->delete($group);
            $group = undef;
        }
    }

    Ravada::Auth::LDAP::add_group( $g_name );
    my $group = Ravada::Auth::LDAP::search_group(name => $g_name);
    ok($group) or return;
    like($group->dn,qr/cn=.*?,$BASE_GROUPS$/);
    ok($group);
    return $group;
}

init('t/etc/ravada_ldap_basic.conf');
$Ravada::CONFIG->{ldap}->{base} = $BASE_USERS;
$Ravada::CONFIG->{ldap}->{field} = 'uid';
$Ravada::CONFIG->{ldap}->{groups_base} = $BASE_GROUPS;
_init_base($BASE_GROUPS);
_init_base($BASE_USERS);

{
    my $group = _create_group() or next;
    is( scalar(Ravada::Auth::LDAP::group_members($group)),0);
    my $user = create_ldap_user(new_domain_name(),"$$");
    like($user->dn,qr/uid=.*?,$BASE_USERS/) or exit;
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
end();
done_testing();
