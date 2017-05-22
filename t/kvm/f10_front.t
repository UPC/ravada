use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql_bare.conf');

use_ok('Ravada');

my $iso;
ok(rvd_back($test->connector), "Expecting rvd_back");
eval { $iso = rvd_front->list_iso_images() };
is($@,'');
ok(scalar @$iso,"Expecting ISOs, got :".Dumper($iso));

done_testing();
