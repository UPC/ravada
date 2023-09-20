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
    wait_request();
    my ($network) = grep {$_->{name} eq $data->{name} }
        $vm->list_virtual_networks();
    return $network;
}

sub test_default_owner(@networks) {
    for my $net (@networks) {
        is($net->{id_owner},Ravada::Utils::user_daemon->id);
    }
}

sub test_deny_access($vm) {
    my $user = create_user();
    my $networks = rvd_front->list_networks($vm->id , $user->id);
    is(scalar(@$networks),0);

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
    wait_request(check_error => 0);
    like($req_delete->error,qr/not authorized/);

    user_admin->grant($user,'create_networks');
    $req_new->status('requested');
    $req_change->status('requested');
    $req_delete->status('requested');

    wait_request(check_error => 0);
    is($req_new->error,'');
    like($req_change->error,qr/not authorized/);
    like($req_delete->error,qr/not authorized/);
    is($req_change->status(),'done');
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
        wait_request( debug => 1);
        test_deny_access($vm);
    }

}

end();
done_testing();
