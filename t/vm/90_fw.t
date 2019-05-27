use warnings;
use strict;

use Data::Dumper;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;


use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back();
my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector());
my $USER = create_user("foo","bar", 1);

my $CHAIN = 'RAVADA';

##########################################################

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name 
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

 
    return $domain;
}

sub test_fw_domain {
    my ($vm_name, $domain) = @_;
    my $remote_ip = '99.88.77.66';

    my $vm = $RVD_BACK->search_vm($vm_name);

    my $local_ip = $vm->ip;

    $domain->start( user => $USER, remote_ip => $remote_ip);

    my $display = $domain->display($USER);
    my ($local_port) = $display =~ m{\d+\.\d+\.\d+\.\d+\:(\d+)};
    ok(defined $local_port, "Expecting a port in display '$display'") or return;
    
    ok($domain->is_active);
    test_chain($vm_name, $local_ip,$local_port, $remote_ip, 1);

    $domain->shutdown_now( $USER );
    test_chain($vm_name, $local_ip,$local_port, $remote_ip, 0);
}

sub test_fw_domain_stored {
    my ($vm_name, $domain_name) = @_;
    my $remote_ip = '99.88.77.66';

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $local_ip = $vm->ip;
    my $local_port;

    {
        my $domain = $vm->search_domain($domain_name);
        ok($domain,"Searching for domain $domain_name") or return;
        $domain->start( user => $USER, remote_ip => $remote_ip);

        my $display = $domain->display($USER);
        ($local_port) = $display =~ m{\d+\.\d+\.\d+\.\d+\:(\d+)};
        ok(defined $local_port, "Expecting a port in display '$display'") or return;
    
        ok($domain->is_active);
        test_chain($vm_name, $local_ip,$local_port, $remote_ip, 1);
    }

    my $domain = $vm->search_domain($domain_name);
    $domain->shutdown_now( $USER );
    test_chain($vm_name, $local_ip,$local_port, $remote_ip, 0);
}



sub test_chain {
    my $vm_name = shift;

    my ($local_ip, $local_port, $remote_ip, $expected_count) = @_;

    my @rule = find_ip_rule(
           remote_ip => $remote_ip
        , local_port => $local_port
          , local_ip =>  $local_ip,
              , jump => 'ACCEPT'
    );

    is(scalar(@rule),$expected_count);
    ok($rule[0],"[$vm_name] Expecting rule for $remote_ip -> $local_ip: $local_port") 
        if $expected_count;

    ok(!$rule[0],"[$vm_name] Expecting no rule for $remote_ip -> $local_ip: $local_port"
                        .", got ".Dumper(\@rule))
        if !$expected_count;

}

sub test_fw_ssh {
    my $vm_name = shift;
    my $domain = shift;

    my $port = 22;
    my $remote_ip = '11.22.33.44';

    $domain->add_nat($port);

    $domain->shutdown_now($USER) if $domain->is_active;
    $domain->start(user => $USER, remote_ip => $remote_ip);

    ok($domain->is_active,"Domain ".$domain->name." should be active=1, got: "
        .$domain->is_active) or return;

    for my $n ( 1 .. 60 ) {
        last if $domain->ip;
        diag("Waiting for ".$domain->name." to have an ip") if !($n % 10);
        sleep 1;
    }
    ok($domain->ip,"Expecting an IP for the domain ".$domain->name) or return;
    eval { $domain->open_nat_ports( remote_ip => $remote_ip, user => $USER) };

    my ($public_ip,$public_port)= $domain->public_address($port);

    diag("Open in $public_ip / $public_port");
    like(($public_ip or '')   ,qr{^\d+\.\d+\.\d+\.\d+$});
    like(($public_port or '') ,qr{^\d+$});

    #comprova que està obert a les iptables per aquest port desde la $remote_ip
    my $vm = $RVD_BACK->search_vm($vm_name);
    my $local_ip = $vm->ip;

    is($public_ip,$local_ip);
    my $domain_ip = $domain->ip;
    for ( 1 .. 10 ) {
        $domain_ip = $domain->ip;
        last if  $domain_ip;
        sleep 1;
    }
    die "No domain ip for ".$domain->name   if !$domain_ip;

    test_chain($vm_name, $local_ip, $public_port, $remote_ip,1);
    test_chain_prerouting($vm_name, $local_ip, $port, $domain_ip, 1)
        or exit;

    eval { $domain->open_nat_ports( remote_ip => $remote_ip, user => $USER) };
    test_chain_prerouting($vm_name, $local_ip, $port,$domain_ip,1) or exit;

    $domain->shutdown_now($USER) if $domain->is_active;
    {
        my ($ip,$port)= $domain->public_address($port);

        like($ip,qr{^$});
        like($port,qr{^$});
    }
    test_chain($vm_name, $local_ip, $public_port, $remote_ip,0);
    test_chain_prerouting($vm_name, $local_ip, $port, $domain_ip, 0);

}

