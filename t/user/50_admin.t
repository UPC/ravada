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
    is($user->password_will_be_changed(),1);
    ok($user->password_expiration_date());
    ok($user->password_expiration_date()-time >= 590 );

    $user->password_expiration_date(time-1);

    eval {
        $user->_data('fails');
    };
    like($@,qr/Wrong field/i);

    my $user2;
    eval { $user2= Ravada::Auth::login('admin','admin');};
    like($@, qr/Password expired/, "Expected error message");
    ok(!$user2);

    $user->password_expiration_date(time+300);
    eval { $user2= Ravada::Auth::login('admin','admin');};
    ok($user2);

    my $p = "newnew";
    $user2->change_password($p);

    eval { $user2= Ravada::Auth::login('admin',$p);};
    ok($user2);
    is($user2->password_expiration_date(),0);
    is($user2->password_will_be_changed(),0);

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
