use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use JSON::XS;
use Test::More;
use IPTables::ChainMgr;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

##############################################################

# Forward one port
sub test_one_port($vm) {

    flush_rules();

    my $domain = create_domain($vm->type, user_admin ,'debian stretch');

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);

    _wait_ip($vm->type, $domain);

    my $domain_ip = $domain->ip;
    ok($domain_ip,"[".$vm->type."] Expecting an IP for domain ".$domain->name.", got ".($domain_ip or '')) or return;
    is(scalar $domain->list_ports,0);

    my ($internal_port, $name_port) = (22, 'ssh');
    my $public_port;
    eval {
       ($public_port) = $domain->expose(port => $internal_port, name => $name_port);
    };
    is($@,'',"[".$vm->type."] export port $internal_port");

    my $port_info_no = $domain->exposed_port(456);
    is($port_info_no,undef);

    $port_info_no = $domain->exposed_port('no');
    is($port_info_no,undef);

    my $port_info = $domain->exposed_port($name_port);
    ok($port_info) && do {
        is($port_info->{name}, $name_port);
        is($port_info->{internal_port}, $internal_port);
    };

    my $port_info2 = $domain->exposed_port($internal_port);
    ok($port_info2);
    is_deeply($port_info2, $port_info);

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1);

    my $info = $domain->info(user_admin);
    ok($info->{ports});
    is($info->{ports}->[0]->{internal_port}, $internal_port);
    is($info->{ports}->[0]->{public_port}, $public_port);
    is($info->{ports}->[0]->{name}, $name_port);

    my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
            , 'to-destination' => $domain->ip.":".$internal_port
    );

    ok($n_rule,"Expecting rule for -> $local_ip:$public_port") or exit;


    #################################################################
    #
    # shutdown
    local $@ = undef;
    eval { $domain->shutdown_now(user_admin) };
    is($@, '');

    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;

    #################################################################
    # start
    #
    $domain->start(user => user_admin, remote_ip => $remote_ip);

    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
            , 'to-destination' => $domain->ip.":".$internal_port
    );

    ok($n_rule,"Expecting rule for -> $local_ip:$public_port") or exit;

    #################################################################
    #
    # remove
    local $@ = undef;
    eval { $domain->remove(user_admin) };
    is($@, '');
    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;

}

# Remove expose port
sub test_remove_expose {
    my $vm_name = shift;
    my $request = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = create_domain($vm_name, user_admin,'debian stretch');

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);

    #    my $client_user = $domain->remote_user();
    # is($client_user->id, user_admin->id);

    _wait_ip($vm_name, $domain);

    my $domain_ip = $domain->ip;
    ok($domain_ip,"[$vm_name] Expecting an IP for domain ".$domain->name.", got ".($domain_ip or '')) or return;

    my $internal_port = 22;
    my ($public_port0) = $domain->expose($internal_port);
    ok($public_port0,"Expecting a public port") or exit;

    is(scalar $domain->list_ports,1);

    #    my ($public_ip, $public_port) = $domain->public_address($internal_port);
    #    is($public_ip, $public_ip0);
    #    is($public_port, $public_port0);
    my $public_port = $public_port0;

    my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok($n_rule,"Expecting rule for -> $local_ip:$public_port") or exit;

    #################################################################
    #
    # remove expose
    if (!$request) {
        local $@ = undef;
        eval { $domain->remove_expose($internal_port) };
        is($@, '');
    } else {
        my $req = Ravada::Request->remove_expose(
                   uid => user_admin->id
                 ,port => $internal_port
            ,id_domain => $domain->id
        );
        rvd_back->_process_all_requests_dont_fork();

        is($req->status(),'done');
        is($req->error(),'');
    }
    is(scalar $domain->list_ports,0) or exit;
    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;

    $domain->shutdown_now(user_admin);
    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;
}

sub test_req_remove_expose {
    flush_rules();
    test_remove_expose(@_,'request');
}

