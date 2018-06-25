#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector);
clean();
###################################################################

sub test_change_max_memory {
	my $vm = shift;
	my $memoryGB = shift;
	my $use_mem_GB = shift;
	my $factor = 1024*1024;
	
	my $domain = create_domain($vm->type);
	
	eval {
		$domain->domain->set_max_memory($memoryGB*$factor);
	};
	is($@,'');
	my $info;
	eval {
		$info = $domain->domain->get_info()
	};
	ok($info->{maxMem}==$memoryGB*$factor, 'Max Memory changed!');#ok
	
	$domain->start(user_admin) if !$domain->is_active;
	
	eval {
		$domain->domain->set_memory($use_mem_GB*$factor);
	};
	is($@,'');
	
	eval {
		$info = $domain->domain->get_info()
	};
	my $nvalue = $info->{memory};
	my $maxvalue = $info->{maxMem};
	ok($nvalue==$use_mem_GB*$factor, 'Memory Changed!'.$nvalue.'  '.$maxvalue);
}

####################################################################

for my $vm_name ( q(KVM) ) {

    init($test->connector, 't/etc/ravada_freemem.conf');
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };
    warn $@ if $@;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg       if !$vm;

        diag("Testing free mem on $vm_name");

        test_change_max_memory($vm, 2, 1);

    }
}

clean();

done_testing();
