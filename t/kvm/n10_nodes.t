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

use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");


my $IP = init_ip();

clean();

my $vm_name = 'KVM';
my $vm;
eval { $vm = rvd_back->search_vm($vm_name) };

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if (!defined $IP) {
        my $msg = "skipped, missing the remote testing IP in the file "
            .$Test::Ravada::FILE_CONFIG_REMOTE;
        diag($msg);
        skip($msg,10);
    }

    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    my $node;
    eval { $node = Ravada::VM::KVM->new(host => $IP) };
    ok(!$@,"Expecting no error connecting to $vm_name at $IP, got :'".($@ or '')."'");
    ok($node) or next;
    is($node->name ,qr($IP));
    ok($node->vm);

}

clean();

done_testing();