# Remove crash a domain and see if ports are closed after cleanup
sub test_crash_domain($vm_name) {
    flush_rules();

    my $vm = rvd_back->search_vm($vm_name);


    my $domain = create_domain($vm_name, user_admin,'debian stretch');

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);

    _wait_ip($vm_name, $domain);

    my $domain_ip = $domain->ip or do {
        diag("[$vm_name] Expecting an IP for domain ".$domain->name);
        return;
    };

    my $internal_port = 22;
    my $public_port = $domain->expose($internal_port);

    is(scalar $domain->list_ports,1);
    my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    is($n_rule,1,"Expecting rule for $remote_ip -> $local_ip:$public_port") or exit;

    #################################################################
    #
    # shutdown forced
    shutdown_domain_internal($domain);

    my $domain2 = create_domain($vm_name, user_admin,'debian stretch');
    $domain2->start(user => user_admin) if !$domain2->is_active;

    $domain2->remove(user_admin);
}

sub test_two_ports($vm) {

    flush_rules();

    my $domain = create_domain($vm, user_admin,'debian stretch');

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);

    _wait_ip($vm->type, $domain);

    my $domain_ip = $domain->ip;
    ok($domain_ip,"[".$vm->type
        ."] Expecting an IP for domain ".$domain->name.", got ".($domain_ip or '')) or return;

    my $internal_port1 = 10;
    my $public_port1 = $domain->expose($internal_port1);

    my $internal_port2 = 20;
    my $public_port2 = $domain->expose($internal_port2);

    ok($public_port1 ne $public_port2,"Expecting two different ports "
        ." $public_port1 $public_port2 ");

    for my $public_port ( $public_port1, $public_port2 ) {
        my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
        );

        ok($n_rule,"Expecting rule for -> $local_ip:$public_port") or exit;
    }

    local $@ = undef;
    eval { $domain->shutdown_now(user_admin) };
    is($@, '');

    for my $public_port ( $public_port1, $public_port2 ) {
        my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
        );

        ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;
    }
}

sub test_clone_exports($vm) {

    my $base = create_domain($vm, user_admin,'debian stretch');
    $base->expose(port => 22, name => "ssh");

    my @base_ports = $base->list_ports();
    is(scalar @base_ports,1 );

    my $clone = $base->clone(name => new_domain_name, user => user_admin);

    my @clone_ports = $clone->list_ports();
    is(scalar @clone_ports,1 );

    is($base_ports[0]->{internal_port}, $clone_ports[0]->{internal_port});
    isnt($base_ports[0]->{public_port}, $clone_ports[0]->{public_port});
    is($base_ports[0]->{name}, $clone_ports[0]->{name});

    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub _wait_ip {
    my $vm_name = shift;
    my $domain = shift  or confess "Missing domain arg";

    return if $domain->_vm->type !~ /kvm|qemu/i;
    return $domain->ip  if $domain->ip;

    sleep 1;
    eval ' $domain->domain->send_key(Sys::Virt::Domain::KEYCODE_SET_LINUX,200, [28]) ';
    die $@ if $@;

    return if $@;
    sleep 2;
    for ( 1 .. 12 ) {
        rvd_back->_process_requests_dont_fork();
        eval ' $domain->domain->send_key(Sys::Virt::Domain::KEYCODE_SET_LINUX,200, [28]) ';
        die $@ if $@;
        sleep 2;
    }
    for (1 .. 30) {
        last if $domain->ip;
        sleep 1;
        diag("waiting for ".$domain->name." ip") if $_ ==10;
    }
    return $domain->ip;
}

sub add_network_10 {
    my $requires_password = shift;
    $requires_password = 1 if !defined $requires_password;

    my $sth = connector->dbh->prepare(
        "DELETE FROM networks where address='10.0.0.0/24'"
    );
    $sth->execute;
        $sth = connector->dbh->prepare(
        "INSERT INTO networks (name,address,all_domains,requires_password)"
        ."VALUES('10','10.0.0.0/24',1,?)"
    );
    $sth->execute($requires_password);
}


# expose a port when the host is down
sub test_host_down {
    my $vm_name = shift;

    flush_rules();

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = create_domain($vm_name, user_admin,'debian stretch');

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->shutdown_now(user_admin)    if $domain->is_active;

    my $internal_port = 22;
    my ($public_port);
    eval { ($public_port) = $domain->expose($internal_port) };
    is($@,'') or return;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    _wait_requests($domain);

    my $domain_ip = $domain->ip;
    ok($domain_ip,"[$vm_name] Expecting an IP for domain ".$domain->name.", got ".($domain_ip or '')) or return;

    is(scalar $domain->list_ports,1);

    my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok($n_rule,"Expecting rule for -> $local_ip:$public_port") or confess;

    local $@ = undef;
    eval { $domain->shutdown_now(user_admin) };
    is($@, '');

    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;
}

sub test_req_expose($vm_name) {
    flush_rules();

    my $domain = create_domain($vm_name, user_admin,'debian stretch');

    my $remote_ip = '10.0.0.6';

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    _wait_ip($vm_name, $domain);

    my $internal_port = 22;
    my $req = Ravada::Request->expose(
                   uid => user_admin->id
            ,port => $internal_port
            ,id_domain => $domain->id
    );
    rvd_back->_process_all_requests_dont_fork();

    is($req->status(),'done');
    is($req->error(),'');

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1) or exit;
    my $public_port = $list_ports[0]->{public_port};

    my $vm = rvd_back->search_vm($vm_name);
    my $local_ip = $vm->ip;
    my $domain_ip = $domain->ip;

    my ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok($n_rule,"Expecting rule for -> $local_ip:$public_port") or exit;

    $domain->remove(user_admin);

    is(scalar $domain->list_ports,0) or exit;
    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
    );

    ok(!$n_rule,"Expecting no rule for -> $local_ip:$public_port") or exit;

}

