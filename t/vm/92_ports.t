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

sub test_no_dupe($vm) {

    flush_rules($vm);

    my $domain= $BASE->clone(name => new_domain_name, user => user_admin);

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    my ($internal_port, $name_port) = (22, 'ssh');

    my ($in, $out, $err);
    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*/,@out),0);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*192.168.\d+\.0/24\sstate NEW},@out),0);

    $domain->start(user => user_admin, remote_ip => $remote_ip);
    my @request = grep { $_->command ne 'set_time'} $domain->list_requests();

    # No requests because no ports exposed
    is(scalar @request,0) or exit;
    delete_request('enforce_limits','set_time');
    wait_request(debug => 0);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);
    my $public_port;
    my $internal_ip = _wait_ip2($vm->type, $domain) or die "Error: no ip for ".$domain->name;
    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    ($public_port) = $domain->expose(
        port => $internal_port
        , name => $name_port
        , restricted => 1
    );
    delete_request('enforce_limits','set_time');
    wait_request(debug => 0);

    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1,"Expecting rule for $internal_net")
        or die $out;

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

    ##########################################################################
    #
    # start again check only one instance of each
    #
    $domain->start(user => user_admin, remote_ip => $remote_ip);
    is($domain->is_active,1);
    Ravada::Request->start_domain(uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip
    );
    wait_request();
    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1) or die $out;

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
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
    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    my @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),0);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*192.168.\d+\.0/24\sstate NEW},@out),0);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),0) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),0) or die $out;

}

sub test_start_after_hibernate($domain
        ,$local_ip, $public_port, $internal_ip, $internal_port, $remote_ip) {

    my $internal_net = $internal_ip;
    $internal_net =~ s{(.*)\.\d+$}{$1.0/24};

    my ($in,$out,$err);
    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    my @out = split /\n/,$out;
    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    @out = split /\n/,$out;
    delete_request('open_exposed_ports');
    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip
    );

    delete_request('enforce_limits');
    wait_request(debug => 0, skip => ['set_time', 'enforce_limits']);

    run3(['iptables','-t','nat','-L','PREROUTING','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(/^DNAT.*$local_ip.*dpt:$public_port to:$internal_ip:$internal_port/,@out),1);

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$internal_net\s+state NEW},@out),1) or die $domain->name."\n".$out;

    run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
    die $err if $err;
    @out = split /\n/,$out;
    is(grep(m{^ACCEPT.*$remote_ip\s+$internal_ip.*dpt:$internal_port},@out),1) or die $out;
    is(grep(m{^DROP.*0.0.0.0.+$internal_ip.*dpt:$internal_port},@out),1) or die $out;

}


##############################################################
# Forward one port
sub test_one_port($vm) {

    flush_rules();

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

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
    wait_request();
    ok($port_info2);
    is_deeply($port_info2, $port_info);

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1);

    my $info = $domain->info(user_admin);
    ok($info->{ports});
    is($info->{ports}->[0]->{internal_port}, $internal_port);
    is($info->{ports}->[0]->{public_port}, $public_port);
    is($info->{ports}->[0]->{name}, $name_port);

    my $n_rule;
    for ( 1 .. 10 ) {
        ($n_rule)    = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
            , 'to-destination' => $domain_ip.":".$internal_port
        );
        last if $n_rule;
        $domain->start(user => user_admin, remote_ip => $remote_ip);
        wait_request();
    }

    ok($n_rule,"Expecting rule for $local_ip:$public_port -> $domain_ip:internal_port") or exit;


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
    wait_request();

    #################################################################
    # start
    #
    $domain->start(user => user_admin, remote_ip => $remote_ip);
    _wait_ip($vm, $domain);
    delete_request('enforce_limits','set_time');
    wait_request(debug => 0);
    _wait_open_port($domain,$internal_port);

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

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

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
        wait_request();

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

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $client_ip = $domain->remote_ip();
    is($client_ip, $remote_ip);

    _wait_ip($vm, $domain, $remote_ip);

    my $domain_ip = $domain->ip or do {
        diag("[$vm_name] Expecting an IP for domain ".$domain->name);
        return;
    };

    my $internal_port = 22;
    my $public_port = $domain->expose($internal_port);
    wait_request();

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

    my $domain2 = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain2->start(user => user_admin) if !$domain2->is_active;

    $domain2->remove(user_admin);
}

