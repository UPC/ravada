#!perl

use warnings;
use strict;

use Data::Dumper;
use IPC::Run3 qw(run3);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

my $DIR_PO = "lib/Ravada/I18N";

my $MSGUNIQ = `which msguniq`;
chomp $MSGUNIQ;
ok($MSGUNIQ,"msguniq required to test po files");

my $FIX = ( $ENV{FIX_PO} or 0 );

sub read_po($file) {
    open my $in,"<",$file or die "$! $file";
    my $string;

    my $line;
    my %found;
    while ($line =<$in>) {
        last if $line =~ /X-Generator/;
    }

    while ($line =<$in>) {
        my ($msgid)= $line =~ /msgid\s+"(.*)"/;
        my ($msgstr)=$line =~ /msgstr\s+"(.*)"/;
        my ($more) = $line =~ /"(.*)"/;
        if (defined $msgid) {
            $string = $msgid;
        } elsif(defined $msgstr) {
            $found{$string}++;
            $string = undef;
        } elsif ( defined $string && $more) {
            $string .= $more;
        }
    }
    close $in;

    return %found;
}

sub read_template($file){
    open my $in,"<",$file or die "$! $file";
    my %strings;
    while (my $line = <$in>) {
        my ($string) = $line =~ /<%=l '(.*?)'\s*%>/;
        next if !$string;
        $string =~ s{\\}{};
        $strings{$string}++;
    }
    return keys %strings;
}

sub list_templates($dir) {
    opendir my $ls,$dir or die "$!";
    my @templates;
    my @dirs;
    while (my $file = readdir $ls) {
        push @dirs,("$dir/$file") if -d "$dir/$file" && $file !~ /^\./;
        push @templates,("$dir/$file") if $file =~ /html/;
    }
    for my $dir2 (@dirs) {
        push @templates, list_templates($dir2);
    }
    return @templates;
}
sub find_strings() {
    my $file_po = "$DIR_PO/en.po";
    my %msgid = read_po($file_po);
    my @templates = list_templates("templates");
    for my $file (@templates) {
        my @strings = read_template($file);
        my @missing;
        for my $string (@strings) {
            push @missing,($string) if !$msgid{$string};
        }
        ok(!@missing,"$file ".Dumper(\@missing));
        if (@missing && $FIX) {
            add_strings($file_po, @missing);
            diag("Added to $file_po");
            last;
        }
    }
}

sub add_strings($file, @strings) {

    open my $out,">>",$file or die "$! $file";
    for my $string (@strings) {

        print $out "\n"
        ."msgid \"$string\"\n"
        ."msgstr \"$string\"\n";
    }
}

my @po;
opendir my $po,$DIR_PO or die "$! $DIR_PO";
while (my $file = readdir $po) {
    next if $file !~ /\.po/;
    push @po,($file);
}
closedir $po;


SKIP: {
    skip("Missing msguniq", scalar @po) if !$MSGUNIQ;
    for my $file (@po) {
        my @cmd = ($MSGUNIQ, "--repeated","lib/Ravada/I18N/$file");

        my ($in, $out, $err);

        run3(\@cmd, \$in, \$out, \$err);

        is($?,0, $file);
        is($err,'', $file);
    }

    find_strings();

}

done_testing();
