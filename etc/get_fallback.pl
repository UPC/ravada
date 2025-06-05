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

my $FILE_CONFIG = getcwd.'/etc/fallback.conf';
my $DIR_FALLBACK = getcwd.'/public/fallback';
my $DIR_IMG = getcwd."/public/img";

if (! -e $FILE_CONFIG && -e "/etc/ravada.conf") {
    die "Error: run $0 from root.\n" if $<;
    $FILE_CONFIG="/usr/share/ravada/fallback.conf";
    $DIR_FALLBACK = "/usr/share/ravada/public/fallback";
    $DIR_IMG = "/usr/share/ravada/public/img";
}

mkdir $DIR_FALLBACK or die "Error: $! $DIR_FALLBACK"
    if ! -e $DIR_FALLBACK;

chdir $DIR_FALLBACK;

sub download($url, $dst = $DIR_FALLBACK) {

    die "Error: no dst for '$url'" if !defined $dst;

    $dst = "$DIR_FALLBACK/$dst" if $dst !~ m{^/};

    my ($path) = $dst =~ m{(.*)/};
    make_path($path) if ! -e $path;

    if ( -d $dst ) {
        my ($filename) = $url =~ m{.*/(.*)};
        die "Error: no filename found in '$url'" if !$filename;
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
    chmod 0755,$dst if !$<;
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
        ,"$DIR_IMG/version-$VERSION-brightgreen.svg");
}

sub remove_old_version_badge {
    $VERSION =~ s/-/--/;
    my $current = "version-$VERSION-brightgreen.svg";
    opendir my $dir,$DIR_IMG or die "$! $DIR_IMG";
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
    uncompress($file) if $file && $file =~ /\.zip$/;
}
close $in;
