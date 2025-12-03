#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

################################################################

# Test that admin user is not created when another admin already exists
sub test_admin_no_need {

    my $user = Ravada::Auth::SQL->new(name => 'admin');
    $user->remove() if $user->id;

    rvd_back->_install();

    $user = Ravada::Auth::SQL->new(name => 'admin');
    ok(!$user->id);
}

sub test_default_admin {

    user_admin->remove();

    rvd_back->_install();

    my $user = Ravada::Auth::login('admin','admin');
    ok($user);
}

################################################################


my $user = create_user("falken","joshua");

user_admin->make_admin($user->id);

$user = Ravada::Auth::SQL->search_by_id($user->id);
is($user->is_admin, 1);

user_admin->remove_admin($user->id);

$user = Ravada::Auth::SQL->search_by_id($user->id);
is($user->is_admin,0 );

test_admin_no_need();
test_default_admin();

end();
done_testing();