sub test_can_expose_ports {
    is(user_admin->can_expose_ports,1);

    my $user = create_user('foo','bar');
    is($user->is_admin,0);
    is($user->can_expose_ports,undef);

    user_admin->grant($user,'expose_ports');
    is($user->can_expose_ports,1);

    $user->remove();

}

sub test_restricted($vm, $restricted) {
    flush_rules();
    flush_rules_node($vm);

    my $domain = create_domain($vm->type, user_admin,'debian Stretch');

    my $local_ip = $vm->ip;
    my $remote_ip = '10.0.0.6';

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    _wait_ip($vm->type, $domain);

    my $internal_port = 22;
    $domain->expose(port => $internal_port, restricted => $restricted);

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1) or exit;
    my $public_port = $list_ports[0]->{public_port};
    is($list_ports[0]->{restricted}, $restricted);

    my ($n_rule)
        = search_iptable_remote(
            local_ip => "$local_ip/32"
            , remote_ip => $remote_ip
            , local_port => $public_port
            , node => $vm
            , jump => 'ACCEPT'
    );
    my ($n_rule_drop)
        = search_iptable_remote(
            local_ip => "$local_ip/32"
            , local_port => $public_port
            , node => $vm
            , jump => 'DROP'
    );

    if ($restricted) {
        ok($n_rule,"Expecting rule for $remote_ip -> $local_ip:$public_port") or exit;
        ok($n_rule_drop,"Expecting drop rule for any -> $local_ip:$public_port") or exit;
    } else {
        ok(!$n_rule,"Expecting no rule for $remote_ip -> $local_ip:$public_port") or exit;
        ok(!$n_rule_drop,"Expecting drop no rule for any -> $local_ip:$public_port") or exit;
    }

    # check for FORWARD
    my $local_net = $domain->ip;
    $local_net =~ s/\.\d+$//;
    $local_net = "$local_net.0/24";
    ($n_rule)
        = search_iptable_remote(local_ip => "$local_ip/32"
            , chain => 'FORWARD'
            , node => $vm
            , jump => 'ACCEPT'
            , local_ip => $local_net
    );
    ok($n_rule,"Expecting rule in forward to -> $local_net") or exit;

    $domain->shutdown_now(user_admin);
    ($n_rule)
        = search_iptable_remote(
            local_ip => "$local_ip/32"
            , remote_ip => $remote_ip
            , local_port => $public_port
            , node => $vm
            , jump => 'ACCEPT'
    );
    ($n_rule_drop)
        = search_iptable_remote(
            local_ip => "$local_ip/32"
            , local_port => $public_port
            , node => $vm
            , jump => 'DROP'
    );

    ok(!$n_rule,"Expecting no rule for $remote_ip -> $local_ip:$public_port") or exit;
    ok(!$n_rule_drop,"Expecting drop no rule for any -> $local_ip:$public_port") or exit;

    $domain->remove(user_admin);
}

