use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new();

my $BACKEND = 'KVM';
my $CLASS= "Ravada::VM::$BACKEND";

use_ok('Ravada');
use_ok($CLASS);

##########################################################

sub test_vm_connect {
    my $vm = Ravada::VM::KVM->new(backend => $BACKEND );
    ok($vm);
    ok($vm->type eq 'qemu');
    ok($vm->host eq 'localhost');
    ok($vm->vm);
}

sub test_search_vm {
    my $ravada = Ravada->new();
    my $vm = $ravada->search_vm($BACKEND);
    ok($vm,"I can't find a $BACKEND virtual manager");
    ok(ref $vm eq $CLASS,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $CLASS");
}

#######################################################

my $RAVADA;
eval { $RAVADA = Ravada->new() };

my $vm;

eval { $vm = Ravada::VM::KVM->new() } ;

SKIP: {
    my $msg = "SKIPPED test: No VM backend found ".($@ or '');
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

test_vm_connect();
test_search_vm();

};
done_testing();
