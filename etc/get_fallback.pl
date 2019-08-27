#!/usr/bin/perl

use warnings;
use strict;

use Cwd;
use File::Path qw(make_path);
use Mojo::UserAgent;

use lib './lib';
use Ravada;

my $VERSION = Ravada::version();
no warnings "experimental::signatures";
use feature qw(signatures);

my $ua  = Mojo::UserAgent->new;
$ua->max_redirects(4);

my $FILE_CONFIG = 'etc/fallback.conf';
my $DIR_FALLBACK = getcwd.'/public/fallback';

die "Error: missing fallback dir $DIR_FALLBACK"
    if ! -e $DIR_FALLBACK;

sub download($url, $dst = $DIR_FALLBACK) {

    $dst = "$DIR_FALLBACK/$dst" if $dst !~ m{^/};

    my ($path) = $dst =~ m{(.*)/};
    make_path($path) if ! -e $path;

    if ( -d $dst ) {
        my ($filename) = $url =~ m{.*/(.*)};
        $dst .= "/" if $dst !~ m{/$};
        $dst .= $filename;
    }

    return $dst if -e $dst;

    print "get $url\n";
    my $res = $ua->get($url)->result;
    if ($res->is_success)  {
        print "$url downloaded to $dst\n";
        $res->content->asset->move_to($dst);
    }
    elsif ($res->is_error)    { print $res->message."\n" }
    elsif ($res->code == 301) { print $res->headers->location."\n" }
    else                      { print "Error ".$res->code." ".$res->message
                                    ." downloading $url\n"}
    return $dst;
}

sub uncompress($file) {
    chdir $DIR_FALLBACK or die "$! $DIR_FALLBACK";
    print `unzip -o $file`;
}

sub get_version_badge {
    download("https://img.shields.io/badge/version-$VERSION-brightgreen.svg"
        ,"../img/version-$VERSION-brightgreen.svg");
}

#############################################################################

get_version_badge();

open my $in,'<',$FILE_CONFIG or die "$! $FILE_CONFIG";
while (<$in>) {
    next if /^#/;
    my ($url, $dst) = split;
    my $file = download($url, $dst);
    uncompress($file) if $file =~ /\.zip$/;
}
close $in;
