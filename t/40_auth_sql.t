use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
use_ok('Ravada::Auth::SQL');
use_ok('Ravada::DB');

my $connector =Ravada::DB->instance(connector => $test->connector());

my $RAVADA = Ravada->new();

Ravada::Auth::SQL::add_user(name => 'test',password => $$);

my $sth = Ravada::DB->instance->dbh->prepare("SELECT * FROM users WHERE name=?");
$sth->execute('test');
my $row = $sth->fetchrow_hashref;
ok($row->{name} eq 'test' ,"I can't find test user in the database ".Dumper($row));


ok(Ravada::Auth::SQL::login('test',$$),"I can't login test/$$");

done_testing();
