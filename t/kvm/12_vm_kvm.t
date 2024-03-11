use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

my $BACKEND = 'KVM';
my $CLASS= "Ravada::VM::$BACKEND";

init();

my %CONFIG = (
        connector => connector
        ,config => 't/etc/ravada.conf'
        ,pid_name => "ravada_install".base_domain_name()
);

use_ok('Ravada');

##########################################################

sub test_vm_connect {
    my $vm = Ravada::VM::KVM->new();
    ok($vm);
    ok($vm->type eq 'KVM');
    ok($vm->host eq 'localhost');
    ok($vm->vm);
}

sub test_search_vm {
    my $ravada = Ravada->new(%CONFIG);
    my $vm = $ravada->search_vm($BACKEND);
    ok($vm,"Expecting valid $BACKEND virtual manager");
    ok(ref $vm eq $CLASS,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $CLASS");
}

#######################################################

my $RAVADA;
eval {
    $RAVADA = Ravada->new(%CONFIG);
    $RAVADA->_install();
};

my $err = ($@ or '');
my $vm;

eval { $vm = $RAVADA->search_vm($BACKEND) } if $RAVADA && !$<;
$err .= ($@ or '');

SKIP: {
    my $msg = "SKIPPED test: No KVM virtual machine manager found ";
    diag($msg)      if !$vm;
    diag($err)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok($CLASS);

test_vm_connect();
test_search_vm();

};
end();
done_testing();
