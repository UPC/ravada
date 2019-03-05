#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();

=pod

Some tests for this are too in t/user/40_grant_shutdown

Here we will grant a non-admin user some power for clones to his base.
Then we will check she can list those clones

=cut


###################################################################

sub test_list_denied($user) {
    is($user->can_list_machines, 0);
    is($user->can_list_clones_from_own_base, 0);

    my $list = rvd_front->list_machines($user);

    is(scalar @$list,0);
}

sub test_list_allowed($user, $grant='', $base=undef , $base_other=undef) {
    is($user->is_operator,1);
    is($user->can_list_clones_from_own_base, 1,"Expecting can list clone with $grant");

    my $list = rvd_front->list_machines($user);

    ok(scalar @$list,"Expecting a list of machines $grant");

    # if optional argument base is passed, we check it is in the
    # listing, and its clones too.
    if ($base) {
        ok(grep({ $base->name eq $_->{name} } @$list)
            ,"Checking ".$base->name." in list");
        for my $clone( $base->clones ) {
            ok(grep( { $clone->{name} eq $_->{name} } @$list)
                ,"Checking ".$clone->{name}." in list");
        }
    }
    # if optional argument base_other is passed, we check it is NOT in the
    # listing, and its clones neither.
    if ($base_other) {
        ok(!grep({ $base_other->name eq $_->{name} } @$list)
            ,"Checking ".$base_other->name." not in list");
        for my $clone( $base_other->clones ) {
            ok(!grep( { $clone->{name} eq $_->{name} } @$list)
                ,"Checking ".$clone->{name}." not in list");
        }
    }
}

sub clone($base, $user) {
    $base->prepare_base(user_admin) if !$base->is_base;
    $base->is_public(1);

    my $clone = $base->clone(
          name => new_domain_name
        , user => $user
    );

}

sub remove_machine(@bases) {
    for my $base ( @bases ) {
        for my $domain_info( $base->clones) {
            my $domain = Ravada::Domain->open($domain_info->{id});
            $domain->remove(user_admin);
        }
        $base->remove(user_admin);
    }
}

sub list_grants_clone {
    my $sth = connector->dbh->prepare(
        "SELECT name from grant_types"
        ." WHERE name like '%_clone%'"
        ." AND enabled=1");
    $sth->execute();
    my @list;
    while ( my ($grant) = $sth->fetchrow ) {
        push @list,($grant);
    }
    return @list;
}

###################################################################

clean();

use_ok('Ravada');

my $oper = create_user("operator","whatever");
my $user = create_user("ken","whatever");

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
        skip $msg,10    if !$vm;

        diag("Testing machine listing on $vm_name");

        user_admin->grant($oper,'create_machine');
        user_admin->grant($oper,'create_base');

        my $base1 = create_domain($vm->type, user_admin);
        clone($base1, $user);
        my $base2 = create_domain($vm->type, $oper);
        clone($base2, $user);

        user_admin->revoke($oper,'create_machine');
        user_admin->revoke($oper,'create_base');

        test_list_denied($oper);
        test_list_allowed(user_admin);

        for my $grant ( list_grants_clone()) {
            diag(" testing $grant");
            user_admin->grant($oper, $grant);
            test_list_allowed($oper, $grant, $base2);
            user_admin->revoke($oper, $grant);
        }
        remove_machine($base1, $base2);
    }
}

clean();

done_testing();
