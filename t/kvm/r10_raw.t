use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $VOL_NAME = new_domain_name();
my $XML_VOL =
"<volume>
  <name>$VOL_NAME.raw</name>
  <capacity>10485760</capacity>
  <target>
    <format type='raw'/>
  </target>
</volume>";

use_ok('Ravada');

init($test->connector);

#####################################################################

sub test_domain_raw {
    my $vm = shift;

    my ($pool) = $vm->vm->list_storage_pools();
    my $vol = $pool->create_volume($XML_VOL);
}

#####################################################################

clean();

for my $vm_name ('KVM') {
    SKIP: {

        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        test_domain_raw($vm);
    }
}

clean();

done_testing();
