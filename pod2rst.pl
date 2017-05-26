#!/usr/bin/perl

use warnings;
use strict;

use File::Basename;


my $cmd = "find . -regex '.*.pm'";
my @list = `$cmd`;
chomp @list;

foreach my $line (@list)
{
            print "$line\n";
}

