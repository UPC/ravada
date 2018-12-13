package Ravada::Repository::ISO;

use warnings;
use strict;

use Data::Dumper;
use YAML qw(LoadFile);

use feature qw(signatures);
no warnings "experimental::signatures";

our $DIR_ISO_YML = "etc/repository/iso";
$DIR_ISO_YML = "/var/lib/ravada/repository/iso" if $0 =~ m{^/usr/sbin};

our $CONNECTOR = \$Ravada::CONNECTOR;

sub insert_iso_yml($file, $verbose = 0) {
    my $entry = LoadFile($file);
    return Ravada::_update_table(undef, 'iso_images','name', { $file => $entry }, $verbose );
}

sub insert_iso_locale($locale, $verbose = 0) {

    my $n_found = 0;

    my $dir = "$DIR_ISO_YML/$locale";
    opendir my $ls,$dir or do {
        return 0;
    };
    while (my $file = readdir $ls) {
        next if $file !~ /\.yml$/;
        insert_iso_yml("$dir/$file", $verbose);

        $n_found++;
    }
    closedir $ls;

    return $n_found;
}

1;
