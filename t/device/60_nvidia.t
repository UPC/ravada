use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Mojo::JSON qw( encode_json decode_json );
use YAML qw(Load Dump  LoadFile DumpFile);

use Ravada;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE;
my $MOCK_MDEV;

######################################################################
######################################################################

init();

end();
done_testing();
