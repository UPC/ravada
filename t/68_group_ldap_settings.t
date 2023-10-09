use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use Test::More;
use YAML qw(LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my  $BASE_USERS = "cn=accounts,dc=example,dc=com";
my $GROUP_BASE = "dc=example,dc=com";
my $GROUP_FIELD = 'cn';

sub _init_base($base) {

    my $object_class = ['top' ,'organizationalPerson'
                   ,'person' ,'inetOrgPerson'
                ];

    my $dn1 = $base;

    $dn1 =~ s/\w+=\w+,(.*)/$1/;

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
            my ($field,$value) = $dn =~ /^(\w+)=(.*?),/;
            my %data = (
                $field => $value
                ,sn => $value
                ,objectclass => $object_class
            );
            $mesg = $ldap->add($dn, attr => [%data]);

            if ($mesg->code) {
                die "Error adding $dn ".$mesg->error;
            }
        }
    }
}

sub _delete_entries($field,$value, $base) {

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $search = $ldap->search(
        filter => "$field=$value"
        ,base => $base
    );
    for my $entry ($search->entries) {
        $entry->delete;
        $entry->update($ldap);
    }
}

sub test_create_group_fail() {
    my $g_name="group_".new_domain_name();
    _delete_entries($GROUP_FIELD,$g_name, $GROUP_BASE);

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();

    my @fields = (
        $GROUP_FIELD => $g_name
        ,gidNumber => Ravada::Auth::LDAP::_search_new_gid()
        ,description => "Group of $g_name"
        ,objectClass => [ 'groupOfUniqueNames','nsMemberOf','posixGroup','top']
    );
    my $dn = "$GROUP_FIELD=$g_name,$GROUP_BASE";
    my $mesg = $ldap->add(
        dn => $dn
        ,$GROUP_FIELD => $g_name
        ,base => $GROUP_BASE
        ,attrs => \@fields
    );

    if ($mesg->code) {
        die "Error creating group: ".$mesg->error." $dn \n".Dumper(\@fields);
    }
    my $group = Ravada::Auth::LDAP::search_group(name => $g_name);
    ok(!$group) or return;

    _delete_entries($GROUP_FIELD,$g_name, $GROUP_BASE);

}

sub test_create_group($posix) {

    my $objectClass = [ 'nsMemberOf','top' ,'organizationalUnit'];
    if ($posix) {
        push @$objectClass,('posixGroup');
    } else {
        push @$objectClass,( 'groupOfUniqueNames','groupOfNames');
    }

    my $g_name="group_".new_domain_name();

    _delete_entries($GROUP_FIELD,$g_name, $GROUP_BASE);
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();

    my $ou = new_domain_name();
    my @fields = (
        $GROUP_FIELD => $g_name
        ,description => "Group of $g_name"
        ,ou => $ou
        ,objectClass => $objectClass
    );
    push @fields,(gidNumber => Ravada::Auth::LDAP::_search_new_gid())
    if $posix;

    my $mesg = $ldap->add(
        dn => "$GROUP_FIELD=$g_name,$GROUP_BASE"
        ,cn=> $g_name
        ,base => $GROUP_BASE
        ,attrs => \@fields
    );

    if ($mesg->code) {
        die "Error creating group: ".$mesg->error."\n".Dumper(\@fields);
    }
    my $group = Ravada::Auth::LDAP::search_group(name => $g_name);
    ok($group) or exit;

    like($group->dn,qr/$GROUP_FIELD=.*?,$GROUP_BASE$/);
    is($group->get_value('ou'), $ou);

    return $group;
}

sub _init_config() {
    my $config = {
        ldap => {
            base => $BASE_USERS
            ,field => 'cn'
            ,admin_user => {
                'dn' => 'cn=Directory Manager'
                ,'password' => '12345678'
            }
            ,group_base => $GROUP_BASE
            ,groups_base => $GROUP_BASE
            ,group_field => $GROUP_FIELD
            ,group_filter => "objectClass=organizationalUnit"
        }
    };
    lock_hash(%$config);
    is(Ravada::_check_config($config,undef,0),0,"expecting invalid config");
    delete $config->{ldap}->{groups_base};
    is(Ravada::_check_config($config,undef,0),1,"invalid config");
    init($config);
}

sub test_group( $posix ) {
    _init_config();

    _init_base("cn=".new_domain_name.",".$BASE_USERS);
    #_init_base("cn=users,dc=accounts,dc=example,dc=com");
    #_init_base("cn=dept,dc=accounts,dc=example,dc=com");

    test_create_group_fail();

    my $group = test_create_group($posix);

    my $user = create_ldap_user(new_domain_name(),"$$");

    Ravada::Auth::LDAP::add_to_group($user->dn, $group->get_value($GROUP_FIELD));

    $group = Ravada::Auth::LDAP::search_group(name => $group->get_value('cn'));

    my @found_member = grep /^member/i,$group->attributes();
    ok(@found_member,"Expecting a member attribute") or exit;

    {
    my @members = Ravada::Auth::LDAP::group_members($group);
    is(scalar(@members),1) or exit;
    }

    is(Ravada::Auth::LDAP::is_member($user->get_value('cn'), $group),1);

    my @oc = $group->get_value('objectClass');
    my ($posix_oc) = grep (/posix/,@oc);
    my @members2 = $group->get_value('member');
    my @members_uid = $group->get_value('memberUid');
    if ($posix) {
        ok($posix_oc) or die Dumper(\@oc);
        is(scalar(@members2),0);
        ok(scalar(@members_uid));
    } else {
        ok(!$posix_oc) or die Dumper(\@oc);
        ok(scalar(@members2));
        is(scalar(@members_uid),0);
    }
}

###################################################################

test_group(0);
test_group(1); # posix

end();
done_testing();
