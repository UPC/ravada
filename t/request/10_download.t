use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
init($test->connector);

diag("$$ parent pid");
my $req1 = Ravada::Request->download( id_iso => 1, delay => 4 );
is($req1->status, 'requested');

$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

my $rvd_back = rvd_back();
$rvd_back->process_all_requests();
is($req1->status, 'working');

my $req2 = Ravada::Request->download( id_iso => 2, delay => 2 );
is($req2->status, 'requested');

$rvd_back->process_all_requests();
is($req1->status, 'working');
is($req2->status, 'waiting');

wait_request($req1);
is($req1->status, 'done');

$rvd_back->process_all_requests();
is($req2->status, 'working');
wait_request($req2);
is($req2->status, 'done');

done_testing();
