use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::VM::Void');
use_ok('Ravada::Auth::SQL');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $ravada = rvd_back($test->connector , 't/etc/ravada.conf');

#
# Create a new user
#
sub test_create_user {

    my $name = shift;
    my $is_admin = shift or 0;

    Ravada::Auth::SQL::add_user(name => $name, password => 'bar', is_admin => $is_admin);

    my $user = Ravada::Auth::SQL->new(name => $name, password => 'bar');
    if ($is_admin) {
        ok($user->is_admin,"User $name should be admin");
    } else {
        ok(! $user->is_admin,"User $name should not be admin");
    }

    return $user;
}

sub test_create_domain {
    my $user = shift;

    my $vm = Ravada::VM::Void->new();
    ok($vm,"I can't connect void VM");

    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain(name => $domain_name, id_owner => $user->id);

    ok($domain,"No domain $domain_name created");

    ok($domain->name eq $domain_name, "Expecting domain name $domain_name , got "
        .($domain->name or '<UNDEF>'));
    ok($domain->id_owner
        && $domain->id_owner eq $user->id,"Expecting owner=".$user->id
                                        ." , got ".$domain->id_owner);
    return $domain;
}

#
# test display allowed
#
sub test_display {

    my ($domain, $user1, $user2) = @_;
    my $display;
    
    eval { $display = $domain->display($user1) };
    ok($display, "User ".$user1->name." should be able to view ".$domain->name." $@ "
        .Dumper($user1));
    $display = undef;
    
    eval { $display = $domain->display($user2) };
    ok(!$display, "User ".$user2->name." shouldn't be able to view ".$domain->name);
}

sub create_admin_user {
    my $name = shift;

    my $user = test_create_user($name, 1);
    ok($user->is_admin);

    return $user;
}

######################################3

remove_old_domains();
remove_old_disks();

my $user_foo = test_create_user('foo');
my $user_bar = test_create_user('bar');
my $domain = test_create_domain($user_foo);
test_display($domain,$user_foo , $user_bar );

my $user_admin = create_admin_user('mcnulty');
test_display($domain,$user_admin , $user_bar );

remove_old_domains();
remove_old_disks();

done_testing();

