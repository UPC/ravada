use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $ravada = Ravada->new( connector => connector(), config => 't/etc/ravada.conf');

my @images = $ravada->list_images();

ok(scalar @images,"No images ".Dumper(\@images));

end();
done_testing();
