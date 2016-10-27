use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Auth::SQL');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $ravada = Ravada->new(connector => $test->connector);

Ravada::Auth::SQL::add_user('root','root', 1);

Ravada::Auth::LDAP(0);

{
    my $user_fail;
    eval { $user_fail = Ravada::Auth::SQL->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
{
    my $user = Ravada::Auth::SQL->new(name => 'root',password => 'root');
    
    ok($user);
    ok($user->id, "User ".$user->name." has no id");
    ok($user->is_admin,"User ".$user->name." should be admin ".Dumper($user->{_data}));

    my $user2 = Ravada::Auth::SQL->search_by_id($user->id );
    ok($user2, "I can't open user with id") or return;
    ok($user2->id eq $user->id ,"Expecting user id=".$user->id." , got ".$user2->id);
    ok($user2->name eq $user->name,"Expecting user name =".$user->name." , got ".$user2->name);
    ok($user2->is_admin,"User ".$user2->name." should be admin ".Dumper($user2->{_data}));

    my $user3 = Ravada::Auth::login('root','root');
    ok($user3,"No user returned from Ravada::Auth::login");
    ok(ref $user && ref($user3) eq 'Ravada::Auth::SQL');
    ok($user3->is_admin,"User ".$user3->name." should be admin ".Dumper($user3->{_data}));

}
    
Ravada::Auth::SQL::add_user('mcnulty','jameson');
    
{
    my $mcnulty= Ravada::Auth::SQL->new(name => 'mcnulty',password => 'jameson');
    
    ok($mcnulty);
    ok(!$mcnulty->is_admin,"User ".$mcnulty->name." should not be admin "
            .Dumper($mcnulty->{_data}));

    my @messages = $mcnulty->messages();
    ok(!scalar @messages);
    my $user3 = Ravada::Auth::login('mcnulty','jameson');
    ok($user3,"No user returned from Ravada::Auth::login");
    ok(ref $user3 && ref($user3) eq 'Ravada::Auth::SQL');
    ok(!$user3->is_admin,"User ".$user3->name." should not be admin ".Dumper($user3->{_data}));

}
    
    
done_testing();
