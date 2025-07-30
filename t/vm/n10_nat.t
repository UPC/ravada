use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(DumpFile);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

my $FILE_CONFIG = "t/etc/ravada.conf";
init( );

my $NAT_IP = '2.2.2.2';
my $REMOTE_IP = '9.9.9.9';
my $CHAIN = 'RAVADA';

my $BASE;
##################################################################################

sub _search_other_ip($ip) {
    my $out = `ifconfig`;
    for my $line ( split /\n/, $out ) {
        my ($ip2) = $line =~ /inet.(\d+\.\d+\.\d+\.\d+) /;

        return $ip2 if $ip2
                        && $ip2 ne $ip
                        && $ip2 ne '127.0.0.1';
    }
    die "I can't find another ip address here";
}

sub test_route($vm) {
    my $domain = create_domain($vm);

    my %route = ( '127.0.0.0/24', '127.0.0.1');
    my $routes = `ip route`;
    for my $line ( split /\n/, $routes ) {
        next if $line =~ / dev tun\d+ /;
        my ($network,$ip) = $line =~ /(^[\d+\.\/]+).*src ([\d+\.]+)/;
        next if !$network || !$ip;
        $route{$network} = $ip;
    }

    for my $network ( sort keys %route ) {
        my ($client_ip, $last) = $network =~ m{(.*)\.(\d+)/.*};
        ($client_ip, $last) = $network =~ m{(.*)\.(\d+)}    if !defined $client_ip;

        confess "No last in network '$network' ".($client_ip or 'UNDEF')
                ." ".($last or 'UNDEF') if !defined $last;
        while ( $last < 2 || "$client_ip.$last" eq $route{$network} ) {
            $last++;
        }
        $client_ip .= ".$last";
        $domain->shutdown_now(user_admin) if $domain->is_active;
        $domain->start(user => user_admin, remote_ip => $client_ip );
        my $display = $domain->display(user_admin);
        my ($ip) = $display =~ m{//([\d+\.]+)};
        is($ip, $route{$network},$vm->type) or die $domain->name;
    }
}

sub test_nat_rdp($vm) {
    my $domain = $BASE->clone(user => user_admin
        ,name => new_domain_name);

    Ravada::Request->add_hardware(
        name => 'display'
        ,uid => user_admin->id
        ,data => { driver => 'rdp' }
        ,id_domain => $domain->id
    );
    $vm->nat_ip($NAT_IP);
    wait_request();
    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $REMOTE_IP
    );
    wait_request(debug=>0);

    wait_ip($domain);

    die "Error: no ip found for ".$domain->name if !$domain->ip;

    $req->status('requested');
    wait_request(debug=>0);

    my $sth = connector->dbh->prepare("SELECT * FROM domain_displays "
    ." WHERE id_domain=?");
    $sth->execute($domain->id);
    while (my $row = $sth->fetchrow_hashref) {
        is($row->{listen_ip}, $vm->ip,"listen_ip ".$row->{driver});
        is($row->{ip},$NAT_IP,"ip ".$row->{driver}) or exit;
    }
    $vm->nat_ip('');
}


