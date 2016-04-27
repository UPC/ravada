package Ravada::Auth::SQL;

use warnings;
use strict;

use Digest::SHA qw(sha1_hex);

our $CON;

sub init {
    my ($config, $con) = @_;
    $CON = $con;
}

sub add_user {
    my ($login,$password) = @_;
    my $sth = $CON->dbh->prepare(
            "INSERT INTO users (name,password) VALUES(?,?)");

    $sth->execute(sha1_hex($password));
    $sth->finish;
}

sub login {
    my ($login,$password) = @_;

    my $sth = $CON->dbh->prepare(
       "SELECT name FROM users WHERE name=? AND password=?");
    $sth->execute(sha1_hex($password));
    my ($found) = $sth->fetchrow;
    $sth->finish;
    return if !$found;
    return $found;
}

1;