sub test_two_ports($vm) {

    flush_rules();

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

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

sub test_clone_exports_spinoff($vm) {
    test_clone_exports($vm,1);
}

sub test_clone_exports($vm, $spinoff=0) {

    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->spinoff() if $spinoff;
    $base->expose(port => 22, name => "ssh");

    my @base_ports = $base->list_ports();
    is(scalar @base_ports,1);

    my $clone = $base->clone(name => new_domain_name, user => user_admin);

    my @clone_ports = $clone->list_ports();
    is(scalar @clone_ports,1, "Expecting ports listed spinoff=$spinoff" );

    is($base_ports[0]->{internal_port}, $clone_ports[0]->{internal_port});
    isnt($base_ports[0]->{public_port}, $clone_ports[0]->{public_port});
    is($base_ports[0]->{name}, $clone_ports[0]->{name});

    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_routing_hibernated($vm) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    my $internal_port = 22;

    $base->expose(port => $internal_port , name => "ssh");

    my @base_ports0 = $base->list_ports();

    my $remote_ip = '4.4.4.4';
    $base->start(remote_ip => $remote_ip,  user => user_admin);

    _wait_ip($vm, $base);
    wait_request( debug => 0 );

    my @base_ports1 = $base->list_ports();

    my $public_port1 = $base_ports1[0]->{public_port};

    my @lines = _wait_open_port($base,$internal_port);
    is (scalar @lines,1) or die Dumper(\@lines);

    my ($out, $err) = $vm->run_command("iptables-save");
    my @lines0 = grep(/-A FORWARD .*ACCEPT$/, split/\n/,$out);
    my $internal_ip = $base->ip;
    @lines = grep(m{d $internal_ip/32 .*dport $internal_port}, @lines0);
    is (scalar @lines,1,"Expecting 1 line $internal_ip .*dport $internal_port")
        or die Dumper($internal_ip,\@lines0);


    hibernate_domain_internal($base);

    $base->start(remote_ip => $remote_ip,  user => user_admin);

    _wait_ip($vm, $base);
    wait_request( debug => 0 );

    my @base_ports2 = $base->list_ports();

    my $public_port2 = $base_ports2[0]->{public_port};

    is($public_port2, $public_port1) or exit;

    _wait_open_port($base, $internal_port);
    $internal_ip = $base->ip;
    ($out, $err) = $vm->run_command("iptables-save");
    @lines = grep(/$internal_ip:$internal_port/, split /\n/,$out);
    is (scalar @lines,1) or die Dumper(\@lines);

    @lines0 = grep(/-A FORWARD .*ACCEPT$/, split/\n/,$out);
    @lines = grep(m{d $internal_ip/32 .*dport $internal_port}, @lines0);
    is (scalar @lines,1,"Expecting 1 line $internal_ip .*dport $internal_port")
        or die Dumper($internal_ip,\@lines0);

    $base->remove(user_admin);
}

sub test_routing_already_used($vm, $source=0, $restricted=0) {
    diag("test routing already used source=$source, restricted=$restricted");
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    my $internal_port = 22;
    $restricted = 1 if $restricted;
    $base->expose(port => $internal_port, name => "ssh", restricted => $restricted);
    my @base_ports0 = $base->list_ports();

    my $public_port0 = $base_ports0[0]->{public_port};

    my @source;
    @source = ( 's' => '0.0.0.0/0') if $source;
    my @iptables_before = _iptables_save($vm,'nat' ,'PREROUTING');
    my @rule = (
            t => 'nat'
            ,A => 'PREROUTING'
            ,p => 'tcp'
            ,dport => $public_port0
            ,j => 'DNAT'
            ,'to-destination' => "1.2.3.4:1111"
            ,@source
        );
    $vm->iptables( @rule );

    my @iptables0 = _iptables_save($vm,'nat','PREROUTING');
    my $remote_ip = '3.3.3.3';
    $base->start(remote_ip => $remote_ip,  user => user_admin);

    _wait_ip($vm, $base);
    my $internal_ip = $base->ip;
    wait_request( debug => 0 , skip => ['set_time','enforce_limits'] );
    rvd_back->_check_duplicated_prerouting();
    _wait_open_port($base, $internal_port);

    my @base_ports1 = $base->list_ports();

    my $public_port1 = $base_ports1[0]->{public_port};

    isnt($public_port1, $public_port0,$base->name." ".Dumper(\@base_ports1)) or exit;
    my @iptables1 = _iptables_save($vm,'nat' ,'PREROUTING',['1.2.3.4',$internal_ip]);

    ok(scalar(@iptables1)>=2) or die "Expecting at least 2 preroutings ".Dumper(\@iptables1);
    #is(scalar(@iptables1),scalar(@iptables0)+1,"Expecting 1 chain more "
    #.Dumper(\@iptables0,\@iptables1)) or exit;

    my @lines0 = grep(/-A FORWARD .*ACCEPT$/, _iptables_save($vm));
    my @lines = grep(m{d $internal_ip/32 .*dport $internal_port}, @lines0);
    is (scalar @lines,1,"Expecting 1 line $internal_ip .*dport $internal_port")
        or die Dumper($internal_ip,\@lines0);

    # start again the machine, nothing should change
    for ( 1 .. 3 ) {
        my $req = Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $base->id
            ,remote_ip => $remote_ip
        );
        wait_request(debug => 0);
        is($req->status,'done');
        is($req->error, '');
        $internal_ip = _wait_ip($vm,$base);

        my @base_ports2 = $base->list_ports();

        my $public_port2 = $base_ports2[0]->{public_port};

        isnt($public_port2, $public_port0) or exit;
        is($public_port2, $public_port1) or exit;

        my @iptables2 = _iptables_save($vm,'nat' ,'PREROUTING',['1.2.3.4',$internal_ip]);
        is(scalar(@iptables1),scalar(@iptables2)) or die Dumper(\@iptables1,\@iptables2);

        my ($out, $err) = $vm->run_command("iptables-save");
        my @lines = grep(/$internal_ip:$internal_port/, split /\n/,$out);
        is (scalar @lines,1) or die Dumper(\@lines);

        my @lines0 = grep(/-A FORWARD /, split/\n/,$out);
        @lines = grep(m{d $internal_ip/32 .*dport $internal_port -j ACCEPT}, @lines0);
        is (scalar @lines,1,"Expecting 1 line $internal_ip .*dport $internal_port")
        or die Dumper($internal_ip,\@lines0);

        if ($restricted) {
            @lines = grep(m{d $internal_ip/32 .*dport 22 -j DROP}, @lines0);
            is (scalar @lines,1,"Expecting 1 $internal_ip .*dport $internal_port -j DROP")
            or die Dumper($internal_ip,\@lines0);
        }

    }

    # open again the ports, nothing should change
    for ( 1 .. 3 ) {
        my $req = Ravada::Request->open_iptables(
            uid => user_admin->id
            ,id_domain => $base->id
            ,remote_ip => $remote_ip
        );
        wait_request(debug => 0);
        is($req->status,'done');
        is($req->error, '');

        my @base_ports2 = $base->list_ports();

        my $public_port2 = $base_ports2[0]->{public_port};

        isnt($public_port2, $public_port0) or exit;
        is($public_port2, $public_port1) or exit;

        my @iptables2 = _iptables_save($vm,'nat' ,'PREROUTING');
        is(scalar(@iptables1),scalar(@iptables2)) or die Dumper(\@iptables1,\@iptables2);

        my ($out, $err) = $vm->run_command("iptables-save");
        my @lines = grep(/$internal_ip:$internal_port/, split /\n/,$out);
        is (scalar @lines,1) or die Dumper(\@lines);

        my @lines0 = grep(/-A FORWARD .*ACCEPT$/, split/\n/,$out);
        @lines = grep(m{d $internal_ip/32 .*dport $internal_port}, @lines0);
        is (scalar @lines,1,"Expecting 1 line $internal_ip .*dport $internal_port")
        or die Dumper($internal_ip,\@lines0);
    }

    $base->remove(user_admin);

    _clean_iptables($vm, @rule );
}

