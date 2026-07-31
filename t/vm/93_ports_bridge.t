use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;
use YAML qw(LoadFile);
use XML::LibXML;
use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

my $BASE_NAME = "zz-test-base-alpine-q35-uefi";
my $BASE;
my $FILE_CONFIG_BRIDGE = "t/etc/bridge.conf";

my $CONFIG_BRIDGE;
$CONFIG_BRIDGE =  LoadFile($FILE_CONFIG_BRIDGE)
if -e $FILE_CONFIG_BRIDGE;

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
    my $remote_ip = '1.2.3.5';
    for ( 1 .. 30 ) {
        my $ip = $domain->ip();
        return $ip if $ip;
        diag("Waiting for ".$domain->name. " ip") if !(time % 10);
        sleep 1;
    }
    confess "Error : no ip for ".$domain->name." Maybe set MAC in YAML file $FILE_CONFIG_BRIDGE";
}

sub _set_mac_address($domain) {
    return if ! $CONFIG_BRIDGE || !exists $CONFIG_BRIDGE->{mac};
    if ($domain->type eq 'KVM') {
        my $doc = XML::LibXML->load_xml( string => $domain->xml_description());
        my ($dev) = $doc->findnodes('/domain/devices/interface[@type="bridge"]/mac');
        $dev->setAttribute('address' => $CONFIG_BRIDGE->{mac});
        $domain->reload_config($doc);
    } elsif( $domain->type eq 'Void') {
        my $ip = $CONFIG_BRIDGE->{ip}
            or die "Error: missing ip in $FILE_CONFIG_BRIDGE ".Dumper($CONFIG_BRIDGE);

        my $hardware = $domain->_value('hardware');
        $hardware->{network}->[0]->{address} = $ip;
        $domain->_store('hardware' => $hardware);
    } else {
        die "I don't know how to set mac for ".$domain->type;
    }
}

sub _set_bridge($vm, $domain) {
    my @bridges = $vm->_list_bridges();
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
    _set_mac_address($domain);
    return $bridges[0];
}

