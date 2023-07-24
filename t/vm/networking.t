use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;
########################################################################

sub test_list_networks($vm) {
    my @list = $vm->list_virtual_networks();
    my ($default)= grep { $_->{name} eq 'default' } @list;
    ok($default);

    for my $net ( @list ) {
        my ($found) = _search_network(internal_id=>$net->{internal_id});
        is($found->{name}, $net->{name});
        ($found) = _search_network(id_vm => $net->{id_vm}, name => $net->{name});
        is($found->{internal_id}, $net->{internal_id});
    }

}

sub _search_network(%args) {
    my $sql = "SELECT * FROM virtual_networks "
    ." WHERE ".join(" AND ",map { "$_=?" } sort keys %args);
    my $sth = connector->dbh->prepare($sql);
    $sth->execute(map { $args{$_} } sort keys %args);
    my $found = $sth->fetchrow_hashref;
    return $found;
}

sub test_add_network($vm) {
    my $name = new_domain_name;
    my $net = {
        name => $name
        ,id_vm => $vm->id
        ,ip_address => '203.0.113.1'
        ,ip_netmask => '255.255.255.0'
    };
    my $user = create_user();
    my $req = Ravada::Request->create_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request(check_error => 0);
    like($req->error,qr/not authorized/);

    $req = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request();
    my($new) = grep { $_->{name} eq $name } $vm->list_virtual_networks();
    ok($new,"Expecting new network $name created") or return;

    is($new->{dhcp_start},2);
    is($new->{dhcp_end},254);
    ok($new->{internal_id});
    return $new;
}

sub test_remove_network($vm, $net) {
    my $user = create_user();
    my $req = Ravada::Request->remove_network(
        uid => $user->id
        ,id => $net->{id}
        ,id_vm => $vm->id
    );
    wait_request(check_error => 0);
    like($req->error,qr/not authorized/);
    user_admin->make_admin($user->id);
    $req->status('requested');

    wait_request(debug => 1);

    my($new) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    ok(!$new,"Expecting removed network $net->{name}") or exit;
}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {
    diag("testing $vm_name");

    SKIP: {

        my $msg = "SKIPPED test: No $vm_name VM found ";
        my $vm;
        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
        } else {
            $vm = Ravada::VM->open( type => $vm_name );
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        is($vm->has_networking,1) if $vm_name eq 'KVM';
        next if !$vm->has_networking();

        test_list_networks($vm);
        my $net = test_add_network($vm);

        test_remove_network($vm,$net);
    }
}

end();

done_testing();

