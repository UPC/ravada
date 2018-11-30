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

sub insert_iso_yml($file) {
    my $entry = LoadFile($file);
    Ravada::_update_table(undef, 'iso_images','name', { $file => $entry } );
}

sub insert_iso_locale($locale) {
    my $dir = "$DIR_ISO_YML/$locale";
    opendir my $ls,$dir or return;
    while (my $file = readdir $ls) {
        next if $file !~ /\.yml$/;
        insert_iso_yml("$dir/$file");
    }
    closedir $ls;
}

1;
