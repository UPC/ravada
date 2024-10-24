#!/usr/bin/perl

use warnings;
use strict;

use Carp qw(confess);
use Cwd qw(getcwd);
use Data::Dumper;
use File::Path qw(remove_tree make_path);
use IPC::Run3;
use lib './lib';
use Ravada;
use File::Copy;

my $VERSION = Ravada::version();
my $DIR_SRC = getcwd;
my $DIR_DST;
my $DEBIAN = "DEBIAN";

my %COPY_RELEASES = (
    'ubuntu-19.04'=> ['ubuntu-18.10','ubuntu-19.10']
    ,'debian-10' => ['debian-11']
);
my %DIR = (
    templates => '/usr/share/ravada'
    ,'etc/ravada.conf' => 'etc'
    ,'etc/xml'  => 'var/lib/ravada'
    ,'sql' => 'usr/share/ravada'
    ,'lib/' => 'usr/share/perl5'
    ,'blib/man3' => 'usr/share/man'
    ,"debian/" => "./DEBIAN"
    ,'etc/systemd/' => 'lib/systemd/system/'
);

for ( qw(css fallback fonts img js favicon.ico )) {
    $DIR{"public/$_"} = "usr/share/ravada/public";
}

my %FILE = (
    'etc/rvd_front.conf.example' => 'etc/rvd_front.conf'
    ,'script/rvd_back' => 'usr/sbin/rvd_back'
    ,'script/rvd_front' => 'usr/sbin/rvd_front'
    ,'CHANGELOG.md'   => 'usr/share/doc/ravada/changelog'
    ,'copyright' => 'usr/share/doc/ravada/copyright'
    ,'package.json' => 'usr/share/ravada'
);

my @REMOVE= qw(
    usr/share/ravada/templates/bootstrap/get_authors.sh
    usr/share/man/man3/.exists
    usr/share/man/man3/Ravada::Domain::LXC.3pm
    usr/share/man/man3/Ravada::Domain::Void.3pm
    usr/share/man/man3/Ravada::NetInterface::Void.3pm
);

########################################################################

sub clean {
    remove_tree($DIR_DST);
}

sub copy_dirs {
    for my $src (sort keys %DIR) {
        my $dst = "$DIR_DST/$DIR{$src}";
        make_path($dst) if ! -e $dst;

        my ($in, $out, $err);
        my @cmd = ('rsync','-avL','--exclude','*.zip',$src,$dst);
        run3(\@cmd, \$in, \$out, \$err);
        die $err if $err;
        print `chmod go+rx $dst`;
    }
}

sub copy_files {
    for my $src (sort keys %FILE) {
        my $dst = "$DIR_DST/$FILE{$src}";

        my ($dir) = $dst =~ m{(.*)/.*};
        make_path($dir) if !-d $dir;

        mkdir $dst if $dst =~ m{.*/$} && ! -e $dst;
        copy($src,$dst) or die "$! $src -> $dst";
    }
}

sub remove_not_needed {
    for my $file (@REMOVE) {
        my $file2 = "$DIR_DST/$file";
        unlink $file2 or die "$! $file2";
    }
    for my $dir ('usr/share/ravada/sql/sqlite') {
        my $path = "$DIR_DST/$dir";
        die "Missing $path" if ! -e $path;
        remove_tree($path);
    }
    remove_custom_files("public/js/custom");
}

sub remove_custom_files {
    my $dir = shift;
    opendir my $ls,$dir or die "$! $dir";
    while ( my $file = readdir $ls) {
        next if $file =~ m/^\.+$/;
        my $path = "$dir/$file";
        if ( -d $path ) {
            die "Error: no dirs should be in $dir";
        } elsif ( -f $path ) {
            if ($file !~ /insert_here/) {
                my ($dir_dst, $component) = $dir =~ m{(.*)/(.*)};
                die "Unknown dir $dir " if !exists $DIR{$dir_dst};
                my $deb_path = "$DIR_DST/$DIR{$dir_dst}/$component/$file";
                if (! -e $deb_path ) {
                    ($component) = $dir =~ m{.*/(\w+/\w+)};
                    $deb_path = "$DIR_DST/$DIR{$dir_dst}/$component/$file";
                }
                unlink $deb_path or die "$! $deb_path";
            }
        } else {
            warn "Warning: unknown file type $file (neither file nor dir)";
        }
    }
}

