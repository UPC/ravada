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

192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 linkdown
192.18.1.0/24 dev foo1 proto kernel scope link src 192.18.1.3
192.18.2.0/24 dev foo2 scope link"
;
    $vm->{_run}->{"/sbin/ip route"}=[$route,''];

    my $devs = "1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
1: lo    inet6 ::1/128 scope host \       valid_lft forever preferred_lft forever
3: wlp4s0    inet 192.168.1.62/24 brd 192.168.1.255 scope global noprefixroute wlp4s0\       valid_lft forever preferred_lft forever
5: eth0 inet 10.2.2.3/24 brd 10.2.2.255 scope global noprefixroute eth0\       valid_lft forever preferred_lft forever
6: foo1 inet 192.18.1.3/24 brd 192.168.1.255 scope global noprefixroute foo1\       valid_lft forever preferred_lft forever
7: foo2 inet 192.18.2.3/24 brd 192.168.2.255 scope global noprefixroute foo2\       valid_lft forever preferred_lft forever
8: virbr0    inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0\       valid_lft forever preferred_lft forever
";
    $vm->{_run}->{"/sbin/ip -o a"}=[$devs,''];

    my $domain = create_domain($vm);

    for my $remote_ip ( qw ( 1.1.36.99 10.2.2.33 192.18.1.9 192.18.2.9)) {
        my $expected_ip = '10.2.2.3';
        if ($remote_ip =~ /192.18/) {
            $expected_ip = $remote_ip;
            $expected_ip =~ s/\.\d+$/\.3/;
        }

        my $ip = $vm->_interface_ip($remote_ip);
        unlike($ip, qr/^192.168.12/);
        is($ip, $expected_ip,"remote ip $remote_ip") or exit;
        my $ip2 = $vm->listen_ip($remote_ip);
        unlike($ip2, qr/^192.168.12/);
        is($ip2,$expected_ip);

        eval {
            $domain->start(user => user_admin, remote_ip => $remote_ip);
        };
        like($@, qr/binding socket to/) if$vm->type ne 'Void';
        my $display = $domain->info(user_admin)->{hardware}->{display};
        for my $dp (@$display) {
            unlike($dp->{listen_ip}, qr/^192.168.12/);
            is($dp->{listen_ip}, $expected_ip) or exit;
        }
        $domain->shutdown_now(user_admin);

    }
    delete $vm->{_run};
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
        test_slim_route($vm);
        test_default_ip($vm);
    }
}

end();
done_testing();