sub _iptables_save($vm,$table=undef,$chain=undef, $ips=undef) {
    if (defined $ips && !ref($ips)) {
        $ips = [$ips];
    }
    my @cmd = ("iptables-save");
    push @cmd,("-t",$table) if $table;

    my ($out,$err) = $vm->run_command(@cmd);

    my @out;
    for my $line (split /\n/,$out) {
        next if $chain && $line !~ /^-A $chain/;
        if ($ips) {
            my $found = 0;
            my ($to) = $line =~ /--to-destination (\d+\.\d+\.\d+\.\d+)/;
            next if !$to;
            for my $ip (@$ips) {
                $found++ if $to eq $ip;
            }
            next if !$found;
        }
        push @out,($line);
    }
    return @out;
}

sub test_interfaces($vm) {
    return if $vm->type ne 'KVM';
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain->start( remote_ip => '10.1.1.2', user => user_admin);

    _wait_ip2($vm, $domain);
    my $info = $domain->info(user_admin);

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info_f = $domain_f->info(user_admin);
    ok(exists $info_f->{ip},"Expecting ip in front domain info");
    is($info_f->{ip}, $domain->ip);

    die $domain->name if !exists $info_f->{interfaces};
    ok(exists $info_f->{interfaces},"Expecting interfaces on ".$domain->_vm->type)
        and isa_ok($info_f->{interfaces},"ARRAY","Expecting mac address is a list")
        and do {
            my $found = 0;
            for my $if (@{$info_f->{interfaces}}) {
                $found++;
                like($if->{hwaddr}, qr/^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]/);
            }
            ok($found,"Expecting some interfaces, found=$found") or exit;
        };

    $domain->remove(user_admin);
}

sub test_port_already_open($vm) {
    diag("Test redirect ip duplicated ".$vm->type);
    flush_rules();
    my $internal_port = 22;
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

    my $remote_ip0 = '10.1.1.2';
    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip0
    );
    my $ip = _wait_ip2($vm, $domain, $remote_ip0);
    wait_request(debug => 0, skip => [ 'set_time','enforce_limits']);

    my $display = $domain->display_info(user_admin);
    my $port = $display->{port};
    shutdown_domain_internal($domain);
    my $sth = connector->dbh->prepare("DELETE FROM iptables");
    $sth->execute();

    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => '10.1.1.33'
    );
    wait_request();

    my @out = split /\n/, `iptables-save`;
    my @port_accept;
    for ( 1 .. 10 ) {
        @port_accept = (grep /--dport $port -j ACCEPT/, @out);
        last if scalar(@port_accept)==1;
        rvd_back->_check_duplicated_prerouting();
        rvd_back->_check_duplicated_iptable();
        Ravada::Request->refresh_vms();
        wait_request();
    }
    is(scalar(@port_accept),1) or die Dumper(\@port_accept);

    my @port_drop = (grep /--dport $port -j DROP/, @out);
    is(scalar(@port_drop),1) or die Dumper(\@port_drop);

    remove_domain($domain);
}