sub create_md5sums {
    my @files;
    chdir $DIR_DST or die "I can't chdir to $DIR_DST";

    unlink "$DEBIAN/md5sums";

    open my $md5sum,'>>',"$DEBIAN/md5sums" or die $!;
    open my $find, ,'-|', 'find . -type f -printf \'%P\n\'' or die $!;
    while (<$find>) {
        chomp;
        next if /^debian/i;
        my @cmd = ('md5sum',$_);
        my ($in,$out,$err);
        run3(\@cmd, \$in, \$out, \$err);
        print $md5sum $out;
    }
    close $find;
    close $md5sum;

    chdir "..";
    chmod 0644,"$DIR_DST/$DEBIAN/md5sums" or die "$! $DIR_DST/$DEBIAN/md5sums";
}

sub create_deb {
    my $dist = shift or confess "Missing dist";

    mkdir "ravada_release" if !-e "ravada_release";
    my $deb = "ravada_release/ravada_${VERSION}_${dist}_all.deb";
    my @cmd = ('dpkg-deb','-b','-Zgzip',"$DIR_DST/",$deb);
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
    print "$deb created\n";
}

sub remove_use_lib {
    for my $file ('usr/sbin/rvd_front','usr/sbin/rvd_back') {
        my $path = "$DIR_DST/$file";
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
        chmod 0755,$path or die "$! chmod 755 $path";
    }
}

sub change_version {
    my $path = "$DIR_DST/usr//share/perl5/Ravada.pm";
    copy($path, "$path.old") or die "$! $path -> $path.old";
    open my $in,'<',"$path.old" or die "$! $path.old";
    open my $out,'>',$path      or die "$! $path";
    while (<$in>) {
        s/(.*our \$VERSION\s*=\s*').*('.*)/$1$VERSION$2/;
        print $out $_;
    }
    close $out;
    close $in;

    unlink "$path.old" or die "$! $path.old";
    chmod 0755,$path or die "$! chmod 755 $path";

}

sub change_mod {
    for my $file ( 'rvd_front.service', 'rvd_back.service') {
        my $path = "$DIR_DST/lib/systemd/system/$file";
        chmod 0644,$path or die "$! $path";
    }
}

sub gzip_docs {
    for my $file ( 'changelog' ) {
        my $path = "$DIR_DST/usr/share/doc/ravada/$file";
        die "Missing $path\n"
            if !-e $path;
        print `gzip -n -9 $path`;
    }
}

sub gzip_man {
    my $dir = "$DIR_DST/usr/share/man/man3" ;
    opendir my $ls,$dir or die "$! $dir";
    while ( my $file = readdir $ls ) {
        next if ! -f "$dir/$file";
        print `gzip -n -9 $dir/$file`;
    }
    closedir $ls;
}

sub chown_files {
    my $dir = shift;
    my $file_perm = ( shift or 0644);
    my $dir_perm = (shift or 0755);

    my $deb_dir = "$DIR_DST/$dir";
    chmod($dir_perm,$deb_dir)   or die "$! $deb_dir";
    chown(0,0,$deb_dir)         or die "$! $deb_dir";

    return if ! -d $deb_dir;

    opendir my $ls,$deb_dir or die "$! $deb_dir";
    while (my $file = readdir $ls) {
        next if $file =~ m{^\.};
        my $path = "$deb_dir/$file";
        die "Missing $path"         if ! -e $path;
        chown(0,0,$path)            or die "$! $path";
        if ( -f $path ) {
            chmod ($file_perm, $path)   or die "$! $path";
#            printf("chmod %o $path\n",$file_perm);
        }
        chown_files("$dir/$file")   if -d $path;
    }
    closedir $ls;
}

sub chown_pms {
    print `find $DIR_DST/ -iname "*pm" -exec chmod 755 {} \\;`;
    print `find $DIR_DST/usr/share -iname "*po" -exec chmod 755 {} \\;`;
}

