use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada::VM');

init($test->connector, 't/etc/ravada_vm.conf');

ok(rvd_back);

done_testing();
