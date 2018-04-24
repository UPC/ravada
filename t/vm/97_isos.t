#!/usr/bin/perl

use warnings;
use strict;

use Carp qw(confess);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
init($test->connector);
rvd_back();

my $sth = $test->connector->dbh->prepare("SELECT DISTINCT xml FROM iso_IMAGES");

$sth->execute;
while (my ($xml) = $sth->fetchrow ){
    ok(-e "etc/xml/$xml", $xml);
}

$sth = $test->connector->dbh->prepare("SELECT DISTINCT xml_volume FROM iso_IMAGES");

$sth->execute;
while (my ($xml) = $sth->fetchrow ){
    ok(-e "etc/xml/$xml", $xml);
}


done_testing();
