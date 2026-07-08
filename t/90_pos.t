#!perl

use warnings;
use strict;

use IPC::Run3 qw(run3);
use Test::More;

my $DIR_PO = "lib/Ravada/I18N";
my $POT_FILE = "$DIR_PO/messages.pot";

my $MSGUNIQ = `which msguniq`;
chomp $MSGUNIQ;
ok($MSGUNIQ,"msguniq required to test po files");

my @po;
opendir my $po,$DIR_PO or die "$! $DIR_PO";
while (my $file = readdir $po) {
    next if $file !~ /\.po$/;
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

}

_check_pot_contains_all_po_strings();

done_testing();

sub _decode_po_string {
    my ($s) = @_;
    $s =~ s/^"(.*)"$/$1/s;
    $s =~ s/\\n/\n/g;
    $s =~ s/\\t/\t/g;
    $s =~ s/\\"/"/g;
    $s =~ s/\\\\/\\/g;
    return $s;
}

sub _get_msgids {
    my ($filepath) = @_;
    my %msgids;
    open my $fh, '<:encoding(UTF-8)', $filepath or die "$! $filepath";
    my @lines = <$fh>;
    close $fh;

    my $i = 0;
    while ($i < scalar @lines) {
        my $line = $lines[$i];
        chomp $line;
        if ($line =~ /^msgid (.*)/) {
            my @parts = ($1);
            $i++;
            while ($i < scalar @lines && $lines[$i] =~ /^"/) {
                my $part = $lines[$i];
                chomp $part;
                push @parts, $part;
                $i++;
            }
            my $decoded = join('', map { _decode_po_string($_) } @parts);
            $msgids{$decoded} = 1 if length($decoded);
        } else {
            $i++;
        }
    }
    return %msgids;
}

sub _check_pot_contains_all_po_strings {
    my %pot_ids = _get_msgids($POT_FILE);

    for my $po_file (sort qw(ca.po en.po es.po)) {
        my %po_ids = _get_msgids("$DIR_PO/$po_file");
        my @missing;
        for my $msgid (sort keys %po_ids) {
            push @missing, $msgid unless exists $pot_ids{$msgid};
        }
        is(scalar @missing, 0, "messages.pot contains all strings from $po_file")
            or diag("Missing from messages.pot:\n" . join("\n", map { "  '$_'" } @missing));
    }
}
