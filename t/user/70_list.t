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

sub test_grant_list_clone_on_clone_not_owned($grant, $vm, $user_A, $user_B) {
    #create
    user_admin->grant($user_A,'create_machine');
    user_admin->grant($user_A,'create_base');
    my $base = create_domain($vm->type, $user_A);
    
    my $clone = clone($base, $user_B);
    user_admin->grant($user_A,$grant);

    is($user_A->can_list_clones_from_own_base,1);
    my $list = rvd_front->list_machines($user_A);
    
    #test
    ok(grep { $_->{'name'} eq $base->{'_data'}->{'name'} } @$list );
    ok(grep { $_->{'name'} eq $clone->{'_data'}->{'name'} } @$list );
    is(scalar @$list, 2);
    
    #delete things
    user_admin->revoke($user_A,'create_machine');
    user_admin->revoke($user_A,'create_base');
    user_admin->revoke($user_A, $grant);
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_clones_all_only_available_machine($grant, $vm, $user_A, $user_B) {
    #setup
    user_admin->grant($user_A,'create_machine');
    user_admin->grant($user_A,'create_base');
    user_admin->revoke_all_permissions($user_B);
    user_admin->grant($user_B, $grant);
    user_admin->grant($user_B,'create_machine');
    user_admin->grant($user_B,'create_base');
    user_admin->grant($user_B, 'clone');
    
    #3 machines non visibles for clones_all
    my $base1 = create_domain($vm->type, $user_A);
    $base1->prepare_base($user_A);
    my $base2 = create_domain($vm->type, $user_A);
    $base2->prepare_base($user_A);
    my $base3 = create_domain($vm->type, $user_A);
    $base3->prepare_base($user_A);
    
    #5 machines visibles for clones_all
    my $base_with_clones_A = create_domain($vm->type, $user_A);
    $base_with_clones_A->prepare_base($user_A);
    my $base_with_clones_B = create_domain($vm->type, $user_B);
    $base_with_clones_B->prepare_base($user_B);
    my $clone_from_A_1 = clone($base_with_clones_A, $user_A);
    my $clone_from_A_2 = clone($base_with_clones_B, $user_A);
    my $clone_from_B_1 = clone($base_with_clones_A, $user_B);
    my $clone_from_B_2 = clone($base_with_clones_B, $user_B); 
    user_admin->revoke($user_B, 'create_machine');
    user_admin->revoke($user_B, 'create_base');
    user_admin->revoke($user_B, 'clone');
    
    my $list = rvd_front->list_machines($user_B);
    #test

    is(scalar @$list, 6);
    ok(grep { $_->{'name'} eq $base_with_clones_A->{'_data'}->{'name'} } @$list );
    ok(grep { $_->{'name'} eq $clone_from_A_1->{'_data'}->{'name'} } @$list );
    ok(grep { $_->{'name'} eq $clone_from_A_2->{'_data'}->{'name'} } @$list );
    ok(grep { $_->{'name'} eq $base_with_clones_B->{'_data'}->{'name'} } @$list );
    ok(grep { $_->{'name'} eq $clone_from_B_1->{'_data'}->{'name'} } @$list );
    ok(grep { $_->{'name'} eq $clone_from_B_2->{'_data'}->{'name'} } @$list );
    
    #clean
    user_admin->revoke($user_B, $grant);
    user_admin->grant($user_B,'create_machine');
    user_admin->grant($user_B,'create_base');
    
    $clone_from_A_1->remove(user_admin);
    $clone_from_A_2->remove(user_admin);
    $clone_from_B_1->remove(user_admin);
    $clone_from_B_2->remove(user_admin);
    
    $base1->remove(user_admin);
    $base2->remove(user_admin);
    $base3->remove(user_admin);
    $base_with_clones_A->remove(user_admin);
    $base_with_clones_B->remove(user_admin);
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

sub list_grants($grant_like) {
    my $sth = connector->dbh->prepare(
        "SELECT name from grant_types"
        ." WHERE name like '%" . $grant_like . "'"
        ." AND enabled=1");
    $sth->execute();
    my @list;
    while ( my ($grant) = $sth->fetchrow ) {
        push @list,($grant);
    }
    return @list;
}

sub list_grants_clone {
    return list_grants('_clone');
}

sub list_grants_clone_all {
    return list_grants('_clone_all');
}

###################################################################

clean();

use_ok('Ravada');

use Data::Dumper;

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
        for my $grant ( list_grants_clone()) {
            test_grant_list_clone_on_clone_not_owned($grant, $vm, $oper, $user);
        }
        
        for my $grant ( list_grants_clone_all()) {
            test_clones_all_only_available_machine($grant, $vm, $oper, $user);
        }
        
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

end();
done_testing();
