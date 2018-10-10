use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my @VMS = vm_names();
init();
my $USER = create_user("foo","bar", 1);

####################################################################################

sub test_get_cpu_usage {
	chomp(my $cpu_count = `grep -c -P '^processor\\s+:' /proc/cpuinfo`);
	#warn $cpu_count;
	open(STAT, '/proc/loadavg') or die "WTF: $!";
	my @cpu = split /\s+/, <STAT>;
	warn $cpu[1]/$cpu_count;
	close STAT;

}

####################################################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);


SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    test_get_cpu_usage();
}

clean();
done_testing();