sub chmod_control_files {
    for (qw(control conffiles)) {
        my $path  = "$DIR_DST/$DEBIAN/$_";
        confess "Missing $path"                    if ! -e $path;
        chmod 0644 , $path or die "$! $path"    if -e $path;
    }

    for(qw(conffiles)) {
        my $path  = "$DIR_DST/$DEBIAN/$_";
        chmod 0644 , $path or die "$! $path"    if -e $path;
    }
}

sub chmod_ravada_conf {
    chmod 0600,"$DIR_DST/etc/ravada.conf" or die $!;
}

sub tar {
    my $dist = shift;
    my @cmd = ('tar','czvf',"ravada_$VERSION.orig.tar.gz"
       ,"ravada-$VERSION-$dist"
    );
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    confess $err if $err;
}

sub make_pl {
    chdir $DIR_SRC or die "$! $DIR_SRC";
    my @cmd = ('perl','Makefile.PL');
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    @cmd = ('make');
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
}

sub set_version {

    my $file_in = "$DIR_DST/DEBIAN/control";
    my $file_out = "$file_in.version";

    open my $in ,'<',$file_in   or confess "$! $file_in";
    open my $out,'>',$file_out  or die "$! $file_out";

    my $version = $VERSION;
    $version =~ s/_/-/g;

    my $changed = 0;
    while (my $lin=<$in>) {
        my $lin2 = $lin;
        $lin2 =~ s/^(Version:\s+)([0-9\.]+)/$1$version/;
        $changed++ if $lin ne $lin2;

        print $out $lin2;
    }

    close $out;
    close $in;

    if ($changed) {
        copy($file_out, $file_in) or die "$! $file_out -> $file_in";
    }
    unlink $file_out;
}

sub list_dists {
    opendir my $dir,'debian' or die "$! debian";
    my @dists;

    while ( my $file = readdir $dir ) {
        my ($dist) = $file =~ /control-(.*)/;
        push @dists,($dist) if $dist;
    }
    closedir $dir;

    die "Error: no dists control files found in 'debian' dir"
        if !@dists;

    return reverse @dists;
}

sub set_control_file {
    my $dist = shift;
    my $dst = "$DIR_DST/DEBIAN/control";
    my $src = "$dst-$dist";

    die "Error: no $src" if ! -e $src;
    copy($src, $dst) or die "$! $src -> $dst";

    opendir my $dir,"$DIR_DST/DEBIAN" or die $!;

    while ( my $file = readdir $dir ) {
        unlink "$DIR_DST/DEBIAN/$file" or die "$! $file"
            if $file =~ /^control-/;
    }
    closedir $dir;
}

sub get_fallback {
    print `etc/get_fallback.pl`;
}

sub copy_identical_releases {
    for my $source (sort keys %COPY_RELEASES ) {
        for my $copy (@{$COPY_RELEASES{$source}}) {
            my $file_source = "$DIR_SRC/../ravada_release/ravada_${VERSION}_${source}_all.deb";
            die "Error: No $file_source" if !-e $file_source;
            my $file_copy = "$DIR_SRC/../ravada_release/ravada_${VERSION}_${copy}_all.deb";
            copy($file_source, $file_copy) or die "Error: $!\n$file_source -> $file_copy";
        }
    }
    exit;
}

#########################################################################

get_fallback();

for my $dist (list_dists) {

$DIR_DST = "$DIR_SRC/../ravada-$VERSION-$dist";
clean();
make_pl();
copy_dirs();
copy_files();
set_control_file($dist);
set_version();
remove_not_needed();
remove_use_lib();
change_version();
change_mod();
gzip_docs();
gzip_man();
chown_files($DEBIAN,0644);
chown_files('etc');
chown_files('lib');
chown_files('var');
chown_files('DEBIAN',0755);
chown_files('DEBIAN/conffiles',undef,0644);
#chown_files('usr/share/doc/ravada');
chown_files('usr');
chown_files('usr/sbin',0755,0755);
#chown_files('usr/share/ravada/public');
#chown_files('usr/share/ravada/templates');
chown_files('etc');
chmod_ravada_conf();
chown_files('lib');
#chown_files('lib/systemd');
chown_files('var/lib/ravada');
chown_files('usr/share/perl5');
#chown_files('usr/share/man');
create_md5sums();
tar($dist);
#chown_pms();
create_md5sums();
create_deb($dist);
}

copy_identical_releases();
