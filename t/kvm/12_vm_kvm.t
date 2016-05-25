use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new();

use_ok('Ravada::VM::KVM');

##########################################################

sub test_vm_connect {
    my $vm = Ravada::VM::KVM->new(connector => $test->connector
    );
    ok($vm);
    ok($vm->type eq 'qemu');
    ok($vm->host eq 'localhost');
    ok($vm->vm);
}

#######################################################

test_vm_connect();

done_testing();
