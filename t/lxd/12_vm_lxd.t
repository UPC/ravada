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
use_ok("Ravada::VM::$BACKEND");

##########################################################

sub test_vm_connect {
    my $vm = Ravada::VM::LXD->new();
    $vm->connect();
    ok($vm->{_connection});
    is($vm->host,'localhost');
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
ok(!$@,$@);
ok($RAVADA);

my $err = ($@ or '');
my $vm;

{ $vm = $RAVADA->search_vm($BACKEND) };
$err .= ($@ or '');

SKIP: {

    my $msg = "SKIPPED test: No $BACKEND backend found : $err";
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok($CLASS);
    test_vm_connect();
    test_search_vm();

};
done_testing();