sub test_bridge($vm) {

    my $domain= $BASE->clone(name => new_domain_name, user => user_admin);
    is($domain->has_nat_interfaces,1,"Expecting ".$domain->name." has nat "
        .$vm->name);
    _set_bridge($vm, $domain);
    is($domain->has_nat_interfaces,0,"Expecting ".$domain->name." has no nat "
        .$vm->name) or exit;

    my $internal_port = 22;
    my $name = "foo";
    $domain->expose(port => $internal_port, restricted => 1, name => 'ssh');

    my $remote_ip = '10.0.0.1';
    $domain->start(user => user_admin, remote_ip => $remote_ip);
    _wait_ip($domain);

    Ravada::Request->start_domain(uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip
    );
    wait_request(debug => 0);

    my $internal_ip = _wait_ip($domain);
    $domain->ip;
    wait_request(debug => 0);

    my $ip_info = $domain->ip_info();
    ok($ip_info->{type} eq 'bridge');

    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    my $local_ip = $vm->ip;
    my $exposed_port = $domain->exposed_port($internal_port);
    my $public_port = $exposed_port->{public_port};

    ok($public_port) or die $domain->name;

    isnt($exposed_port->{public_port}, $internal_port) or exit;

    my ($in, $out, $err);
    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1)
        or die Dumper(\@out);

    run3(['iptables','-t','nat','-L','POSTROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(/^SNAT.* 0.0.0.0\/0\s+$internal_ip\s+tcp dpt\:$internal_port to\:$local_ip$/,@out),1);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1) or die $out;

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

    Ravada::Request->shutdown_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,timeout => 2
    );
    wait_request();
    for ( 1.. 10 ) {
        run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
        die $err if $err;
        @out = split /\n/,$out;

        last if(!grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out));

        wait_request();
    }

    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;

    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),0)
        or die Dumper(\@out);

    run3(['iptables','-t','nat','-L','POSTROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(/^SNAT.* 0.0.0.0\/0\s+$internal_ip\s+tcp dpt\:$internal_port to\:$local_ip$/,@out),0)
        or die Dumper([ grep /^SNAT/, @out]);

}

sub _get_alternate_ip {
    my ($in, $out, $err);
    run3(["ip","route"], \$in, \$out, \$err);
    die $err if $err;
    my ($ip) = $out =~ /^\d+\.\d+.* dev virbr.*link src (\d+\.\d+\.\d+\.\d+)/m;

    return $ip if $ip;

    warn "Warning: I can't find an alternate ip from $out. Using localhost" if !$ip;

    return '127.0.0.1';

}

# Test scenario with NAT and Display_ip ########################################
#
sub test_bridge_nat($vm) {

    my $nat_ip = '198.18.1.33';
    my $display_ip = _get_alternate_ip();
    $vm->nat_ip($nat_ip);
    $vm->display_ip($display_ip);

    my $domain= $BASE->clone(name => new_domain_name, user => user_admin);
    is($domain->has_nat_interfaces,1,"Expecting ".$domain->name." has nat "
        .$vm->name);
    _set_bridge($vm, $domain);
    is($domain->has_nat_interfaces,0,"Expecting ".$domain->name." has no nat "
        .$vm->name) or exit;

    my $internal_port = 22;
    my $name = "foo";
    $domain->expose(port => $internal_port, restricted => 1, name => 'ssh');

    my $remote_ip = '10.0.0.1';
    $domain->start(user => user_admin, remote_ip => $remote_ip);
    _wait_ip($domain);

    Ravada::Request->start_domain(uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip
    );
    wait_request(debug => 0 , skip => 'refresh_machine_ports');

    my $internal_ip = _wait_ip($domain);
    $domain->ip;
    wait_request(debug => 0);

    my $ip_info = $domain->ip_info();
    ok($ip_info->{type} eq 'bridge');

    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    my $local_ip = $vm->ip;
    my $interface_ip = $vm->interface_ip($remote_ip);
    my $exposed_port = $domain->exposed_port($internal_port);
    my $public_port = $exposed_port->{public_port};

    ok($public_port) or die $domain->name;

    isnt($exposed_port->{public_port}, $internal_port) or exit;

    my ($in, $out, $err);
    run3(['iptables','-t','nat','-L','PREROUTING','-n'], undef, \$out, \$err);
    die $err if $err;
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*$interface_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1)
        or die Dumper(\@out);

    run3(['iptables','-t','nat','-L','POSTROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;

    is(grep(/^SNAT.* 0.0.0.0\/0\s+$internal_ip\s+tcp dpt\:$internal_port to\:$interface_ip$/,@out),1);

    run3(['iptables-save','-t','nat'],\($in, $out, $err));
    die $err if $err;
    @out = grep /SNAT/, split/\n/,$out;
    my @snat = grep /SNAT/, @out;
    is(scalar(@snat),1);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1) or die $out;

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

    Ravada::Request->shutdown_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,timeout => 2
    );
    wait_request(debug => 0, skip => 'refresh_machine_ports');
    for ( 1.. 10 ) {
        run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
        die $err if $err;
        @out = split /\n/,$out;

        my ($dnat) = grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out);
        my ($snat) = grep(/^SNAT.* 0.0.0.0\/0\s+$internal_ip\s+tcp dpt\:$internal_port to\:$interface_ip$/,@out);
        last if !$dnat && !$snat;

        wait_request();
    }

    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;

    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),0)
        or die Dumper(\@out);

    run3(['iptables','-t','nat','-L','POSTROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(/^SNAT.* 0.0.0.0\/0\s+$internal_ip\s+tcp dpt\:$internal_port to\:$local_ip$/,@out),0)
        or die Dumper([ grep /^SNAT/, @out]);

    $vm->nat_ip('');
    $vm->display_ip('');
    remove_domain($domain);
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
        test_bridge_nat($vm);
        test_bridge($vm);
    }
}

end();
done_testing();
