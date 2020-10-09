#!/usr/bin/perl

use warnings;
use strict;

use Carp qw(confess);
use Test::More;

use_ok('Ravada');

use lib 't/lib';
use Test::Ravada;

init();

my $sth = connector->dbh->prepare("SELECT DISTINCT xml FROM iso_IMAGES");

$sth->execute;
while (my ($xml) = $sth->fetchrow ){
    ok(-e "etc/xml/$xml", $xml);
}

$sth = connector->dbh->prepare("SELECT DISTINCT xml_volume FROM iso_IMAGES");

$sth->execute;
while (my ($xml) = $sth->fetchrow ){
    ok(-e "etc/xml/$xml", $xml);
}

end();
done_testing();
