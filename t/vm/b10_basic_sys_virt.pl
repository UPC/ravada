use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector);

sub test_basic {
	my $name = shift;
	
	my $con = Sys::Virt->new(address=>"qemu:///system");
	
	my $domain = $con->get_domain_by_name($name);
	$domain->shutdown() if $domain->is_active();
	
	my $info;
	eval {
		$info = $domain->get_info()
	};
	is($@,'');
	my $factor = 1024*1024; #Gb->Kb
	eval {
		$domain->set_max_memory($info->{maxMem}+$factor)
	};
	is($@,'');
	$domain->create() if !$domain->is_active();
	
	eval {
		$domain->set_memory(2*$factor)
	};
	is($@,'');
	
	eval {
		$info = $domain->get_info()
	};
	is($@,'');
	ok(2*$factor==$info->{memory}, "Mateixa memoria! -> ".$info->{maxMem}."  =  ".$info->{memory});
	
	
	$domain->shutdown() if $domain->is_active();
	
	$domain->set_max_memory($factor) if !$domain->is_active();
}

#test_basic('testh2');

done_testing();