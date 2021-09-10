use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

sub test_dupe($vm, $ip) {
    my $domain = create_domain($vm);
    $domain->expose(22);
    $domain->start(remote_ip => $ip , user => user_admin);
    my @display_info = $domain->display_info(user_admin);
    my $port = $display_info[0]->{port};
    $domain->_open_port(user_admin(), $ip, $vm->ip, $port);
    $domain->_close_port(user_admin(), '0.0.0.0/0', $vm->ip, $port);
    diag("check duplicated iptables");
    rvd_back->_check_duplicated_iptable();
    _check_first_accept($vm, $ip, $port);
    $domain->remove(user_admin);
}

sub test_dupe_open($vm, $ip) {
    my $domain = create_domain($vm);
    $domain->expose( port => 22, restricted => 1);
    $domain->start(remote_ip => $ip , user => user_admin);
    my @display_info = $domain->display_info(user_admin);
    my $port = $display_info[0]->{port};
    wait_request(debug => 0);
    my $req = Ravada::Request->open_iptables(id_domain => $domain->id
        ,remote_ip => $ip
        ,uid => user_admin->id
        ,_force => 1
    );
    wait_request(debug => 0);
    _check_first_accept($vm, $ip, $port);
    $req = Ravada::Request->open_exposed_ports(id_domain => $domain->id
        ,uid => user_admin->id
        ,_force => 1
    );
    wait_request(debug => 1);
    _check_first_accept($vm, $ip, $port);
    _check_prerouting($vm, 22);
    $domain->remove(user_admin);
}

sub _check_prerouting($vm, $dport) {
    my ($iptables, $err) = $vm->run_command("iptables-save");
    my ($accept, $drop);
    my %done;
    my $found;
    for my $line ( split /\n/,$iptables) {
        next if $line !~ /^-A PREROUTING/;
        ($found) = $line =~ /^-A PREROUTING.*:$dport$/;
        ok(!$done{$line}++,"Duplicated $line ".Dumper(\%done)) or exit;
    }
    ok($found,"Not found dport $dport");
}

sub _check_first_accept($vm, $ip, $dport) {
    my ($iptables, $err) = $vm->run_command("iptables-save");
    my ($accept, $drop);
    my @iptables2 = grep {/^-A RAVADA/ } split /\n/,$iptables;
    my %accept;
    for my $line ( @iptables2 ) {
        my ($curr_accept) = $line =~ m{(^-A RAVADA .* --dport $dport .*ACCEPT)};
        my ($curr_drop) = $line =~ m{^(-A RAVADA .* --dport $dport .*DROP)};
        if ($curr_accept) {
            ok(0,"Duplicated $accept") or exit
            if $accept && $accept eq $curr_accept;

            my ($ip) = $curr_accept =~ m{-d (.*?) };
            $accept{$ip} = $curr_accept;
        }
        if ($curr_drop) {
            ok(0,"Duplicated $drop") or exit
            if $drop && $curr_drop eq $drop;

            my ($ip) = $curr_drop=~ m{-d (.*?) };
            ok(0,"DROP found before accept") if !$accept{$ip};
        }
    }
    ok(keys %accept,"Empty accept iptables") or exit;
}

SKIP:
{
    if ($>) {
        skip("Test must run as root",10);
    }
    flush_rules();
    for my $vm_name ( 'Void' ) {
        my $vm = rvd_back->search_vm($vm_name);
        ok($vm, "Expecting vm $vm_name") or next;
        for my $ip ( '192.0.2.3' , $vm->ip, '127.0.0.1') {
            test_dupe_open($vm, $ip);
            test_dupe($vm, $ip);
        }
    }
};

end();
done_testing();
