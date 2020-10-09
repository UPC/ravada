use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;


use_ok('Ravada');

my $iso;
ok(rvd_back(), "Expecting rvd_back");
eval { $iso = rvd_front->list_iso_images() };
is($@,'');
ok(scalar @$iso,"Expecting ISOs, got :".Dumper($iso));

end();
done_testing();
