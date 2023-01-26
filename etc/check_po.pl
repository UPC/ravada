#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use File::Find;

use feature qw(signatures);
no warnings "experimental::signatures";

my @TEMPLATES;

sub load_strings($lang) {

    my $file = "lib/Ravada/I18N/$lang.po";
    open my $in,"<",$file or die "$! $file";

    my %strings;
    while (my $line =<$in>) {
        my ($msgid) = $line =~ /msgid "(.*)"/;
        next if !$msgid;

        die "Error : $msgid duplicated in $file\n" if $strings{$msgid};

        $strings{$msgid}++;
    }
    close $file;

    return %strings;
}

sub find_new_strings($strings) {

    find (\&wanted,"templates");

    my %lc = map { lc($_) => 1 } keys %$strings;

    for my $file (@TEMPLATES) {
        open my $in,"<",$file or die "$! $file";
        my @new;
        my @lc;
        while (my $line=<$in>) {
            my @found = $line =~ m{<%=l '(.*?)'\s*%}g;
            next if !@found;
            for my $line (@found) {
                $line =~ s/\\'/'/g;
                next if $strings->{$line};
                my $line_lc = lc($line);
                if ($lc{$line}) {
                    push @lc,($line);
                    next;
                }
                push @new,($line) if !$strings->{$line};
            }
        }
        next if !@new;
        print "$file\n";
        print "  Different Case :\n".Dumper(@lc)."\n" if @lc;
        print "  New:\n".Dumper(\@new)."\n" if @new;
    }
}

sub wanted {
    my $file = $File::Find::name;
    return if $file !~ /\.html.ep$/;
    push @TEMPLATES,($file);
}

my %en = load_strings('en');

find_new_strings(\%en);