sub test_port_prerouting_already_open($vm) {
    diag("Test redirect ip duplicated prerouting ".$vm->type);
    flush_rules();
    my $internal_port = 29;
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain->expose(port => $internal_port
        , name => "ssh"
        , restricted => 1
    );
    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => '10.1.1.2'
    );
    wait_request();
    shutdown_domain_internal($domain);
    my $sth = connector->dbh->prepare("DELETE FROM iptables");
    $sth->execute();
    my $remote_ip = '10.1.1.35';
    my @port;
    for ( 1 .. 3 ) {
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,remote_ip => $remote_ip
            ,_force => 1
        );
        wait_request();

        my $domain_ip  =$domain->ip;
        for ( 1 .. 60 ) {
            last if $domain_ip;
            sleep 1;
            $domain_ip  =$domain->ip;
        }

        my @out = split /\n/, `iptables-save`;

        @port = (grep /-s $remote_ip.32.*--dport $internal_port -j ACCEPT/, @out);

        my @port_prerouting = (grep /-A PREROUTING.*--to-destination .*$domain_ip:$internal_port$/, @out);
        last if scalar(@port)==1 && scalar(@port_prerouting)==1;
        rvd_back->_check_duplicated_prerouting() if scalar(@port_prerouting)>1;

        sleep 1;
    }
    if(scalar(@port)>1) {
        rvd_back->_check_duplicated_prerouting();
        rvd_back->_check_duplicated_iptable();
        wait_request();
    }

    my @out = split /\n/, `iptables-save`;

    @port = (grep /-s $remote_ip.32.*--dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port),1,"Expecting $internal_port") or die Dumper(\@port);

    my $domain_ip  =$domain->ip;
    my @port_drop = (grep /-d $domain_ip.*--dport $internal_port -j DROP/, @out);
    is(scalar(@port_drop),1) or die Dumper(\@port_drop);

    my @port_prerouting = (grep /-A PREROUTING.*--to-destination .*$domain_ip:$internal_port$/, @out);
    is(scalar(@port_prerouting),1) or die Dumper(\@port_prerouting);

    #    my @port_one= (grep /--dport $internal_port -j ACCEPT/, @out);
    # is(scalar(@port_one),1,"Expecting $internal_port") or die Dumper(\@port_one);

    $domain_ip = $domain->ip;
    remove_domain($domain);
    @out = split /\n/, `iptables-save`;
    @port = (grep /-d $domain_ip.*--dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port),0,"Expecting $internal_port") or die Dumper(\@port);

    @port_drop = (grep /-d $domain_ip.*--dport $internal_port -j DROP/, @out);
    is(scalar(@port_drop),0) or die Dumper(\@port_drop);

}

sub test_port_prerouting_already_open_clones($vm) {
    diag("Test redirect ip duplicated prerouting clones ".$vm->type);
    flush_rules();
    my $internal_port = 22;
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->expose(port => $internal_port
        , name => "ssh"
        , restricted => 1
    );
    my $clone1 = $base->clone(user=> user_admin,name => new_domain_name);
    my $clone2 = $base->clone(user=> user_admin,name => new_domain_name);
    my $n=0;
    for my $clone ($clone1, $clone2) {
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,remote_ip => '10.1.1.1'.(++$n)
        );
    }
    wait_request();

    shutdown_domain_internal($clone1);
    shutdown_domain_internal($clone2);
    my $sth = connector->dbh->prepare("DELETE FROM iptables");
    $sth->execute();
    my $remote_ip1 = '10.1.1.31';
    my $remote_ip2 = '10.1.1.32';
    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $clone1->id
        ,remote_ip => $remote_ip1
    );
    wait_request(debug => 0);
    my $ip1 = _wait_ip2($vm, $clone1);
    ok($ip1) or die "No ip for ".$clone1->name;

    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $clone2->id
        ,remote_ip => $remote_ip2
    );
    wait_request(debug => 0);

    my $ip2 = _wait_ip2($vm, $clone2);
    ok($ip2) or die "No ip for ".$clone2->name;;

    wait_request(debug => 0);

    my @out;
    for ( 1 .. 10 ) {
        @out = split /\n/, `iptables-save`;
        my $a1 = (grep /-s $remote_ip1.*--dport $internal_port -j ACCEPT/, @out);
        my $a2 = (grep /-s $remote_ip2.32.*--dport $internal_port -j ACCEPT/, @out);
        last if $a1 && $a2;
        diag("Waiting for $remote_ip1 and $remote_ip2");
        sleep 1;
    }

    my @port1 = (grep /-s $remote_ip1.*--dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port1),1,"Expecting -s $remote_ip1 --dport $internal_port -j ACCEPT") or die Dumper(\@port1);

    @port1 = (grep /-d $ip1.32 .*--dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port1),1,"Expecting -s $remote_ip1 --dport $internal_port -j ACCEPT") or die Dumper(\@port1);

    my @port2 = (grep /-s $remote_ip2.32.*--dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port2),1,"Expecting -s $remote_ip2.* --dport $internal_port") or die Dumper(\@port2);
    my $req_refresh = Ravada::Request->refresh_vms(_force => 1);
    for ($clone1, $clone2) {
        my $req_ref = Ravada::Request->refresh_machine(id_domain => $_->id
            ,uid => user_admin->id
        );
        wait_request($req_ref);
    }
    wait_request($req_refresh);

    my @port_drop = (grep /--dport $internal_port -j DROP/, @out);
    ok(scalar(@port_drop) >= 2) or die Dumper(\@port_drop);

    my @port_prerouting = (grep /-A PREROUTING.*--to-destination .*:$internal_port$/, @out);
    ok(scalar(@port_prerouting) >= 2) or die Dumper(\@port_prerouting);

    $clone1->shutdown_now(user_admin);
    wait_request();

    _check_one_port($remote_ip2, $internal_port, $clone2->ip);

    remove_domain($clone1);
    remove_domain($clone2);
    remove_domain($base);

}

