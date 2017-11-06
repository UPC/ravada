use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, 't/etc/ravada.conf');

my $USER = create_user("foo","bar");

###################################################################

clean();

for my $vm_name (qw(KVM)) {
   my $vm;
   my $msg = "SKIPPED: virtual manager $vm_name not found";
    eval {
        $vm= rvd_back->search_vm($vm_name)  if rvd_back();

        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm= undef;
        }

    };

    SKIP: {
        diag($msg)      if $msg;
        skip($msg,10)   if !$vm;

        diag("Testing requests with $vm_name");
    }
}

done_testing();
clean();
