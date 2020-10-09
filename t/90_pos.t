#!perl

use warnings;
use strict;

use IPC::Run3 qw(run3);
use Test::More;

my $DIR_PO = "lib/Ravada/I18N";

my $MSGUNIQ = `which msguniq`;
chomp $MSGUNIQ;
ok($MSGUNIQ,"msguniq required to test po files");

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

}

done_testing();
