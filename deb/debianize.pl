#!/usr/bin/perl

use warnings;
use strict;

use Cwd qw(getcwd);
use File::Path qw(remove_tree make_path);
use IPC::Run3;
use lib './lib';
use Ravada;
use File::Copy;

my $DIR_DST = getcwd."/../ravada-".Ravada::version();
my $DEBIAN = "DEBIAN";

my %DIR = (
    templates => '/usr/share/ravada'
    ,'etc/ravada.conf' => 'etc'
    ,'etc/xml'  => 'var/lib/ravada'
    ,'docs/' => 'usr/share/docs/ravada'
    ,sql => 'usr/share/doc/ravada'
    ,'lib/' => 'usr/share/perl5'
    ,'blib/man3' => 'usr/share/man'
    ,"debian/" => "./DEBIAN"
    ,'etc/systemd/' => 'lib/systemd/system/'
);

for ( qw(css fonts img js )) {
    $DIR{"public/$_"} = "usr/share/ravada/public";
}

my %FILE = (
    'etc/rvd_front.conf.example' => 'etc/rvd_front.conf'
    ,'bin/rvd_back.pl' => 'usr/sbin/rvd_back'
    ,'rvd_front.pl' => 'usr/sbin/rvd_front'
    ,'CHANGELOG.md'   => 'usr/share/doc/ravada/changelog'
    ,'copyright' => 'usr/share/doc/ravada'
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
        my @cmd = ('rsync','-avL',$src,$dst);
        run3(\@cmd, \$in, \$out, \$err);
        die $err if $err;
        print `chmod go+rx $dst`;
    }
}

sub copy_files {
    for my $src (keys %FILE) {
        my $dst = "$DIR_DST/$FILE{$src}";

        my ($dir) = $dst =~ m{(.*)/.*};
        make_path($dir) if !-d $dir;

        mkdir $dst if $dst =~ m{.*/$} && ! -e $dst;
        copy($src,$dst) or die "$! $src -> $dst";
    }
}

sub remove_not_needed {
    for my $file (@REMOVE) {
        $file = "$DIR_DST/$file";
        unlink $file or die "$! $file";
    }
    for my $dir ('usr/share/doc/ravada/sql/sqlite') {
        my $path = "$DIR_DST/$dir";
        die "Missing $path" if ! -e $path;
        remove_tree($path);
    }
}

sub create_md5sums {
    my @files;
    chdir $DIR_DST or die "I can't chdir to $DIR_DST";

    unlink "$DEBIAN/md5sums";

    open my $find, ,'-|', 'find . -type f -printf \'%P\n\'' or die $!;
    while (<$find>) {
        chomp;
        next if /^debian/i;
        print `md5sum $_ >> $DEBIAN/md5sums`
    }
    close $find;
    chdir "..";
    chmod 0644,"$DIR_DST/$DEBIAN/md5sums" or die "$! $DIR_DST/$DEBIAN/md5sums";
}

sub create_deb {
    my $deb = "ravada_${Ravada::VERSION}_all.deb";
    my @cmd = ('dpkg','-b',"$DIR_DST/",$deb);
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
        warn "Missing $path"                    if ! -e $path;
        chmod 0644 , $path or die "$! $path"    if -e $path;
    }

    for(qw(conffiles)) {
        my $path  = "$DIR_DST/$DEBIAN/$_";
        chmod 0644 , $path or die "$! $path"    if -e $path;
    }
}

sub chmod_ravada_conf {
    chmod 0644,"$DIR_DST/etc/ravada.conf" or die $!;
}

sub tar {
    my @cmd = ('tar','czvf',"ravada_".Ravada::version.".orig.tar.gz"
       ,"ravada-".Ravada::version()
    );
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
}

sub make_pl {
    my @cmd = ('perl','Makefile.PL');
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    @cmd = ('make');
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
}

#########################################################################

clean();
make_pl();
copy_dirs();
copy_files();
remove_not_needed();
remove_use_lib();
change_mod();
gzip_docs();
gzip_man();
chown_files($DEBIAN,0755);
chown_files('etc');
chown_files('lib');
chown_files('var/lib/ravada');
chown_files('DEBIAN',0755);
#chown_files('usr/share/doc/ravada');
chown_files('usr/share/ravada/public');
chown_files('usr/share/ravada/templates');
chown_files('etc');
chown_files('lib');
#chown_files('lib/systemd');
chown_files('var/lib/ravada');
chown_files('usr/share/perl5');
#chown_files('usr/share/man');
create_md5sums();
tar();
#chown_pms();
create_md5sums();
create_deb();
