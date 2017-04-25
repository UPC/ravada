use warnings;
use strict;

use Data::Dumper;
use JSON::XS;
use Test::More;
use Test::SQL::Data;
use IPTables::ChainMgr;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

my $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG);
my $USER = create_user("foo","bar");

my $CHAIN = 'RAVADA';

##########################################################

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    if (!$ARG_CREATE_DOM{$vm_name}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}}) 
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


sub open_ipt {
    my %opts = (
    	'use_ipv6' => 0,         # can set to 1 to force ip6tables usage
	    'ipt_rules_file' => '',  # optional file path from
	                             # which to read iptables rules
	    'iptout'   => '/tmp/iptables.out',
	    'ipterr'   => '/tmp/iptables.err',
	    'debug'    => 0,
	    'verbose'  => 0,

	    ### advanced options
	    'ipt_alarm' => 5,  ### max seconds to wait for iptables execution.
	    'ipt_exec_style' => 'waitpid',  ### can be 'waitpid',
	                                    ### 'system', or 'popen'.
	    'ipt_exec_sleep' => 1, ### add in time delay between execution of
	                           ### iptables commands (default is 0).
	);

	my $ipt_obj = IPTables::ChainMgr->new(%opts)
    	or die "[*] Could not acquire IPTables::ChainMgr object";

}

sub test_chain {
    my $vm_name = shift;

    my ($local_ip, $local_port, $remote_ip, $enabled) = @_;
    my $ipt = open_ipt();

    my ($rule_num , $chain_rules) 
        = $ipt->find_ip_rule($remote_ip, $local_ip,'filter', $CHAIN, 'ACCEPT'
                              , {normalize => 1 , d_port => $local_port });

    ok($rule_num,"[$vm_name] Expecting rule for $remote_ip -> $local_ip: $local_port") 
        if $enabled;
    ok(!$rule_num,"[$vm_name] Expecting no rule for $remote_ip -> $local_ip: $local_port"
                        .", got $rule_num ")
        if !$enabled;

}

sub flush_rules {
    my $ipt = open_ipt();
    $ipt->flush_chain('filter', $CHAIN);
    $ipt->delete_chain('filter', 'INPUT', $CHAIN);
}
#######################################################

remove_old_domains();
remove_old_disks();

#TODO: dump current chain and restore in the end
#      maybe ($rv, $out_ar, $errs_ar) = $ipt_obj->run_ipt_cmd('/sbin/iptables
#           -t filter -v -n -L RAVADA');

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

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

        flush_rules();

        my $domain = test_create_domain($vm_name);
        test_fw_domain($vm_name, $domain);

        my $domain2 = test_create_domain($vm_name);
        test_fw_domain_stored($vm_name, $domain2->name);
    };
}
flush_rules();
remove_old_domains();
remove_old_disks();

done_testing();
