#!/usr/bin/perl

use warnings;
use strict;

use DBIx::Connector;
use File::Copy qw(copy);
use IPC::Run3 qw(run3);

use feature qw(signatures);
no warnings "experimental::signatures";

use YAML;

my $HOME = "/var/tmp";
our $FILE_CONFIG = "/etc/ravada.conf";
my $URL = "http://infoteleco.upc.edu/img/debian";
my $RELEASE = get_last_release();

my $DOMAIN_NAME = "tst_upgrade_01";
my $USER_NAME = "tst_upgrade_01";

my $CONFIG = {};

my $CONNECTOR;
my %SKIP_TABLE = map { $_ => 1 }
qw(requests messages);

$ENV{LANG}='C';

die "Error: this must be run as root\n" if $>;

my $COUNT = 0;
my $DIR_IMG = "/var/lib/libvirt/images";

sub _connect_dbh {
    $CONFIG = YAML::LoadFile($FILE_CONFIG) if -e $FILE_CONFIG;
    if ( !$CONFIG || !keys %$CONFIG ) {
        warn "Empty or missing $FILE_CONFIG, trying defaults to "
        ."connect to db\n";
    }

    my $driver= ($CONFIG->{db}->{driver} or 'mysql');;
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_pass = ($CONFIG->{db}->{password} or undef);
    my $db = ( $CONFIG->{db}->{db} or 'ravada' );
    my $host = $CONFIG->{db}->{host};

    my $data_source = "DBI:$driver:$db";
    $data_source = "DBI:$driver:database=$db;host=$host"
        if $host && $host ne 'localhost';

    my $con;
    for my $try ( 1 .. 10 ) {
        eval { $con = DBIx::Connector->new($data_source
                        ,$db_user,$db_pass,{RaiseError => 0
                        , PrintError=> 1 });
            $con->dbh();
        };
        return $con if $con && !$@;
        sleep 1;
        warn "Try $try $@\n";
    }
    die ($@ or "Can't connect to $driver $db at $host");
}

sub list_tables {
    my $sth = $CONNECTOR->dbh->prepare("show tables");
    $sth->execute();

    my @tables = qw(booking_entry_ldap_groups booking_entry_users booking_entry_bases booking_entries group_access file_base_images volumes domain_access base_xml domain_instances domains_kvm domains_void domains_network);
    push @tables,(qw(host_devices_domain_locked
        host_devices_domain
        host_device_templates
        host_devices
        ));
    my %done = map { $_ => 1 } @tables;
    my %all;
    while (my ($table) = $sth->fetchrow ) {
        $all{$table}++;
        next if $done{$table};
        push @tables,($table);
    }
    my @tables2;
    for my $table (@tables) {
        push @tables2,($table) if $all{$table};
    }
    return @tables2;
}

sub backup {
    my $dir_backup = $HOME."/backup.".time;
    mkdir $dir_backup if !-e $dir_backup;
    copy($FILE_CONFIG,$dir_backup);
    my @cmd = ("mysqldump","--quote-names","--skip-lock-tables","--skip-extended-insert"
        ,"--compact","ravada");
    for my $table (list_tables()) {
        next if $SKIP_TABLE{$table};
        my ($in, $out, $err);
        my @cmd2 = ( @cmd,$table);
        run3(\@cmd2,\$in, \$out, \$err);
        if ($err =~ /Couldn't find table/) {
            warn $err;
            next;
        }
        die $err if $err;
        open my $file, ">","$dir_backup/$table.sql" or die "$! $dir_backup/$table.sql";
        print $file $out;
        close $file;
    }
}

sub remove_tables {
    my $dbh = $CONNECTOR->dbh;
    for my $table (list_tables()) {
        my $sth = $dbh->prepare("drop table $table");
        eval {
           $sth->execute();
        };
        warn "Error dropping table $table : ".$dbh->errstr
        if $dbh->err;

        my $errstr = $CONNECTOR->dbh->errstr;
        die $CONNECTOR->dbh->err." ".$errstr
        if $errstr && $CONNECTOR->dbh->err != 1051;

    }
}

