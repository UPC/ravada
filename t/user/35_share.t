#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

##############################################################

sub test_share($vm) {
    my $base = create_domain($vm->type);

    $base->prepare_base( user_admin );
    $base->is_public(1);

    my $user1 = create_user(new_domain_name(),$$);
    my $user2 = create_user(new_domain_name(),$$);
    is($user1->is_admin,0);

    my $req = Ravada::Request->clone(
        uid => $user1->id
        ,id_domain => $base->id
    );
    wait_request();
    my ($clone0) = grep { $_->{id_owner} == $user1->id } $base->clones;
    ok($clone0);
    my $clone = Ravada::Front::Domain->open($clone0->{id});

    my $list_bases_u1 = rvd_front->list_machines_user($user1);
    my ($clone_user1) = grep { $_->{name } eq $base->name } @$list_bases_u1;
    is(scalar(@{$clone_user1->{list_clones}}),1);

    my $list_bases_u2 = rvd_front->list_machines_user($user2);
    my ($clone_user2) = grep { $_->{name } eq $base->name } @$list_bases_u2;
    is(scalar(@{$clone_user2->{list_clones}}),0);

    test_users_share($clone);
    $clone->share($user2);
    test_users_share($clone,$user2);

    is($user2->can_shutdown($clone),1);

    my $req2 = Ravada::Request->start_domain(
        uid => $user2->id
        ,id_domain => $clone->id
    );
    wait_request();
    is($req2->status,'done');
    is($req2->error,'');


    $list_bases_u2 = rvd_front->list_machines_user($user2);
    ($clone_user2) = grep { $_->{name } eq $base->name } @$list_bases_u2;
    is(scalar(@{$clone_user2->{list_clones}}),1);
    is($clone_user2->{list_clones}->[0]->{can_remove},0);
    is($clone_user2->{list_clones}->[0]->{can_shutdown},1);

    is($user2->can_view_all,undef);
    is($user2->can_start_machine($clone->id),1) or exit;

    is($user2->can_manage_machine($clone->id),1,"should manager machine");
    is($user2->can_change_settings($clone->id),1);

    test_machine_info_shared($user2,$clone);

    test_requests_shared($user2, $clone);

    $clone->remove_share($user2);

    is($user2->can_shutdown($clone),0);
}

sub test_users_share($clone, @users) {
    my $all_users = rvd_front->list_users();
    my @expected;
    for my $user (@$all_users) {
        next if grep { $_->id == $user->{id} } @users;
        next if $user->{id} == $clone->id_owner;

        push @expected,($user);
    }
    my $owner = Ravada::Auth::SQL->search_by_id($clone->id_owner);
    my $users_share = rvd_front->list_users_share('',$owner,@users);
    is_deeply($users_share,\@expected) or die Dumper($users_share,\@expected);

}

sub test_requests_shared($user, $clone) {
    my $req3 = Ravada::Request->start_domain(
        uid => $user->id
        ,id_domain => $clone->id
    );
    wait_request();
    is($req3->status,'done');
    is($req3->error,'');

    my $req4 = Ravada::Request->list_cpu_models(
        uid => $user->id
        ,id_domain => $clone->id
    );
    wait_request();
    is($req4->status,'done');
    is($req4->error,'');

}

sub test_machine_info_shared($user, $clone) {
    my $info = $clone->info($user);
    is($info->{can_start},1);
    is($info->{can_view},1);
}

##############################################################

clean();
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

        diag("Testing share on $vm_name");

        test_share($vm);
    }
}

end();
done_testing();
