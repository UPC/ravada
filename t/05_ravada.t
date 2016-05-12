use warnings;
use strict;

use Test::More;

use_ok('Ravada');

my $ravada = Ravada->new();

ok($Ravada::CONNECTOR,"No connector defined ");
eval { ok($Ravada::CONNECTOR->dbh,"No dbh defined ") };

done_testing();