sub wget {
    my $url = shift;

    my ($file) = $url =~ m{.*/(.*)};
    $file = "index.html" if !length($file);
    if (-e $file) {
        warn "File $file already downloaded\n";
        return;
    }
    my @cmd = ("wget",$url);
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    warn $out if $out;
    die "Error $?: $url $err" if $err && $?;
}

sub install_deb {
    my $deb = shift;
    my @cmd = ("sudo","dpkg","-i","--force-confold",$deb);
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    warn $out if $out;
    my $err2 = '';
    for my $line ( split /\n/, $err ) {
        next if $line =~ /dpkg:.*desact/;
        next if $line =~ /Fitxer de configu/i;
        next if $line =~ /==>/;
        next if $line =~ /^\s*$/;
        next if $line =~ /^text/i;
        next if $line =~ /^INFO: creating constraint/;
        $err2 .= "$line\n";
    }
    die "Error en dpkg -i $deb $err2" if $err2 && $err2 !~ /depend/;

    run3(["sudo","apt","-y","-f","install"], \$in, \$out, \$err);
    #    warn $out if $out;
    die "Error en $deb $err" if $err && $err !~ /WARNING/i;

    my ($n) = $deb =~ m{ravada_(\d+\.\d+\.\d+)};
    run3(["sudo","/usr/sbin/rvd_back","--add-user","tst.".time.".$n"], \$in, \$out, \$err);
    warn $out if $out;
    $err2 = '';
    for my $line ( split /\n/, $err ) {
        next if $line =~ /^INFO/;
        next if $line =~ /'\w+' =>/;
        next if $line =~ /\s+}/;
        next if $line =~ /(BLOB|CHAR|TEXT).*->/;
        next if $line =~ /\d+ to./;
        next if $line =~ /char\(\d+/i;
        next if $line =~ /^int DEFAULT/;
        next if $line =~ /^MEDIUMBLOB/;
        next if $line =~ / in \w+/;
        next if $line =~ /^TEXT/i;
        next if $line !~ /[a-z]/;
        next if $line =~ /No timezone found/i;
        next if $line =~ /INF.*UEFI/i;
        next if $line =~ /No storage pool.*creating/i;
        $err2 .= "$line\n";
    }
    die "Error en apt $deb $err2" if $err2;
}

sub remove_ravada {
    my ($in, $out, $err);
    run3(["sudo","apt","-y","purge","ravada"], \$in, \$out, \$err);
    #    warn $out if $out;
    die "Error en apt purge ravada $err" if $err && $err !~ /WARNING/i;

    run3(["sudo","apt","--purge","-y","autoremove"], \$in, \$out, \$err);
    # warn $out if $out;
    die "Error en apt --purge autoremove $err" if $err && $err !~ /WARNING/i;
}

sub upgrade_latest {
    my $host = get_os();;
    my $deb = "ravada_${RELEASE}_${host}_all.deb";
    warn $deb;
    wget("$URL/$deb");
    install_deb($deb);
}

sub get_os {
    my $hostnamectl = `hostnamectl`;
    my ($name,$version) = $hostnamectl =~ /Operating System: (\w+) .*?([0-9\.]+)/ms;

    if ($name =~ /ubuntu/i) {
        my ($n) = $version =~ m{^(\d+)\.};
        die "I can't find major version in '$version'" if !defined $n;
	    return "ubuntu-20.04" if $n > 20;
    }
    $version =~ s{(\d+\.\d+)\..*}{$1};
    return lc($name)."-$version";
}

sub upgrades {
    my $dir = "$HOME/releases";
    if (! -e $dir) {
        mkdir $dir or die "$! $dir";
    }
    my $os = get_os();
    open my $in,"<","$dir/index.html" or die $!;
    my $found_first_release = 0;
    warn "checking all upgrades for $os\n";
    while (my $line = <$in>) {
        my ($release) = $line =~ /a href="(ravada_[0-9\.\-]+_$os.*?)"/;
        if (!$release && $os eq 'debian-11') {
            ($release) = $line =~ /a href="(ravada_[0-9\.\-]+_debian-1.*?)"/;
        }
        next if !$release;
        if (!$found_first_release) {
            $found_first_release = $release =~ m{^ravada_0};
        }
        next if !$found_first_release;
        get_install_and_upgrade($release, $os);
    }
    close $in;
    die "Error: no first release found\n" if !$found_first_release;
}

