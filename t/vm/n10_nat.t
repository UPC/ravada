use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(DumpFile);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

init( $test->connector , $FILE_CONFIG );

my $NAT_IP = '2.2.2.2';

my $REMOTE_IP = '9.9.9.9';

my $CHAIN = 'RAVADA';
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
    DumpFile($file_config,{ display_ip => $display_ip });
    my $rvd_back = rvd_back($test->connector, $file_config);

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
    DumpFile($file_config,{ display_ip => $display_ip, nat_ip => $NAT_IP });
    $rvd_back = rvd_back($test->connector, $file_config);

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

    rvd_back($test->connector, $FILE_CONFIG);
}

sub test_chain($vm_name, %args) {
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
##################################################################################

clean();
flush_rules();

for my $vm_name ( 'Void', 'KVM' ) {

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

        test_nat($vm_name);
    }
}

clean();
flush_rules();

done_testing();
