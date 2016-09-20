use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new();

use_ok('Ravada');


##########################################################

sub test_vm_connect {
    my $vm_name = shift;

    my $class = "Ravada::VM::$vm_name";
    my $obj = {};

    bless $obj,$class;

    my $vm = $obj->new();
    ok($vm);
    ok($vm->host eq 'localhost');
}

sub test_search_vm {
    my $vm_name = shift;

    return if $vm_name eq 'Void';

    my $class = "Ravada::VM::$vm_name";

    my $ravada = Ravada->new();
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find a $vm virtual manager");
    ok(ref $vm eq $class,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $class");
}

#######################################################

for my $VM (qw( Void KVM )) {

    diag("Testing $VM VM");
    my $CLASS= "Ravada::VM::$VM";

    use_ok($CLASS);

    my $RAVADA;
    eval { $RAVADA = Ravada->new() };

    my $vm;

    eval { $vm = $RAVADA->search_vm($VM) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $VM VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_vm_connect($VM);
        test_search_vm($VM);

    };
}
done_testing();
