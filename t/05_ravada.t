use warnings;
use strict;

use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

ok(! $Ravada::CONNECTOR, "DB connector should be undef at load time");

my $ravada = rvd_back();

ok($Ravada::CONNECTOR, "Now we should have a DB connector ");

ok($Ravada::CONNECTOR,"No connector defined ");
eval { ok($Ravada::CONNECTOR->dbh,"No dbh defined ") };

eval {
    my $config_err = "t/etc/ravada_miss.conf";
    my $rvd_err = Ravada->new( connector => connector(), config => $config_err);
};
like($@,qr/Missing config file/);

eval {
    my $config_err = "t/etc/ravada_err.conf";
    my $rvd_err = Ravada->new( connector => connector(), config => $config_err);
};
like($@,qr/Format error/);

done_testing();
