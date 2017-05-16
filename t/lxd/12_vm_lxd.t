use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $BACKEND = 'LXD';
my $CLASS= "Ravada::VM::$BACKEND";

my %CONFIG = (
        connector => $test->connector
        ,config => 't/etc/ravada.conf'
);

use_ok('Ravada');
use_ok($CLASS);

##########################################################

sub test_vm_connect {
    my $vm = Ravada::VM::LXD->new();
    ok($vm->host eq 'https://localhost:8443/');
}

sub test_search_vm {
    my $ravada = Ravada->new(%CONFIG);
    my $vm = $ravada->search_vm($BACKEND);
    ok($vm,"I can't find a $BACKEND virtual manager");
    ok(ref $vm eq $CLASS,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $CLASS");
}

#######################################################

my $RAVADA;
eval { $RAVADA = Ravada->new(%CONFIG) };

my $err = ($@ or '');
my $vm;

eval { $vm = $RAVADA->search_vm($BACKEND) } if $RAVADA;
$err .= ($@ or '');

SKIP: {

    my $msg = "SKIPPED test: No VM backend found";
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

#test_vm_connect();
test_search_vm();

};
done_testing();