sub test_port_prerouting_already_open_clones_no_restricted($vm) {
    diag("Test redirect ip duplicated prerouting clones no restricted ".$vm->type);
    flush_rules();
    my $internal_port = 22;
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->expose(port => $internal_port
        , name => "ssh"
    );
    my $clone1 = $base->clone(user=> user_admin,name => new_domain_name);
    my $clone2 = $base->clone(user=> user_admin,name => new_domain_name);
    my $n=0;
    for my $clone ($clone1, $clone2) {
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,remote_ip => '10.1.1.1'.(++$n)
        );
    }
    wait_request();
    shutdown_domain_internal($clone1);
    shutdown_domain_internal($clone2);
    my $sth = connector->dbh->prepare("DELETE FROM iptables");
    $sth->execute();
    my $remote_ip1 = '198.18.0.1';
    my $remote_ip2 = '198.18.0.2';
    my $req_s1=Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $clone1->id
        ,remote_ip => $remote_ip1
    );
    ok($req_s1);
    wait_request(debug=>0);
    my $ip1 = _wait_ip2($vm, $clone1);
    ok($ip1) or die "No ip for ".$clone1->name;

    my $req_s2 = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $clone2->id
        ,remote_ip => $remote_ip2
    );
    ok($req_s2);
    isnt($req_s2->id, $req_s1->id);
    wait_request( debug => 0);

    my $ip2 = _wait_ip2($vm, $clone2);
    ok($ip2) or die "No ip for ".$clone2->name;;

    wait_request(debug => 0);

    my @out;
    for ( 1 .. 10 ) {
        @out = split /\n/, `iptables-save`;
        my @port1 = (grep /-A FORWARD -d $ip1.32 -p tcp -m tcp --dport $internal_port -j ACCEPT/, @out);
        last if @port1;
        $req_s2->status('requested');
        $req_s1->status('requested');
        wait_request();
        sleep 1;
    }

    my @port1 = (grep /-A FORWARD -d $ip1.32 -p tcp -m tcp --dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port1),1,"Expecting -d $ip1 --dport $internal_port -j ACCEPT ".$clone2->name) or die Dumper(\@port1);

    my @port2 = (grep /-A FORWARD -d $ip2.32 -p tcp -m tcp --dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port2),1,"Expecting -d $ip2 ... --dport $internal_port") or die Dumper(\@port2);

    my @port_drop = (grep /--dport $internal_port -j DROP/, @out);
    is(scalar(@port_drop),0) or die Dumper(\@port_drop);

    my @port_prerouting = (grep /-A PREROUTING.*--to-destination $ip1:$internal_port$/, @out);
    is(scalar(@port_prerouting),1) or die Dumper(\@port_prerouting);

    @port_prerouting = (grep /-A PREROUTING.*--to-destination $ip2:$internal_port$/, @out);
    is(scalar(@port_prerouting),1) or die Dumper(\@port_prerouting);

    $clone1->shutdown_now(user_admin);
    wait_request();

    for ( 1 .. 5 ) {
        @out = split /\n/, `iptables-save`;
        @port1 = (grep /-A FORWARD -d $ip1.32 -p tcp -m tcp --dport $internal_port -j ACCEPT/, @out);
        last if scalar(@port1)==0;
        Ravada::Request->refresh_machine(
            uid => user_admin->id
            ,id_domain => $clone1->id
            ,_force => 1
        );
        wait_request();
    }
    is(scalar(@port1),0,"Expecting -d $ip1 --dport $internal_port -j ACCEPT") or die Dumper(\@port1);

    @port2 = (grep /-A FORWARD -d $ip2.32 -p tcp -m tcp --dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port2),1,"Expecting -s $remote_ip2 --dport $internal_port") or die Dumper(\@port2);

    remove_domain($clone1);
    remove_domain($clone2);
    remove_domain($base);

}

sub _check_one_port($remote_ip, $internal_port, $internal_ip) {
    my @out = split /\n/, `iptables-save`;
    my @port2 = (grep /-s $remote_ip.32.*--dport $internal_port -j ACCEPT/, @out);
    is(scalar(@port2),1,"Expecting $internal_port") or confess Dumper(\@port2);

    my @port_drop = (grep /-d $internal_ip.*--dport $internal_port -j DROP/, @out);
    is(scalar(@port_drop),1,"-d $internal_ip.*--dport $internal_port -j DROP") or die Dumper(\@port_drop);

    my @port_prerouting = (grep /-A PREROUTING.*--to-destination $internal_ip:$internal_port$/, @out);
    is(scalar(@port_prerouting),1) or die Dumper(\@port_prerouting);

    # TODO
    #my @port1 = (grep /--dport $internal_port -j ACCEPT/, @out);
    #is(scalar(@port1),1,"Expecting $internal_port") or die Dumper(\@port1);

}

