use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Auth::SQL');

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my $ravada = Ravada->new(connector => $test->connector);

Ravada::Auth::SQL::add_user('root','root', 1);

{
    my $user_fail;
    eval { $user_fail = Ravada::Auth::SQL->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
{
    my $user = Ravada::Auth::SQL->new(name => 'root',password => 'root');
    
    ok($user);
    ok($user->is_admin,"User ".$user->name." should be admin ".Dumper($user->{_data}));
}
    
Ravada::Auth::SQL::add_user('mcnulty','jameson');
    
{
    my $mcnulty= Ravada::Auth::SQL->new(name => 'mcnulty',password => 'jameson');
    
    ok($mcnulty);
    ok(!$mcnulty->is_admin,"User ".$mcnulty->name." should not be admin "
            .Dumper($mcnulty->{_data}));
}
    
    
done_testing();
