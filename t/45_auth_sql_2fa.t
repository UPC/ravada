use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
use_ok('Ravada::Auth::SQL');
use_ok('Ravada::Auth::2FA');


my $RAVADA = Ravada->new(connector => $test->connector);

Ravada::Auth::SQL::add_user(name => 'test',password => $$, two_fa => 1);

ok($$Ravada::Auth::SQL::CON,"Undefined DB connection");

my $sth = $$Ravada::Auth::SQL::CON->dbh->prepare("SELECT two_fa FROM users WHERE name=?");
$sth->execute('test');
my $row = $sth->fetchrow_hashref;
ok($row->{two_fa} eq '1' ,"2FA is not enable in the database ".Dumper($row));

$sth = $$Ravada::Auth::SQL::CON->dbh->prepare("SELECT * FROM users WHERE name=?");
$sth->execute('test');
$row = $sth->fetchrow_hashref;
ok($row->{name} eq 'test' ,"I can't find test user in the database ".Dumper($row));


ok(Ravada::Auth::SQL::login('test',$$),"I can't login test/$$");

my $base32Secret = Ravada::Auth::2FA->generateBase32Secret();
my $keyId = "RavadaVDI ($row->{name})";
warn "Secret $base32Secret \n";
my $qr = qrImageUrl($keyId, $base32Secret);
warn "QR image: $qr \n";
ok(qrImageUrl($keyId, $base32Secret) =~ m{^https://}, "I can't generate HTTPS URL with QR image");

ok(generateCurrentNumber($base32Secret) =~ m{^\d{6}$}, "I can't generate 6 digits code");

#Save secret to db
$sth = $$Ravada::Auth::SQL::CON->dbh->prepare("UPDATE users SET secret=? WHERE name=?");
$sth->execute($base32Secret, $row->{name});
$sth = $$Ravada::Auth::SQL::CON->dbh->prepare("SELECT secret FROM users WHERE name=?");
$sth->execute('test');
$row = $sth->fetchrow_hashref;
like($row->{secret}, qr{.{16}$}, "I can't insert secret in db");

done_testing();
