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

use_ok('Ravada');

my $BASE_NAME = "zz-test-base-alpine";
my $BASE;

#######################################################################

sub _import_base($vm) {
    if ($vm->type eq 'KVM') {
        $BASE = rvd_back->search_domain($BASE_NAME);
        $BASE = import_domain($vm->type, $BASE_NAME, 1) if !$BASE;
        confess "Error: domain $BASE_NAME is not base" unless $BASE->is_base;

        confess "Error: domain $BASE_NAME has exported ports that conflict with the tests"
        if $BASE->list_ports;
    } else {
        $BASE = create_domain($vm);
    }
}

sub _wait_ip($domain) {
    $domain->start(user => user_admin, remote_ip => '1.2.3.5') unless $domain->is_active();
    for ( 1 .. 30 ) {
        return $domain->ip if $domain->ip;
        diag("Waiting for ".$domain->name. " ip") if !(time % 10);
        sleep 1;
    }
    confess "Error : no ip for ".$domain->name;
}

sub _set_bridge($vm, $domain) {
    return if $vm->type eq 'Void';
    my @bridges = $vm->_list_bridges();
    return if !@bridges;
    my $req = Ravada::Request->change_hardware(
        hardware => 'network'
        ,id_domain => $domain->id
        ,uid => user_admin->id
        ,index => 0
        ,data => {
            'type' => 'bridge'
            ,'bridge' => $bridges[0]
            ,'driver' => 'virtio'
        }
    );
    wait_request();
    return $bridges[0];
}

sub test_bridge($vm) {

    my $domain= $BASE->clone(name => new_domain_name, user => user_admin);
    _set_bridge($vm, $domain) or return;
    my $internal_port = 22;
    my $name = "foo";
    $domain->expose(port => $internal_port, restricted => 0, name => 'ssh');
    my $remote_ip = '10.0.0.1';
    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $internal_ip = _wait_ip($domain);
    wait_request(debug => 1);

    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    my $local_ip = $vm->ip;
    my $exposed_port = $domain->exposed_port($internal_port);
    my $public_port = $exposed_port->{public_port};
    is($public_port, $internal_port) or exit;
    is($exposed_port->{public_port}, $internal_port) or exit;

    my ($in, $out, $err);
    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),0);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),0) or die $out;

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),0) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),0) or die $out;

    $domain->remove(user_admin);
}

######################################################################

init();
clean();

for my $vm_name ( reverse vm_names() ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }
        if ($vm && !$vm->_list_bridges()) {
            $msg = "SKIPPED: No bridges found";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        flush_rules() if !$<;
        _import_base($vm);
        test_bridge($vm);
    }
}

end();
done_testing();