sub test_change_expose($vm, $restricted) {
    my $domain = create_domain($vm->type, user_admin,'debian');

    my $internal_port = 22;
    my $name = "foo";
    $domain->expose(port => $internal_port, restricted => $restricted, name => $name);

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1) or exit;
    my $public_port = $list_ports[0]->{public_port};
    is($list_ports[0]->{restricted}, $restricted);
    is($list_ports[0]->{name}, $name);

    $restricted = !$restricted;
    $name = "$name bar";
    $domain->expose(
             id_port => $list_ports[0]->{id}
              , name => $name
        , restricted => $restricted
    );

    @list_ports = $domain->list_ports();
    is(scalar @list_ports,1) or exit;
    is($list_ports[0]->{public_port} , $public_port);
    is($list_ports[0]->{restricted}, $restricted);
    is($list_ports[0]->{name}, $name);

    $domain->remove(user_admin);
}

sub test_change_expose_3($vm) {
    my $domain = create_domain($vm->type, user_admin,'debian stretch');

    my $internal_port = 100;
    my $name = "foo";
    for my $n ( 1 .. 3 ) {
        my $restricted = 0;
        $restricted = 1 if $n == 2;
        $domain->expose(port => $internal_port+$n , restricted => $restricted);
    }

    my $remote_ip = '10.0.0.4';
    $domain->start(user => user_admin, remote_ip => $remote_ip);

    _wait_ip($vm->type, $domain);
    rvd_back->_process_requests_dont_fork(1);

    _wait_requests($domain);
    _check_port_rules($domain, $remote_ip);

    is($domain->list_ports, 3);
    for my $port ($domain->list_ports) {
        my $restricted = ! $port->{restricted};
        $domain->expose(id_port => $port->{id}, restricted => $restricted);
        _check_port_rules($domain, $remote_ip
            ,"Changed port $port->{internal_port} restricted=$restricted");
    }

    $domain->remove(user_admin);
}
sub _check_port_rules($domain, $remote_ip, $msg='') {
    for my $port ( $domain->list_ports ) {
        my ($n_rule, $n_rule_drop, $n_rule_nat)
            =_search_rules($domain, $remote_ip, $port->{internal_port}, $port->{public_port});
        ok($n_rule_nat,"Expecting NAT rule ".Dumper($port)."\n$msg")
            or confess;
        if ($port->{restricted}) {
            ok($n_rule);
            ok($n_rule_drop);
        } else {
            ok(!$n_rule);
            ok(!$n_rule_drop);
        }
    }
}

sub _search_rules($domain, $remote_ip, $internal_port, $public_port) {
    my $local_ip = $domain->_vm->ip;

    my ($n_rule) = search_iptable_remote(
        local_ip => "$local_ip/32"
        , remote_ip => $remote_ip
        , local_port => $public_port
        , node => $domain->_vm
        , jump => 'ACCEPT'
    );
    my ($n_rule_drop)
    = search_iptable_remote(
        local_ip => "$local_ip/32"
        , local_port => $public_port
        , node => $domain->_vm
        , jump => 'DROP'
    );
    my ($n_rule_nat)
    = search_iptable_remote(local_ip => "$local_ip/32"
        , local_port => $public_port
        , table => 'nat'
        , 'to-destination' => $domain->ip.":".$internal_port
        , chain => 'PREROUTING'
        , node => $domain->_vm
        , jump => 'DNAT'
    );

    return($n_rule, $n_rule_drop, $n_rule_nat);
}

sub _wait_requests($domain) {
    _wait_ip($domain->_vm->type, $domain);
    for (;;) {
        rvd_back->_process_requests_dont_fork(1);
        last if !$domain->list_requests(1);
        sleep 1;
    }
}

##############################################################

#clean();

init();
Test::Ravada::_clean_db();

add_network_10(0);

test_can_expose_ports();
for my $vm_name ( 'KVM', 'Void' ) {

    my $vm = rvd_back->search_vm($vm_name);
    next if !$vm;

    diag("Testing $vm_name");

    test_restricted($vm,0);
    test_restricted($vm,1);

    test_change_expose($vm, 0);
    test_change_expose($vm, 1);

    test_change_expose_3($vm);

    test_host_down($vm_name);

    test_req_remove_expose($vm_name);
    test_crash_domain($vm_name);
    test_req_expose($vm_name);

    test_one_port($vm);
    test_two_ports($vm);

    test_clone_exports($vm);

}

flush_rules();
clean();
done_testing();
