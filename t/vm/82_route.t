use warnings;
use strict;

use Data::Dumper;
use Test::More;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
###############################################################################
sub test_default_ip($vm) {
    my $ip = $vm->_interface_ip('1.1.36.99');
    unlike($ip, qr/^192.168.12/);

    my $ip2 = $vm->listen_ip('1.1.36.99');
    unlike($ip2, qr/^192.168.12/);


}

sub test_slim_route($vm) {
    my $route = "default via 10.2.2.1 dev eth0
10.2.2.1 dev eth0 scope link
192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 linkdown";
    $vm->{_run}->{"/sbin/ip route"}=[$route,''];

    my $domain = create_domain($vm);

    for my $remote_ip ( qw ( 1.1.36.99 10.255.255.3)) {
        my $ip = $vm->_interface_ip($remote_ip);
        unlike($ip, qr/^192.168.12/);
        my $ip2 = $vm->listen_ip($remote_ip);
        unlike($ip2, qr/^192.168.12/);

        $domain->start(user => user_admin, remote_ip => $remote_ip);
        my $display = $domain->info(user_admin)->{hardware}->{display};
        for my $dp (@$display) {
            unlike($dp->{listen_ip}, qr/^192.168.12/);
        }

    }
    delete $vm->{_run}->{"/sbin/ip route"};
}

###############################################################################
clean();

for my $vm_name (vm_names()) {
    diag($vm_name);
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name); };
    SKIP: {
        if (!$vm) {
        skip("No $vm_name virtual manager found",3);
        }
        test_default_ip($vm);
        test_slim_route($vm);
    }
}

end();
done_testing();

