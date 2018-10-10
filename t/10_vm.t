use warnings;
use strict;

use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::VM');

init();

ok(rvd_back);
isa_ok(rvd_back,'Ravada');

done_testing();
