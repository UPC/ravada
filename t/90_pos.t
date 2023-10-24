#!perl

use warnings;
use strict;

use IPC::Run3 qw(run3);
use Test::More;

my $DIR_PO = "lib/Ravada/I18N";

my $MSGUNIQ = `which msguniq`;
chomp $MSGUNIQ;
ok($MSGUNIQ,"msguniq required to test po files");

sub test_duplicated {
    my $file = shift;
    open my $in,"<", $file or die "$! $file";
    my $msgid;
    my %found;
    my $string;
    my @warnings;
    while (my $line = <$in>) {
        my ($msgstr) = $line =~ /^msgstr/;
        if ($msgstr && $string) {
            my $string_lc = uc($string);
            if($found{$string_lc}) {
                push@warnings,("'$string' duplicated in line ".$found{$string_lc}." and $.");
            }
            $found{$string_lc}=$.;
            $string = undef;
            next;
        }
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
    if (@warnings){
        diag("Warning: duplicated strings found in $file");
        diag(join("\n",map {"  - $_" } @warnings));
    }
}

my @po;
opendir my $po,$DIR_PO or die "$! $DIR_PO";
while (my $file = readdir $po) {
    next if $file !~ /\.po$/;
    push @po,($file);
}
closedir $po;

for my $file (@po) {
    test_duplicated("$DIR_PO/$file");
}

SKIP: {
    skip("Missing msguniq", scalar @po) if !$MSGUNIQ;
    for my $file (@po) {
        my @cmd = ($MSGUNIQ, "--repeated","lib/Ravada/I18N/$file");

        my ($in, $out, $err);

        run3(\@cmd, \$in, \$out, \$err);

        is($?,0, $file);
        is($err,'', $file);
    }

}

done_testing();