sub rvd {
    my @cmd = ("/usr/bin/perl","-MRavada","-e",'my $rvd = Ravada->new();print "Installing Ravada ".$rvd->version()."\n";$rvd->_install()');
    my ($in, $out,$err);
    run3(\@cmd,\$in, \$out, \$err);
    print $out if $out;

    @cmd = ("systemctl","restart","rvd_back");
    run3(\@cmd,\$in, \$out, \$err);
    print $out if $out;
    print $err if $err;
}

sub _list_requests {
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM requests "
        ."WHERE status <> 'done'");
    $sth->execute;
    my @req;
    while (my ($id) = $sth->fetchrow) {
        push @req,($id);
    }
    return @req;
}

sub _wait_request($command) {

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM requests where command=? "
        ." AND (status <> 'done' OR id=?)"
    );
    my $id;
    for (;;) {
        $sth->execute($command, $id);
        my $row = $sth->fetchrow_hashref;
        return if !keys %$row;

        die "Error $row->{command} $row->{error}"
        if $row->{error};

        return if $row->{status} eq 'done';
        warn $row->{id}." ".$row->{command}." ".$row->{status}."\n";
        $id = $row->{id} if $row->{id};
        sleep 1;
    }
}

sub _search_id_iso($name) {

    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM iso_images "
        ." WHERE name like ?"
    );
    $sth->execute("$name%");
    my ($id) = $sth->fetchrow;
    die "There is no iso called $name%" if !$id;
    return $id;
}

sub virsh_remove_domain($name, $storage=0){
    my @cmd = ("virsh","destroy",$name);
    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);
    @cmd = ("virsh","undefine",$name);

    push @cmd,("--remove-all-storage") if $storage;

    run3(\@cmd,\$in,\$out,\$err);

    warn $err if $err;

}

sub new_domain_name {
    return "tst_upgrade_".$COUNT++;
}