sub test_jump {
    my ($vm_name, $domain_name) = @_;
    my $out = `iptables -L INPUT -n`;
    my $count = 0;
    for my $line ( split /\n/,$out ) {
        next if $line !~ /^[A-Z]+ /;
        $count++;
        next if $line !~ /^RAVADA/;
        `iptables -D INPUT $count`;
    }
    $out = `iptables -L INPUT -n`;
    ok(! grep(/^RAVADA /, split(/\n/,$out)),"Expecting no RAVADA jump in $out");

    my $vm =$RVD_BACK->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);

    $domain->start(user_admin)  if !$domain->is_active;

    $domain->open_iptables(remote_ip => '1.1.1.1', uid => user_admin->id);

    $out = `iptables -L INPUT -n`;
    ok(grep(/^RAVADA /, split(/\n/,$out)),"Expecting RAVADA jump in $out");
}

sub test_new_ip {
    my $vm = shift;

    my $domain = create_domain($vm->type);

    my $remote_ip = '1.1.1.1';

    $domain->start( user => user_admin, remote_ip => $remote_ip);

    my ($local_port) = $domain->display(user_admin) =~ m{\d+\.\d+\.\d+\.\d+\:(\d+)};
#    test_chain($vm->type, $vm->ip, $local_port, $remote_ip,1);
    my %test_args= (
           remote_ip => $remote_ip
        , local_port => $local_port
          , local_ip =>  $vm->ip,
              , jump => 'ACCEPT'
    );
    my %test_args_drop = (%test_args
        ,remote_ip => '0.0.0.0/0'
        ,jump => 'DROP'
    );
    my @rule = find_ip_rule(%test_args);
    is(scalar @rule,1);

    my @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,1) or return;
    ok($rule_drop[0] > $rule[0],Dumper(\@rule,\@rule_drop))
        if scalar @rule_drop == 1 && scalar @rule == 1;

    $domain->open_iptables( user => user_admin);
    @rule = find_ip_rule(%test_args);
    is(scalar @rule,0);

    @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,0);

    $domain->open_iptables( user => user_admin, remote_ip => $remote_ip);
    @rule = find_ip_rule(%test_args);
    is(scalar @rule,1);

    my $remote_ip2 = '2.2.2.2';
    $domain->open_iptables( user => user_admin, remote_ip => $remote_ip2);

    @rule = find_ip_rule(%test_args);
    is(scalar @rule,0);

    $test_args{remote_ip} = $remote_ip2;
    @rule = find_ip_rule(%test_args);
    is(scalar @rule,1);

    @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,1);

    ok($rule_drop[0] > $rule[0],Dumper(\@rule,\@rule_drop))
        if scalar @rule_drop == 1 && scalar @rule == 1;

    $domain->remove(user_admin);

    @rule = find_ip_rule(%test_args);
    is(scalar @rule,0);

    @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,0);
}

