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

mkdir $DIR_FALLBACK or die "Error: $! $DIR_FALLBACK"
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
    elsif ($res->is_error)    { print $res->message."\n"; exit }
    elsif ($res->code == 301) { print $res->headers->location."\n" }
    else                      { print "Error ".$res->code." ".$res->message
                                    ." downloading $url\n";
                                    exit;
                                }
    return $dst;
}

sub uncompress($file) {
    chdir $DIR_FALLBACK or die "$! $DIR_FALLBACK";
    print `unzip -oq $file`;
}

sub get_version_badge {
    return if $VERSION =~/alpha/;
    #    $VERSION =~ s/-/--/;
    download("https://img.shields.io/badge/version-$VERSION-brightgreen.svg"
        ,"../img/version-$VERSION-brightgreen.svg");
}

sub remove_old_version_badge {
    $VERSION =~ s/-/--/;
    my $current = "version-$VERSION-brightgreen.svg";
    opendir my $dir,"public/img" or die "$! public/img";
    while (my $file = readdir $dir) {
        next if $file !~ /^version-.*\.svg/;
        next if $file eq $current;
        $file = "public/img/$file";
        unlink $file or die "$! $file";
    }
    closedir $dir;

}

#############################################################################

remove_old_version_badge();
get_version_badge();

open my $in,'<',$FILE_CONFIG or die "$! $FILE_CONFIG";
while (<$in>) {
    next if /^#/;
    my ($url, $dst) = split;
    my $file = download($url, $dst);
    uncompress($file) if $file =~ /\.zip$/;
}
close $in;
