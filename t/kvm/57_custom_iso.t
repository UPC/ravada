use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $FILE_CONFIG = 't/etc/ravada.conf';

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, $FILE_CONFIG);

my $USER = create_user('foo','bar');

#########################################################################
#
# test a new domain withou an ISO file
#

sub test_custom_iso {
    my $vm_name = shift;
    my $domain = create_domain($vm_name, $USER,'windows_7');
}

#########################################################################

clean();

my $vm;
my $vm_name = 'KVM';
eval { $vm = rvd_back->search_vm('KVM') };
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    if ($vm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    test_custom_iso($vm_name);

};

clean();

done_testing();
