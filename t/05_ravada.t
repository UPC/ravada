use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use_ok('Ravada');

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
my $connector = Ravada::DB->instance(connector => $test->connector);

my $ravada = Ravada->new();

ok($ravada->connector, "Expecting a DB connector defined");

eval { ok($ravada->connector->dbh,"Expecting dbh defined") };

done_testing();
