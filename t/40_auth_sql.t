use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
use_ok('Ravada::Auth::SQL');


my $RAVADA = Ravada->new(connector => $test->connector);

Ravada::Auth::SQL::add_user(name => 'test',password => $$);

ok($$Ravada::Auth::SQL::CON,"Undefined DB connection");

my $sth = $$Ravada::Auth::SQL::CON->dbh->prepare("SELECT * FROM users WHERE name=?");
$sth->execute('test');
my $row = $sth->fetchrow_hashref;
ok($row->{name} eq 'test' ,"I can't find test user in the database ".Dumper($row));


ok(Ravada::Auth::SQL::login('test',$$),"I can't login test/$$");

done_testing();