sub test_redirect_ip_duplicated($vm) {
    diag("Test redirect ip duplicated ".$vm->type);
    my $internal_port = 22;
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain->expose(port => $internal_port, name => "ssh");
    my $remote_ip = '10.1.1.2';
    for ( 1 .. 3 ) {
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,remote_ip => $remote_ip
            ,_force => 1
        );
        wait_request(debug => 0);
        my $ip = _wait_ip2($vm, $domain, $remote_ip);
        my @out0 = split /\n/, `iptables-save -t nat`;
        my @open0 = (grep /--to-destination $ip/, @out0);
        last if scalar(@open0) == 1;

    }
    my $ip = _wait_ip2($vm, $domain);
    wait_request(debug => 0, skip => [ 'set_time','enforce_limits']);

    my @out0 = split /\n/, `iptables-save -t nat`;
    my @open0 = (grep /--to-destination $ip/, @out0);
    is(scalar(@open0),1) or die Dumper(\@open0);

    my @ports0 = $domain->list_ports();
    my ($public_port) = $ports0[0]->{public_port};
    my @rule = (
        t => 'nat'
        , A => 'PREROUTING'
        , p => 'tcp'
        , d => $vm->ip
        , dport => $public_port+10
        , j => 'DNAT'
        , 'to-destination' => "$ip:$internal_port"
    );
    $vm->iptables(@rule);
    my @out = split /\n/, `iptables-save -t nat`;
    my @open = (grep /--to-destination $ip/, @out);
    is(scalar(@open),2) or die Dumper(\@open);
    delete_request('open_exposed_ports','set_time','enforce_limits');
    $domain->start( remote_ip => '10.1.1.2', user => user_admin);
    wait_request(debug => 0);
    rvd_back->_check_duplicated_prerouting();

    @out = split /\n/, `iptables-save -t nat`;
    @open = (grep /--to-destination $ip/, @out);
    is(scalar(@open),1,"expecting --to-destination $ip") or die Dumper(\@open);

    $domain->remove(user_admin);
    _clean_iptables($vm, @rule);
}

sub test_redirect_ip_duplicated_refresh($vm) {
    diag("Test redirect ip duplicated refresh".$vm->type);
    my $internal_port = 22;
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain->expose(port => $internal_port, name => "ssh");
    $domain->start( remote_ip => '10.1.1.2', user => user_admin);
    my $ip = _wait_ip2($vm, $domain);
    wait_request(debug => 0);

    my @ports0 = $domain->list_ports();
    my ($public_port) = $ports0[0]->{public_port};
    my @rule = (
        t => 'nat'
        , A => 'PREROUTING'
        , p => 'tcp'
        , d => $vm->ip
        , dport => $public_port+10
        , j => 'DNAT'
        , 'to-destination' => "$ip:$internal_port"
    );
    $vm->iptables(@rule);
    my @out = split /\n/, `iptables-save -t nat`;
    my @open = (grep /--to-destination $ip/, @out);
    is(scalar(@open),2) or die Dumper(\@open);

    my $req = Ravada::Request->refresh_vms();
    wait_request();
    is($req->status,'done');
    is($req->error, '');

    @out = split /\n/, `iptables-save -t nat`;
    @open = (grep /--to-destination $ip/, @out);
    is(scalar(@open),1) or die Dumper(\@open);

    $domain->remove(user_admin);
    _clean_iptables($vm, @rule);
}

sub _wait_open_port($domain, $port ) {
    my @open;
    for my $n ( 1 .. 21 ) {
        wait_request(debug => 0, skip => [ 'set_time','enforce_limits']);
        my $ip = $domain->ip;
        my @out = split /\n/, `iptables-save -t nat`;
        @open = (grep /--to-destination $ip:$port/, @out);
        last if scalar(@open);
        if (! ($n % 5) ) {
            diag("Open exposed port for ".$domain->id);
            Ravada::Request->open_exposed_ports(
                id_domain => $domain->id
                ,uid => user_admin->id
                ,_force => 1
            );
            next;
        }
        diag("$n waiting for port $port from domain ".$domain->name);
        sleep 1;
    }

    return @open;
}

