use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;
use IPTables::ChainMgr;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

sub test_no_dupe($vm) {

    flush_rules($vm);

    my $domain = create_domain($vm->type, user_admin ,'debian stretch');

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    my ($internal_port, $name_port) = (22, 'ssh');

    my ($in, $out, $err);
    run3(['/sbin/iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*/,@out),0);

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*192.168.\d+\.0/24\sstate NEW},@out),0);

    $domain->start(user => user_admin, remote_ip => $remote_ip);
    my @request = $domain->list_requests();

    # No requests because no ports exposed
    is(scalar @request,0) or exit;
    delete_request('enforce_limits');
    wait_request(debug => 0, background => 0);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);
    my $public_port;
    my $internal_ip = _wait_ip($vm->type, $domain) or die "Error: no ip for ".$domain->name;
    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    ($public_port) = $domain->expose(
        port => $internal_port
        , name => $name_port
        , restricted => 1
    );
    delete_request('enforce_limits');
    wait_request(background => 0, debug => 0);

    run3(['/sbin/iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1);

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1,"Expecting rule for $internal_net")
        or die $out;

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

    ##########################################################################
    #
    # start again check only one instance of each
    #
    $domain->start(user => user_admin, remote_ip => $remote_ip);
    is($domain->is_active,1);
    run3(['/sbin/iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1);

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1) or die $out;

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

    test_hibernate($domain, $local_ip, $public_port, $internal_ip, $internal_port,$remote_ip);
    test_start_after_hibernate($domain, $local_ip, $public_port, $internal_ip, $internal_port,$remote_ip);
    $domain->remove(user_admin);

    flush_rules($vm);
}

sub test_hibernate($domain
        ,$local_ip, $public_port, $internal_ip, $internal_port, $remote_ip) {
    $domain->hibernate(user_admin);
    is($domain->is_hibernated,1);

    my ($in,$out,$err);
    run3(['/sbin/iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),0);

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*192.168.\d+\.0/24\sstate NEW},@out),0);

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),0) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),0) or die $out;

}

sub test_start_after_hibernate($domain
        ,$local_ip, $public_port, $internal_ip, $internal_port, $remote_ip) {

    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    delete_request('enforce_limits');
    wait_request(debug => 0, background => 0);

    my ($in,$out,$err);
    run3(['/sbin/iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1);

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1) or die $out;

    run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

}


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
    delete_request('enforce_limits');
    wait_request(debug => 0, background => 0);

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

sub test_clone_exports_add_ports($vm) {

    my $base = create_domain($vm, user_admin,'debian stretch');
    $base->expose(port => 22, name => "ssh");
    my @base_ports0 = $base->list_ports();

    $base->prepare_base(user => user_admin, with_cd => 1);

    my $clone = $base->clone(name => new_domain_name, user => user_admin);
    $base->expose(port => 80, name => "web");
    my @base_ports = $base->list_ports();
    is(scalar @base_ports, scalar @base_ports0 + 1);

    my $clone_f = Ravada::Front::Domain->open($clone->id);
    eval { my $info = $clone_f->info(user_admin) };
    is($@,'');

    $clone->start(remote_ip => '10.1.1.1', user => user_admin);
    my @clone_ports = $clone->list_ports();
    is(scalar @clone_ports,2 );

    for my $n ( 0 .. 1 ) {
        is($base_ports[$n]->{internal_port}, $clone_ports[$n]->{internal_port});
        isnt($base_ports[$n]->{public_port}, $clone_ports[$n]->{public_port},"Same public port in clone and base for ".$base_ports[$n]->{internal_port});
        is($base_ports[$n]->{name}, $clone_ports[$n]->{name});
    }
    _wait_ip($vm, $clone);
    wait_request( );
    my @out = split /\n/, `iptables -t nat -L PREROUTING -n`;
    ok(grep /dpt:\d+.*\d+:22/, @out);
    ok(grep /dpt:\d+.*\d+:80/, @out);

    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub _wait_ip {
    my $vm_name = shift;
    my $domain = shift  or confess "Missing domain arg";

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
    wait_request(debug => 0, background => 0);

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
    my $internal_ip = $domain->ip;

    my $internal_port = 22;
    $domain->expose(port => $internal_port, restricted => $restricted);

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1) or exit;
    my $public_port = $list_ports[0]->{public_port};
    is($list_ports[0]->{restricted}, $restricted);

    my $remote_ip_check ='0.0.0.0/0';
    $remote_ip_check = $remote_ip if $restricted;
    my ($n_rule)
        = search_iptable_remote(
            local_ip => "$internal_ip/32"
            , chain => 'FORWARD'
            , remote_ip => $remote_ip_check
            , local_port => $internal_port
            , node => $vm
            , jump => 'ACCEPT'
    );
    my ($n_rule_drop)
        = search_iptable_remote(
            local_ip => "$internal_ip/32"
            , chain => 'FORWARD'
            , local_port => $internal_port
            , node => $vm
            , jump => 'DROP'
    );

    ok($n_rule,"Expecting rule for $remote_ip_check -> $internal_ip:$internal_port")
        or exit;
    if ($restricted) {
        ok($n_rule_drop,"Expecting drop rule for any -> $internal_ip:$internal_port") or exit;
    } else {
        ok(!$n_rule_drop,"Expecting drop no rule for any -> $internal_ip:$internal_port") or exit;
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

    my $internal_ip = _wait_ip($vm->type, $domain);
    rvd_back->_process_requests_dont_fork();

    _wait_requests($domain);

    is($domain->list_ports, 3);
    for my $port ($domain->list_ports) {
        my $restricted = ! $port->{restricted};
        $domain->expose(id_port => $port->{id}, restricted => $restricted);
        wait_request(background => 0, debug => 0);
        my ($in, $out, $err);
        run3(['/sbin/iptables','-L','FORWARD','-n'],\($in, $out, $err));
        my @out = split /\n/,$out;
        if ($restricted) {
            my $port_re = qr{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$port->{internal_port}};
            is(grep(m{$port_re}
                    ,@out),1)
                or die "Expecting $port_re in $out";
            is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$port->{internal_port}},@out),1)
                or die $out;
        } else {
            is(grep(m{^ACCEPT.*0.0.0.0/0\s+$internal_ip.*dpt:$port->{internal_port}},@out),1)
                or die $out;
        }
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
            ok($n_rule) or confess;
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
        rvd_back->_process_requests_dont_fork();
        last if !$domain->list_requests(1);
        sleep 1;
    }
    delete_request('enforce_limits');
    wait_request( background => 0 );
}

##############################################################

clean();

init();
Test::Ravada::_clean_db();

add_network_10(0);

test_can_expose_ports();
for my $vm_name ( 'KVM', 'Void' ) {

    my $vm = rvd_back->search_vm($vm_name);
    next if !$vm;

    diag("Testing $vm_name");
    test_clone_exports_add_ports($vm);

    test_no_dupe($vm);

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
