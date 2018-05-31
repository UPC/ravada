#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector);

################################################################

my $user = create_user("falken","joshua");

user_admin->make_admin($user->id);

$user = Ravada::Auth::SQL->search_by_id($user->id);
is($user->is_admin, 1);

user_admin->remove_admin($user->id);

$user = Ravada::Auth::SQL->search_by_id($user->id);
is($user->is_admin,0 );

done_testing();