sub test_open_port_duplicated($vm) {
    diag("Test open port duplicated ".$vm->type);
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->expose(port => 22, name => "ssh");
    my @base_ports0 = $base->list_ports();

    $base->prepare_base(user => user_admin);

    my $clone = $base->clone(name => new_domain_name, user => user_admin);

    my $remote_ip = "10.1.1.1";
    $clone->start(remote_ip => $remote_ip, user => user_admin);
    _wait_ip2($vm, $clone);

    my @open=_wait_open_port($clone,22);
    is(scalar(@open),1) or die "Expecting open port 22 for ".$clone->name;
    my ($public_port) = $open[0] =~ /--dport (\d+)/;
    die "Error: no public port in $open[0]" if !$public_port;
    my @rule = (
        t => 'nat'
        , A => 'PREROUTING'
        , p => 'tcp'
        , d => '192.0.2.3'
        , dport => $public_port
        , j => 'DNAT'
        , 'to-destination' => '127.0.0.1:23'
    );
    $vm->iptables(@rule);
    my @out2 = split /\n/, `iptables-save -t nat`;
    my @open2 = (grep /--dport $public_port/, @out2);
    is(scalar(@open2),2) or die Dumper(\@open2);

    my $req = Ravada::Request->refresh_vms(_force => 1);
    for ( 1 .. 30 ) {
        wait_request(request => $req, debug => 0);
        last if $req->status eq 'done';
        sleep 1;
    }
    is($req->status,'done');
    like($req->error,qr/checking /) if $req->error;

    my (@out3,@open3);
    for ( 1 .. 5 ) {
        @out3 = split /\n/, `iptables-save -t nat`;
        @open3 = (grep /--dport $public_port/, @out3);
        last if scalar(@open3)==1;
        if (scalar(@open3)>1) {
            Ravada::Request->refresh_vms(_force =>1, uid => Ravada::Utils::user_daemon->id)
        }
        Ravada::Request->open_exposed_ports(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,_force => 1
        );
        wait_request();
    }
    is(scalar(@open3),1,"Expecting 1 --dport $public_port") or die Dumper(\@open3,\@out3);

    $clone->remove(user_admin);
    $base->remove(user_admin);
    _clean_iptables($vm, @rule);
}

sub test_close_port($vm) {
    diag("Test close port ".$vm->type);
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->expose(port => 22, name => "ssh");
    my @base_ports0 = $base->list_ports();

    $base->prepare_base(user => user_admin);

    my $clone = $base->clone(name => new_domain_name, user => user_admin);
    my $remote_ip = '10.1.1.1';
    $clone->start(remote_ip => $remote_ip , user => user_admin);
    _wait_ip2($vm, $clone);

    my @open=_wait_open_port($clone,22);

    is(scalar(@open),1) or exit;
    my ($public_port) = $open[0] =~ /--dport (\d+)/;
    die "Error: no public port in $open[0]" if !$public_port;
    my @rule = (
        t => 'nat'
        , A => 'PREROUTING'
        , p => 'tcp'
        , d => '192.0.2.3'
        , dport => $public_port
        , j => 'DNAT'
        , 'to-destination' => '127.0.0.1:23'
    );
    $vm->iptables( @rule);
    my @out2 = split /\n/, `iptables-save -t nat`;
    my @open2 = (grep /--dport $public_port/, @out2);
    is(scalar(@open2),2) or die Dumper(\@open);
    $clone->shutdown_now(user_admin);
    wait_request();

    my $clone_ip = _wait_ip($vm,$clone);
    my @out3 = split /\n/, `iptables-save -t nat`;
    my @open3 = (grep /--to-destination $clone_ip:22/, @out3);
    is(scalar(@open3),0, Dumper(\@open3));

    $clone->remove(user_admin);
    $base->remove(user_admin);
    _clean_iptables($vm,@rule);
}

sub _clean_iptables($vm, @rule) {
    for (@rule) { $_ = "D" if $_ eq 'A' };
    $vm->iptables(@rule);
}

