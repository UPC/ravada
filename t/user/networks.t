#!perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use Ravada;

use Data::Dumper;
use Mojo::JSON qw(decode_json);

no warnings "experimental::signatures";
use feature qw(signatures);

##############################################################################

sub test_create_network($vm) {
    my $req_new= Ravada::Request->new_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => base_domain_name()
    );
    wait_request();
    my $data = decode_json($req_new->output);

    my $req = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $data
    );
    wait_request(debug => 0);
    my ($network) = grep {$_->{name} eq $data->{name} }
        $vm->list_virtual_networks();

    return $network;
}

sub test_default_owner(@networks) {
    for my $net (@networks) {
        is($net->{id_owner},Ravada::Utils::user_daemon->id);
    }
}

sub test_grant_access($vm) {
    my $user = create_user();
    user_admin->grant($user,'create_networks');

    my $req_new= Ravada::Request->new_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,name => base_domain_name()
    );
    wait_request();
    is($req_new->error,'');
    my $data = decode_json($req_new->output);

    my $req_create = Ravada::Request->create_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,data => $data
    );

    wait_request();

    my ($network) = grep {$_->{name} eq $data->{name} }
        $vm->list_virtual_networks();

        ok($network) or die "Error: network not created ".Dumper($data);

    my $networks = rvd_front->list_networks($vm->id , $user->id);
    my ($network_f) = grep {$_->{name} eq $data->{name}} @$networks;

    ok($network_f) or die "Network $data->{name} not found ";

    is($network_f->{_owner}->{id}, $user->id);
    is($network_f->{_owner}->{name}, $user->name);
}

sub test_deny_access($vm) {
    my $user = create_user();
    my $networks = rvd_front->list_networks($vm->id , $user->id);
    ok(scalar(@$networks));

    $networks = rvd_front->list_networks($vm->id , user_admin->id);
    ok(scalar(@$networks));

    test_default_owner(@$networks);

    my $network = test_create_network($vm);

    my $req_new= Ravada::Request->new_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,name => base_domain_name()
    );
    wait_request(check_error => 0);
    like($req_new->error,qr/not authorized/);

    my $req_change = Ravada::Request->change_network(
        uid => $user->id
        ,data => $network
    );
    wait_request(check_error => 0);
    like($req_change->error,qr/not authorized/);

    my $req_delete = Ravada::Request->remove_network(
        uid => $user->id
        ,id => $network->{id}
    );
    wait_request(check_error => 0, debug => 1);
    like($req_delete->error,qr/not authorized/);
    my $networks2 = rvd_front->list_networks($vm->id , user_admin->id);
    my ($found2) = grep { $_->{name} eq $network->{name} } @$networks2;
    ok($found2,"Expecting network $network->{name} $network->{id} not removed ".Dumper($networks2)) or return;

    my $req_create = Ravada::Request->create_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,data => $network
    );
    wait_request(check_error => 0);
    like($req_create->error,qr/not authorized/);

    my $req_list = Ravada::Request->list_networks(
        uid => $user->id
        ,id_vm => $vm->id
    );
    wait_request(check_error => 0);
    like($req_list->error,qr/not authorized/);

    user_admin->grant($user,'create_networks');
    $req_new->status('requested');
    $req_change->status('requested');
    $req_list->status('requested');

    wait_request(check_error => 0);
    is($req_new->error,'');
    like($req_change->error,qr/not authorized/);
    is($req_change->status(),'done');
    is($req_list->error,'');

    $req_delete->status('requested');
    wait_request(check_error => 0);
    like($req_delete->error,qr/not authorized/);

    $req_create->status('requested');
    my $new_data = decode_json($req_new->output);
    $req_create->arg('data' => $new_data);
    $req_create->status('requested');
    wait_request();

    is($req_create->error, '');

    $req_list->status('requested');
    wait_request();

    my $new_list = decode_json($req_list->output);
    my ($found) = grep { $_->{name} eq $new_data->{name} } @$new_list;

    ok($found,"Expecting new network $new_data->{name}");
    $user->remove();
}

##############################################################################

init();

for my $vm_name( vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm= undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing networks access on $vm_name");

        Ravada::Request->list_networks(id_vm => $vm->id, uid => user_admin->id);
        wait_request( debug => 0);
        test_deny_access($vm);
        test_grant_access($vm);
    }

}

end();
done_testing();