sub test_nat($vm_name) {
    my $domain = create_domain($vm_name);

    $domain->shutdown_now() if $domain->is_active;
    $domain->start(user => user_admin, remote_ip => $REMOTE_IP );

    #-------------------------------------------------------------------------------
    # Test Display
    #
    my $display;
    eval { $display = $domain->display(user_admin)};
    is($@,'');
    ok($display,"Expecting a display URI, got '".($display or '')."'") or return;

    my ($ip, $port) = $display =~ m{^\w+://(.*):(\d+)} if defined $display;

    ok($ip, "Expecting an IP , got ''") or return;

    test_chain($vm_name, local_ip =>  $ip, local_port => $port, remote_ip => $REMOTE_IP);
    test_chain($vm_name, local_ip =>  $ip, local_port => $port, remote_ip => '0.0.0.0/0'
        , jump => 'DROP');


    isnt($ip , '127.0.0.1', "[$vm_name] Expecting IP no '127.0.0.1', got '$ip'")
        or exit;

    $domain->shutdown_now(user_admin)   if $domain->is_active;

    test_chain($vm_name, local_ip =>  $ip, local_port => $port, remote_ip => $REMOTE_IP
        , enabled => 0);
    test_chain($vm_name, local_ip =>  $ip, local_port => $port, remote_ip => '0.0.0.0/0'
        , jump => 'DROP', enabled => 0);

    #--------------------------------------------------------------------------------
    # Test forcing display ip
    #
    my $display_ip = _search_other_ip( $ip );
    isnt($display_ip, $ip);
    like($display_ip, qr{\d+\.\d+\.\d+\.\d+});

    my $file_config = "/tmp/config_display.yml";
    DumpFile($file_config,{ display_ip => $display_ip, vm => ['Void', 'KVM']
            ,dir_rrd => '/var/tmp/ravada/'.new_domain_name() });

    my $rvd_back = Ravada->new(
        connector => connector()
        , config => $file_config
    );

    is($rvd_back->display_ip, $display_ip);
    is($rvd_back->search_vm($vm_name)->ip, $display_ip);

    $domain = $rvd_back->search_domain($domain->name);
    $domain->start(user => user_admin, remote_ip => $REMOTE_IP );

    eval { $display = $domain->display(user_admin)};
    is($@,'');
    my ($ip2) = $display =~ m{^\w+://(.*):\d+} if defined $display;

    is($ip2, $display_ip);

    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => $REMOTE_IP
        , msg => "display");
    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => '0.0.0.0/0'
        , jump => 'DROP');


    $domain->shutdown_now(user_admin)   if $domain->is_active;

    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => $REMOTE_IP
        , enabled => 0);
    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => '0.0.0.0/0'
        , jump => 'DROP', enabled => 0);

    #--------------------------------------------------------------------------------
    # Now with Nat
    #
    DumpFile($file_config,{ display_ip => $display_ip, nat_ip => $NAT_IP, vm => ['Void', 'KVM']
            ,dir_rrd => '/var/tmp/ravada/'.new_domain_name() });

    $rvd_back = Ravada->new(
        connector => connector()
        , config => $file_config
    );

    is($rvd_back->nat_ip, $NAT_IP);
    is($rvd_back->search_vm($vm_name)->nat_ip, $NAT_IP);
    $domain = $rvd_back->search_domain($domain->name);

    $domain->start(user => user_admin, remote_ip => $REMOTE_IP );

    eval { $display = $domain->display(user_admin)};
    my ($ip3) = $display =~ m{^\w+://(.*):\d+} if defined $display;
    is($ip3, $NAT_IP,"[$vm_name] Expecting NAT_IP in display");

    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => $REMOTE_IP
        , msg => 'nat');
    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => '0.0.0.0/0'
        , jump => 'DROP', msg => 'nat');

    $domain->shutdown_now(user_admin)   if $domain->is_active;

    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => $REMOTE_IP
        , enabled => 0, msg => 'nat');
    test_chain($vm_name, local_ip =>  $display_ip, local_port => $port, remote_ip => '0.0.0.0/0'
        , jump => 'DROP', enabled => 0, msg => 'nat');

    unlink($file_config);

    rvd_back($FILE_CONFIG);
}

sub test_chain($vm_name, %args) {
    SKIP: {
        skip("iptables test must be run from root user",2);
    my $jump =  (delete $args{jump} or 'ACCEPT');
    my $local_ip = delete $args{local_ip}       or confess "Missing local_ip";
    my $remote_ip = delete $args{remote_ip}     or confess "Missing remote_ip";
    my $local_port= delete $args{local_port}    or confess "Missing local_port";
    my $enabled = delete $args{enabled};
    $enabled = 1 if !defined $enabled;
    my $msg = ( delete $args{msg} or '' );

    confess "Unknown args ".join(",",sort keys %args)   if keys %args;
    my $ipt = open_ipt();
    my ($rule_num , $chain_rules)
        = $ipt->find_ip_rule($remote_ip, $local_ip,'filter', $CHAIN, $jump
                              , {normalize => 1 , d_port => $local_port });

    my $msg2 = "[$vm_name]";
    $msg2 = "[$vm_name - $msg]" if $msg;
    ok($rule_num,"$msg2 Expecting rule for $remote_ip -> $local_ip: $local_port $jump")
            or exit
        if $enabled;
    ok(!$rule_num,"$msg2 Expecting no rule for $remote_ip -> $local_ip: $local_port"
                        .", found at $rule_num ")
        if !$enabled;

    }
}

sub _import_base($vm) {
    if ($vm->type eq 'KVM') {
        $BASE = import_domain($vm);
    } else {
        $BASE = create_domain($vm);
    }
}

##################################################################################

clean();
flush_rules();

for my $vm_name ( vm_names() ) {

    my $vm;

    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        _import_base($vm);
        test_nat_rdp($vm);

        test_route($vm);
        test_nat($vm_name);
    }
}

flush_rules() if $<;
end();
done_testing();