sub test_clone_exports_add_ports($vm) {

    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
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

    my @req = $clone->list_requests;

    for my $n ( 0 .. 1 ) {
        is($base_ports[$n]->{internal_port}, $clone_ports[$n]->{internal_port});
        isnt($base_ports[$n]->{public_port}, $clone_ports[$n]->{public_port},"Same public port in clone and base for ".$base_ports[$n]->{internal_port});
        is($base_ports[$n]->{name}, $clone_ports[$n]->{name});
    }
    _wait_ip2($vm, $clone);
    wait_request( debug => 0);
    wait_request( debug => 0, request => \@req );
    for (@req) {
        next if $_->command eq 'set_time';
        is($_->status,'done')   or exit;
        is($_->error,'')        or exit;
    }
    _wait_open_port($clone,22);
    my @out = split /\n/, `iptables -t nat -L PREROUTING -n`;
    ok(grep /dpt:\d+.*\d+:22/, @out) or die Dumper([$clone->name,\@out]);
    ok(grep /dpt:\d+.*\d+:80/, @out);

    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub _wait_ip2($vm_name, $domain, $remote_ip='1.2.3.5') {
    confess if !ref($domain) || ref($domain) !~ /Domain/;
    wait_request();
    $domain->start(user => user_admin, remote_ip => $remote_ip) unless $domain->is_active();
    for ( 1 .. 30 ) {
        return $domain->ip if $domain->ip;
        diag("Waiting for ".$domain->name. " ip") if !(time % 10);
        sleep 1;
    }
    confess "Error : no ip for ".$domain->name;
}

sub _wait_ip {
    return _wait_ip2(@_);
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

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

    my $remote_ip = '10.0.0.1';
    my $local_ip = $vm->ip;

    $domain->shutdown_now(user_admin)    if $domain->is_active;

    my $internal_port = 22;
    my ($public_port);
    eval { ($public_port) = $domain->expose($internal_port) };
    is($@,'') or return;

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    _wait_requests($domain);
    wait_request(debug => 0);

    my $domain_ip = $domain->ip;
    ok($domain_ip,"[$vm_name] Expecting an IP for domain ".$domain->name.", got ".($domain_ip or '')) or return;

    is(scalar $domain->list_ports,1);

    my ($n_rule);
    for ( 1 .. 3 ) {
        my $exposed_port = $domain->exposed_port($internal_port);
        $public_port = $exposed_port->{public_port};
        $n_rule = search_iptable_remote(local_ip => "$local_ip/32"
            , local_port => $public_port
            , table => 'nat'
            , chain => 'PREROUTING'
            , node => $vm
            , jump => 'DNAT'
        );
        last if $n_rule;
        wait_request();
    }

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

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

    my $remote_ip = '10.0.0.'.int(rand(200)+2);

    $domain->start(user => user_admin, remote_ip => $remote_ip);

    my $ip = _wait_ip($vm_name, $domain);
    ok($ip) or die $domain->name." is down or has no ip";

    my $internal_port = 22;
    my $req = Ravada::Request->expose(
                   uid => user_admin->id
            ,port => $internal_port
            ,id_domain => $domain->id
    );
    ok(!$req->{_duplicated}) or exit;
    for ( 1 .. 30 ) {
        wait_request(request => $req, debug => 0);
        last if $req->status eq 'done' && ! $req->error =~ /retry/i;
        sleep 1;
    }

    is($req->status(),'done');
    is($req->error(),'');

    $domain->start(user => user_admin, remote_ip => $remote_ip);
    wait_request();

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

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

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
    my ($n_rule, $n_rule_drop);
    for ( 1 .. 10 ) {
        ($n_rule)
        = search_iptable_remote(
            local_ip => "$internal_ip/32"
            , chain => 'FORWARD'
            , remote_ip => $remote_ip_check
            , local_port => $internal_port
            , node => $vm
            , jump => 'ACCEPT'
        );
        last if $n_rule;
        wait_request(skip => '');
    }
    ($n_rule_drop)
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
    my $domain= $BASE->clone(name => new_domain_name, user => user_admin);

    my $internal_port = 22;
    my $name = "foo";
    $domain->expose(port => $internal_port, restricted => $restricted, name => $name);

    my @list_ports = $domain->list_ports();
    is(scalar @list_ports,1) or exit;
    my $public_port = $list_ports[0]->{public_port};
    is($list_ports[0]->{restricted}, $restricted);
    is($list_ports[0]->{name}, $name);

    $restricted = !$restricted;
    $restricted = 0 if !$restricted;
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
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);

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
        $restricted = 0 if !$restricted;
        $domain->expose(id_port => $port->{id}, restricted => $restricted);
        wait_request(debug => 0);
        my ($in, $out, $err);
        run3(['iptables','-L','FORWARD','-n'],\($in, $out, $err));
        die $err if $err;
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
    delete_request('enforce_limits','set_time');
    wait_request( );
}

sub import_base($vm) {
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

sub test_expose_nested_base($vm) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->expose(22);
    $base->prepare_base(user_admin);

    my $base2 = $base->clone(name => new_domain_name , user => user_admin);
    $base2->prepare_base(user_admin);

    ok($base2->exposed_port(22));

    $base2->remove_expose(22);
    ok(!$base2->exposed_port(22));
    $base2->remove(user_admin);
    $base->remove(user_admin);
}

##############################################################

for my $db ( 'mysql', 'sqlite' ) {


for my $vm_name ( reverse vm_names() ) {

    if ($db eq 'mysql') {
        init('/etc/ravada.conf',0, 1);
        next if !ping_backend();
        $Test::Ravada::BACKGROUND=1;
        remove_old_domains_req(1);
        wait_request();
    } elsif ( $db eq 'sqlite') {
        $Test::Ravada::BACKGROUND=0;
        init(undef, 1,1); # flush
    }
    diag("Testing $vm_name on $db");
    clean();
    add_network_10(0);
    test_can_expose_ports();

    SKIP: {
    my $vm = rvd_back->search_vm($vm_name);

    my $msg = "SKIPPED test: No $vm_name VM found ";
    if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    flush_rules() if !$<;
    rvd_back->setting("/backend/wait_retry",1);
    import_base($vm);

    test_req_expose($vm_name);
    test_expose_nested_base($vm);

    test_interfaces($vm);

    test_port_prerouting_already_open_clones_no_restricted($vm);
    test_port_prerouting_already_open_clones($vm);

    test_port_already_open($vm);
    test_port_prerouting_already_open($vm);

    test_redirect_ip_duplicated($vm);
    test_open_port_duplicated($vm);
    test_close_port($vm);

    test_routing_hibernated($vm);
    test_routing_already_used($vm,0,'restricted');
    test_routing_already_used($vm);
    test_routing_already_used($vm,'addsource');
    test_routing_already_used($vm,'addsource','restricted');

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
    test_clone_exports_spinoff($vm);

    rvd_back->setting("/backend/wait_retry",10);
    NEXT:
    }; # of SKIP
}
}

flush_rules() if !$<;
end();
done_testing();
