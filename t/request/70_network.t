use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use JSON::XS;
use POSIX qw(WNOHANG);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

init();

############################################################
sub test_list_nats($vm) {
    return if $<;
    my @exp_nat =   grep { defined $_ && !/^Name$/ }
                    map { /^\s+(\w+)\s*/; $1 }
                    split /\n/,`virsh net-list`;

    my $req = Ravada::Request->list_network_interfaces(
             uid => user_admin->id
           ,type => 'nat'
        ,vm_type => $vm->type
    );
    rvd_back->_process_requests_dont_fork();
    wait_request();
    is($req->status,'done');
    is($req->error,'');
    like($req->output,qr{\"$exp_nat[0]\"});

    my $nats = rvd_front->list_network_interfaces(
           user => user_admin
          ,type => 'nat'
       ,vm_type => $vm->type
       ,timeout => 1
    );
    ok($nats);

}

sub _remove_qemu_bridges($vm, $bridges) {
    return @$bridges if $vm->type eq 'Void';
    my @nat = $vm->list_network_interfaces('nat');

    my %bridges = map { $_ => 1 } @$bridges;
    for my $nat ( @nat ) {
        my $nat_bridge = `virsh net-info $nat| egrep "^Bridge:" | awk '{ print \$2 }'`;
        chomp $nat_bridge;
        chomp $nat_bridge;
        delete $bridges{$nat_bridge}
    }
    return keys %bridges;
}

sub test_list_bridges($vm) {

    is(rvd_front->{_networks_bridge},undef);

    my $req = Ravada::Request->list_network_interfaces(
             uid => user_admin->id
           ,type => 'bridge'
        ,vm_type => $vm->type
    );
    rvd_back->_process_requests_dont_fork();
    wait_request();
    is($req->status,'done');
    is($req->error,'');

    my @exp_bridges = sort(_expected_bridges($vm));
    is($req->output,encode_json(\@exp_bridges));

    my $bridges = rvd_front->list_network_interfaces(
           user => user_admin
          ,type => 'bridge'
       ,vm_type => $vm->type
       ,timeout => 1
      );
    ok($bridges);
    warn Dumper($bridges);

    SKIP: {
        skip("No system bridges found",1) if !scalar @exp_bridges;
        like($req->output, qr/\["[\w\d]+".*\]/);
    }
}
sub _expected_bridges($vm) {
    my $brctl = `which brctl`;
    chomp $brctl;
    return undef if !$brctl;

    my @exp_bridges =   grep { defined $_ && $_ ne 'bridge' }
    map { /(^\w+)\s*/; $1 }
    split /\n/,`brctl show`;
    @exp_bridges = _remove_qemu_bridges($vm, \@exp_bridges);

    return @exp_bridges;
}

############################################################

for my $vm_name (vm_names()) {
    my $vm;
    my $msg = "SKIPPED: virtual manager $vm_name not found";
    eval {
        $vm= rvd_back->search_vm($vm_name)  if rvd_back();

        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm= undef;
        }

    };

    SKIP: {
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;
        diag("Testing requests with $vm_name");

        test_list_nats($vm);
        test_list_bridges($vm);
    }


}

end();
done_testing();