sub test_localhost {
    my $vm = shift;

    my $domain = create_domain($vm->type);

    my $remote_ip = '127.0.0.1';

    $domain->start( user => user_admin, remote_ip => $remote_ip);

    my ($local_ip, $local_port) = $domain->display(user_admin) =~ m{(\d+\.\d+\.\d+\.\d+)\:(\d+)};
    is($local_ip, $remote_ip);
#    test_chain($vm->type, $vm->ip, $local_port, $remote_ip,1);
    my %test_args= (
           remote_ip => $remote_ip
        , local_port => $local_port
          , local_ip =>  $local_ip,
              , jump => 'ACCEPT'
    );
    my %test_args_drop = (%test_args
        ,remote_ip => '0.0.0.0/0'
        ,jump => 'DROP'
    );
    my @rule_localhost = find_ip_rule(%test_args);
    is(scalar @rule_localhost,1);

    my @rule_ip = find_ip_rule(%test_args, remote_ip => $local_ip);
    is(scalar @rule_ip,1);

    my @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,1) or return;
    ok($rule_drop[0] > $rule_localhost[0],Dumper(\@rule_localhost,\@rule_drop))
        if scalar @rule_drop == 1 && scalar @rule_localhost == 1;

    ok($rule_drop[0] > $rule_ip[0],Dumper(\@rule_ip,\@rule_drop))
        if scalar @rule_drop == 1 && scalar @rule_ip== 1;

    $domain->remove(user_admin);

    @rule_localhost = find_ip_rule(%test_args);
    is(scalar @rule_localhost,0);

    @rule_ip = find_ip_rule(%test_args);
    is(scalar @rule_ip,0);

    @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,0);

    @rule_drop = find_ip_rule(remote_ip => $vm->ip, jump => 'ACCEPT');
    is(scalar @rule_drop,0) or exit;
}

sub test_shutdown_internal {
    my $vm = shift;

    my $domain = create_domain($vm->type);

    my $remote_ip = '1.1.1.1';

    $domain->start( user => user_admin, remote_ip => $remote_ip);

    my ( $local_port ) = $domain->display(user_admin) =~ m{\d+\.\d+\.\d+\.\d+\:(\d+)};
    shutdown_domain_internal($domain);
#    test_chain($vm->type, $vm->ip, $local_port, $remote_ip,1);
    my %test_args= (
        local_port => $local_port
          , local_ip =>  $vm->ip,
              , jump => 'ACCEPT'
    );
    my %test_args_drop = (%test_args
        ,remote_ip => '0.0.0.0/0'
        ,jump => 'DROP'
    );

    my $remote_ip2 = '2.2.2.2';
    $domain->start( user => user_admin, remote_ip => $remote_ip2);

    my @rule = find_ip_rule(%test_args);
    is(scalar(@rule) , 1);

    my @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar(@rule_drop) , 1);

    $domain->remove(user_admin);
}

sub test_hibernate {
    my $vm = shift;

    my $domain = create_domain($vm->type);

    my $remote_ip = '3.3.3.3';

    $domain->start( user => user_admin, remote_ip => $remote_ip);

    my ($local_port) = $domain->display(user_admin) =~ m{\d+\.\d+\.\d+\.\d+\:(\d+)};
#    test_chain($vm->type, $vm->ip, $local_port, $remote_ip,1);
    my %test_args= (
           remote_ip => $remote_ip
        , local_port => $local_port
          , local_ip =>  $vm->ip,
              , jump => 'ACCEPT'
    );
    my %test_args_drop = (%test_args
        ,remote_ip => '0.0.0.0/0'
        ,jump => 'DROP'
    );
    my @rule = find_ip_rule(%test_args);
    is(scalar @rule,1);

    my @active_iptables = $domain->_active_iptables( id_domain => $domain->id);
    is(scalar @active_iptables,2) or exit;

    my @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,1) or return;
    ok($rule_drop[0] > $rule[0],Dumper(\@rule,\@rule_drop))
        if scalar @rule_drop == 1 && scalar @rule == 1;

    $domain->hibernate( user_admin );
    @rule = find_ip_rule(%test_args);
    is(scalar @rule,0);

    @rule_drop = find_ip_rule(%test_args_drop);
    is(scalar @rule_drop,0);

    $domain->remove(user_admin);
}

#######################################################

remove_old_domains();
remove_old_disks();

#TODO: dump current chain and restore in the end
#      maybe ($rv, $out_ar, $errs_ar) = $ipt_obj->run_ipt_cmd('/sbin/iptables
#           -t filter -v -n -L RAVADA');

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");

    my $vm;
    eval { $vm = $RVD_BACK->search_vm($vm_name) };

    SKIP: {
        #TODO: find out if this system has iptables
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok("Ravada::VM::$vm_name");

        flush_rules_node($vm);

        my $domain = test_create_domain($vm_name);
        test_fw_domain($vm_name, $domain);

        my $domain2 = test_create_domain($vm_name);
        test_fw_domain_stored($vm_name, $domain2->name);

        test_new_ip($vm);
        test_localhost($vm);

        test_shutdown_internal($vm);

        test_hibernate($vm);

        test_jump($vm_name, $domain2->name);
    };
}
remove_old_domains();
remove_old_disks();

done_testing();
