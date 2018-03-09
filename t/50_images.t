use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
my $ravada = Ravada->new( connector => $test->connector, config => 't/etc/ravada.conf');

my @images = $ravada->list_images();

ok(scalar @images,"No images ".Dumper(\@images));

done_testing();
