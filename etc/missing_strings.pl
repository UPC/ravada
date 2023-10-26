#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;

my $DIR = "lib/Ravada/I18N";

my %LIST = map { $_ => 1 } @ARGV;

sub selected {
    my $file = shift;
    my ($name) = $file =~ m{(.*)\.\w+};

    return 0 if !exists $LIST{$name};
    return $LIST{$name};
}

sub load_strings {
    my $file = shift;

    if ($file !~ m{/}) {
        $file = "$DIR/$file";
    }
    open my $in,"<",$file or die "$! $file";

    my $msgid;
    my %found;
    my $string;
    my $comment='';
    my %dupe;
    while (my $line = <$in>) {
        my ($msgstr) = $line =~ /^msgstr/;
        if ($msgstr && $string) {
            my $string_lc = lc($string);
            if ($dupe{$string_lc}) {
                warn("Warning: '$string' duplicated in line ".$dupe{$string_lc}." and $.\n");
            } else {
                $dupe{$string_lc} = $.;
            }
            $found{$string}=[$.,$comment];
            $comment= '';
            $string = undef;
            next;
        }
        $comment = $line if $line =~ /^#/;
        my ($string1) = $line =~ /^msgid "(.*)"/;
        if (defined $string1) {
            $string = $string1;
            next;
        }
        if (!defined $string1 && defined $string) {
            my ($string2) = $line =~ /^"(.*)"/;
            if (defined $string2) {
                $msgid=0;
                $string = "$string$string2";
            }
        }
        next if !$string;
    }
    close $in;
    die Dumper($found{"Schedule"});
    return \%found;
}

my $english = load_strings('en.po');
my $found=0;


opendir my $in,$DIR or die "$! $DIR";
while (my $file = readdir $in) {
    next if $file !~ /\.po$/;
    next if keys %LIST && !selected($file);
    my $path = "$DIR/$file";
    next if !-f $path;
    print "$path\n";

    my $string = load_strings($file);
    for my $key (sort keys %$english) {
        next if $string->{$key};
        print "msgid \"$key\"\n"
                ."msgstr \"\"\n\n";
        $found++;
    }
    last if $found;
}
closedir $in;
