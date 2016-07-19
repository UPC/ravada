use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new();

my $CLASS= 'Ravada::VM::KVM';

use_ok('Ravada');
use_ok($CLASS);

##########################################################

sub test_vm_connect {
    my $vm = Ravada::VM::KVM->new();
    ok($vm);
    ok($vm->type eq 'qemu');
    ok($vm->host eq 'localhost');
    ok($vm->vm);
}

sub test_search_vm {
    my $ravada = Ravada->new();
    my $vm = $ravada->search_vm('kvm');
    ok($vm,"I can't find a KVM virtual manager");
    ok(ref $vm eq $CLASS,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $CLASS");
}

#######################################################

my $RAVADA;
eval { $RAVADA = Ravada->new() };

my $vm;

eval { $vm = $RAVADA->search_vm('kvm') } if $RAVADA;

SKIP: {
    my $msg = "SKIPPED test: No VM backend found";
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

test_vm_connect();
test_search_vm();

};
done_testing();
