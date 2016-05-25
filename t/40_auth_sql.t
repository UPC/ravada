use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

use_ok('Ravada');
use_ok('Ravada::Auth::SQL');

ok($Ravada::Auth::SQL::CON,"Undefined DB connection");

my $RAVADA = Ravada->new(connector => $test->connector);

Ravada::Auth::SQL::add_user('test',$$);

my $sth = $$Ravada::Auth::SQL::CON->dbh->prepare("SELECT * FROM users WHERE name=?");
$sth->execute('test');
ok($sth->fetchrow,"I can't find test user in the database") or exit;


ok(Ravada::Auth::SQL::login('test',$$,"I can't login test/$$"));

done_testing();