sub create_domain($name) {

    virsh_remove_domain($name);

    my @cmd = ("/usr/bin/perl","-MRavada","-MRavada::Request"
        ,"-e",'my $rvd=Ravada->new();
    my $req = Ravada::Request->create_domain(
        name => '.$name
        .',id_owner =>'.user_id('daemon')
        .',id_iso => '._search_id_iso('%alpine%64%')
        .',disk => 2*1024*1024'
        .',vm => "KVM"
    ); ');

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    warn $err if $err;

    _wait_request("create");
}

sub prepare_base($name) {

    my @cmd = ("/usr/bin/perl","-MRavada","-MRavada::Request"
        ,"-e",'my $rvd=Ravada->new();
    my $req = Ravada::Request->prepare_base(
        id_domain => '.domain_id($name)
        .',uid =>'.user_id('daemon')
        .'); ');

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    warn $err if $err;

    _wait_request("prepare_base");
}

sub clone($name) {

    my $clone_name = new_domain_name();

    remove_domain($clone_name);
    virsh_remove_domain($clone_name);

    my @cmd = ("/usr/bin/perl","-MRavada","-MRavada::Request"
        ,"-e",'my $rvd=Ravada->new();
    my $req = Ravada::Request->clone(
        id_domain => '.domain_id($name)
        .',uid =>'.user_id('daemon')
        .',name => '.$clone_name
        .'); ');

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    warn $err if $err;

    _wait_request("prepare_base");

    return $clone_name;
}


sub domain_id($name) {
    for ( 1 .. 2 ) {
        my $sth = $CONNECTOR->dbh->prepare(
            "SELECT id FROM domains WHERE name=?"
        );
        $sth->execute($name);
        my ($id ) =$sth->fetchrow;
        return $id if $id;
        warn "No id for domain $name";
        sleep 1;
    }
}

sub user_id($name) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM users WHERE name=?"
    );
    $sth->execute($name);
    my ($id ) =$sth->fetchrow;
    return $id;
}


sub start_domain($name) {

    my @cmd = ("/usr/bin/perl","-MRavada","-MRavada::Request"
        ,"-e",'my $rvd=Ravada->new();
    my $req = Ravada::Request->start_domain(
        uid => '.user_id("daemon")
        .',id_domain => '.domain_id($name)
        .',remote_ip => "127.0.0.1"
    ); ');

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    warn $err if $err;

    _wait_request("create");

}

sub remove_domain($name) {
    my @cmd = ("/usr/bin/perl","-MRavada","-MRavada::Request"
        ,"-e",'my $rvd=Ravada->new();
    my $req = Ravada::Request->remove_domain(
        uid => '.user_id("daemon")
        .',name => '.$name
    .'); ');

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    warn $err if $err;

    _wait_request("remove_domain");
}

sub create_user($rvd) {
    my $name = $USER_NAME;
    my $pass = "$$.$$";
    my $login;
    eval { $login = Ravada::Auth::SQL->new(name => $name ) };
    return $login if $login;

    Ravada::Auth::SQL::add_user(name => $name, password => $pass, is_admin => 0 );

    my $user;
    eval {
        $user = Ravada::Auth::SQL->new(name => $name);
    };
    die $@ if !$user;
    return $user;
}

sub test_user($name) {
    my $user = Ravada::Auth::SQL->new(name => $name);
    die "Error. I can't find user '$name'" if !$user;
}

sub get_install_and_upgrade($deb, $os) {

    warn $deb."\n";
    wget("$URL/$deb");
    remove_tables();
    remove_ravada();
    install_deb($deb);

    rvd();
    my $domain_name = new_domain_name();
    create_domain($domain_name);

    my $clone_name = $domain_name;

    my ($major) = $deb =~ /ravada_(0.\d+)/;
    if ($os =~ /ubuntu-18/i || $os =~ /debian-10/i || $major > 0.7) {
        prepare_base($domain_name);
        $clone_name = clone($domain_name);
    }
    upgrade_latest();

    start_domain($clone_name);
    remove_domain($clone_name);
    remove_domain($domain_name);
}

sub test_domain() {
    warn "test domain";

    rvd();
    my $domain_name = new_domain_name();

    remove_domain($domain_name);
    create_domain($domain_name);
    start_domain($domain_name);

    remove_domain($domain_name);

}

sub get_last_release {
    my $dir = "$HOME/releases";
    mkdir $dir if ! -e $dir;
    chdir $dir;

    die "Error: no url" if !$URL;
    if (! -e "$dir/index.html") {
        wget("$URL/index.html");
    }

    open my $in,"<","$dir/index.html" or die "$! $dir/index.html";
    while (<$in>) {
        my ($release) = /a href="ravada_([0-9\.\-]+)/;
        return $release if $release;
    }
    close $in;
    die "Error: I can't find a href=\"ravada_ in $URL";
}

sub install_virsh {
    my @cmd = ("apt-get","install","libvirt-clients","libvirt-daemon");
    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);
    die $err if $err;
}

sub clean_old {
    install_virsh();
    my @cmd = ("virsh","list","--all");
    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    my @cmd_remove = ("virsh","undefine");

    for my $line (split/\n/,$out) {
        next if $line !~ /tst_upgrade/i;
        my ($name) = $line =~ /.* (tst_upgrade.*?) /;
        print "removing $name\n";
        virsh_remove_domain($name,1);
    }

    opendir my $dir,$DIR_IMG or return;
    chdir $DIR_IMG;
    while (my $file = readdir $dir ) {
        next if $file !~ /^tst_upgrade/;
        print "$file\n";
        unlink $file or die "$! $file\n";
    }
}

################################################################

$CONNECTOR = _connect_dbh();

#test_domain();

clean_old();

get_os();

backup();

upgrades();
