#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

################################################################

my $user = create_user("falken","joshua");

user_admin->make_admin($user->id);

$user = Ravada::Auth::SQL->search_by_id($user->id);
is($user->is_admin, 1);

user_admin->remove_admin($user->id);

$user = Ravada::Auth::SQL->search_by_id($user->id);
is($user->is_admin,0 );

done_testing();
