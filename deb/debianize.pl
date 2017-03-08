#!/usr/bin/perl

use warnings;
use strict;

use File::Path qw(remove_tree make_path);
use IPC::Run3;
use lib './lib';
use Ravada;
use File::Copy;

my %DIR = (
    templates => 'var/www/ravada'
    ,'bin/' => 'usr/sbin'
    ,'rvd_front.pl' => 'usr/sbin'
    ,'etc/ravada.conf' => 'etc'
    ,'etc/xml'  => 'var/lib/ravada'
    ,'etc/systemd/' => 'lib/systemd/system'
    ,docs => 'usr/share/doc/ravada'
    ,sql => 'usr/share/doc/ravada'
    ,public => 'var/www/ravada'
    ,lib => 'usr/share/perl5'
);

my @REMOVE= qw(
    usr/share/doc/ravada/docs/_config.yml
    public/img/screenshots
);

########################################################################

sub clean {
    for my $src (sort keys %DIR ) {
        my $dst = "pkg-debian/$DIR{$src}";
        next if ! -e $dst;
        remove_tree($dst);
    }
}

sub copy_files {
    for my $src (sort keys %DIR) {
        my $dst = "pkg-debian/$DIR{$src}";
        make_path($dst) if ! -e $dst;

        my ($in, $out, $err);
        my @cmd = ('rsync','-av',$src,$dst);
        run3(\@cmd, \$in, \$out, \$err);
        die $err if $err;
    }
}

sub remove_not_needed {
    for my $file (@REMOVE) {
        $file = "pkg-debian/$file";
        unlink $file or die $!
            if -e $file;
    }
}

sub create_md5sums {
    my @files;
    chdir "pkg-debian" or die "I can't chdir to pkg-debian";

    unlink "DEBIAN/md5sums";

    open my $find, ,'-|', 'find . -type f -printf \'%P\n\'' or die $!;
    while (<$find>) {
        chomp;
        next if /^DEBIAN/;
        print `md5sum $_ >> DEBIAN/md5sums`
    }
    close $find;
    chdir "..";
}

sub create_deb {
    my @cmd = ('dpkg','-b','pkg-debian/',"ravada_${Ravada::VERSION}_all.deb");
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
}

sub remove_use_lib {
    for my $file ('rvd_front.pl','rvd_back.pl') {
        my $path = "pkg-debian/usr/sbin/$file";
        die "Missing file '$path'" if ! -e $path;
        copy($path, "$path.old") or die "$! $path -> $path.old";
        open my $in,'<',"$path.old" or die "$! $path.old";
        open my $out,'>',$path      or die "$! $path";
        while (<$in>) {
            next if /^use lib/;
            print $out $_;
        }
        close $out;
        close $in;

        unlink "$path.old" or die "$! $path.old";
    }
}

#########################################################################

clean();
copy_files();
remove_not_needed();
remove_use_lib();
create_md5sums();
create_deb();
