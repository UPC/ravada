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
    my $local_ip = '127.0.0.1';
    my $local_port = '5900';
	my %opts = (
    	'use_ipv6' => 0,         # can set to 1 to force ip6tables usage
	    'ipt_rules_file' => '',  # optional file path from
	                             # which to read iptables rules
	    'iptout'   => '/tmp/iptables.out',
	    'ipterr'   => '/tmp/iptables.err',
	    'debug'    => 0,
	    'verbose'  => 0,
# in the filter table

	    ### advanced options
	    'ipt_alarm' => 5,  ### max seconds to wait for iptables execution.
	    'ipt_exec_style' => 'waitpid',  ### can be 'waitpid',
	                                    ### 'system', or 'popen'.
	    'ipt_exec_sleep' => 1, ### add in time delay between execution of
	                           ### iptables commands (default is 0).
	);
    my $ipt_obj = IPTables::ChainMgr->new(%opts)
        or die "[*] Could not acquire IPTables::ChainMgr object";
    $ipt_obj->flush_chain('filter', 'RAVADA');
    #my $rv = 0;
    #my $out_ar = [];
    #my $errs_ar = [];
    #($rv, $out_ar, $errs_ar) = $ipt_obj->add_ip_rule($local_ip,
    #    $remote_ip, 4, 'filter', 'RAVADA', 'DROP',
    #        {'protocol' => 'tcp', 's_port' => 0, 'd_port' => $local_port});
    $domain->start( user => $USER, remote_ip => $remote_ip);
    
    #($rv, $out_ar, $errs_ar) = $ipt_obj->append_ip_rule($local_ip,
    #    $remote_ip, 'filter', 'RAVADA', 'ACCEPT',
    #        {'protocol' => 'tcp', 's_port' => 0, 'd_port' => $local_port});
    
    ok($domain->is_active);
    
    #TODO check iptables for an entry allowing 127.0.0.1 to $domain->display
}

#######################################################

remove_old_domains();
remove_old_disks();

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

    my $vm;
    eval { $vm = $RVD_BACK->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        my $domain = test_create_domain($vm_name);
        test_fw_domain($vm_name, $domain);
    };
}
done_testing();
