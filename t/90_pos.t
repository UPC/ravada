#!perl

use warnings;
use strict;

use IPC::Run3 qw(run3);
use Test::More;

my $DIR_PO = "lib/Ravada/I18N";

opendir my $po,$DIR_PO or die "$! $DIR_PO";
while (my $file = readdir $po) {
    next if $file !~ /\.po/;

    my @cmd = ("/usr/bin/msguniq", "--repeated","lib/Ravada/I18N/$file");

    my ($in, $out, $err);

    run3(\@cmd, \$in, \$out, \$err);

    is($?,0, $file);
    is($err,'', $file);
}


done_testing();
