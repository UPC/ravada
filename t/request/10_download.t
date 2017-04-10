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


my $req1 = Ravada::Request->download( id_iso => 1 );
ok($req1->status eq 'requested');

rvd_back->process_all_requests('debug');
ok($req1->status eq 'working');

my $req2 = Ravada::Request->download( id_iso => 2 );
ok($req2->status eq 'requested');
rvd_back->process_all_requests('debug');
ok($req1->status eq 'working');
ok($req2->status eq 'requested');

done_testing();
