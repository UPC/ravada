#!/usr/bin/perl

use warnings;
use strict;

use DBIx::Connector;
use Carp qw(confess);
use Data::Dumper;
use File::Copy;
use Fcntl qw(:flock);
use Getopt::Long;
use Hash::Util qw(lock_hash);
use HTTP::Request;
use IPC::Run3;
use LWP::UserAgent;
use Socket qw( inet_aton inet_ntoa );
use Proc::PID::File;
use Sys::Hostname;
use Sys::Virt;
use XML::LibXML;
use YAML;

use lib './lib';

use Ravada;
use Ravada::Auth::SQL;

my $help;
my $FORCE;
my $VM_TYPE = 'qemu';

my ($BASE,$PREPARE, $DAEMON, $DEBUG, $REMOVE, $PROVISION, $ADD_USER, $CREATE );
my $REMOVE_NOW;
my $VERBOSE = $ENV{TERM};
my $FILE_CONFIG = "/etc/ravada.conf";
my $ADD_USER_LDAP;

my $USAGE = "$0 --base=".($BASE or 'BASE')
        ." [--debug] [--prepare] [--daemon] [--file-config=$FILE_CONFIG] "
        ." [name]\n"
        ." --create : creates an empty virtual machine\n"
        ." --prepare : prepares a base system with one of the created nodes\n"
        ." --add-user : adds a new db user\n"
        ." --add-user-ldap : adds a new LDAP user\n"
        ." --provision : provisions a new domain\n"
        ." --remove : removes a domain\n"
        ." --remove-now : removes a domain, doesn't wait a nice shutdown\n"
        ." --daemon : listens for request from the web frontend\n"
    ;

GetOptions (       help => \$help
                 ,force => \$FORCE
                 ,debug => \$DEBUG
                ,create => \$CREATE
                ,daemon => \$DAEMON
                ,remove => \$REMOVE
               ,'base=s'=> \$BASE
               ,prepare => \$PREPARE
               ,verbose => \$VERBOSE
             ,'config=s'=> \$FILE_CONFIG
             ,'add-user'=> \$ADD_USER
        ,'add-user-ldap'=> \$ADD_USER_LDAP
             ,provision => \$PROVISION
           ,'remove-now'=> \$REMOVE_NOW
) or exit;

#####################################################################
#
# check arguments
#
my $CONFIG=YAML::LoadFile($FILE_CONFIG) if -e $FILE_CONFIG;

if ($REMOVE_NOW) {
    $REMOVE = 1;
    $CONFIG->{timeout_shutdown}= 1;
}

if ($REMOVE || $PROVISION || $ADD_USER || $ADD_USER_LDAP || $CREATE) {
    if ( ! @ARGV ) {
        $help=1;
        warn "ERROR: missing username.\n"   if $ADD_USER;
        warn "ERROR: Missing domain names.\n"   if $PROVISION || $REMOVE;
    }
    $|=1;
}
if ($PROVISION && !$BASE ) {
    warn "ERROR: Missing base\n";
    $help =1;
}
if ($ADD_USER && $ADD_USER_LDAP) {
    warn "ERROR: Only one kind of user, please\n";
    $help = 1;
}

if ($help) {
    print $USAGE;
    exit;
}

$Ravada::DEBUG=1    if $DEBUG;
###################################################################

our ($FH_DOWNLOAD, $DOWNLOAD_TOTAL);

my $RAVADA = Ravada->new( config => $FILE_CONFIG );
my $REMOTE_VIEWER;
###################################################################
#

sub init_config {

}

sub init {
    init_config();
}

sub new_uuid {
    my $uuid = shift;
    

    my ($principi, $f1,$f2) = $uuid =~ /(.*)(.)(.)/;

    return $principi.int(rand(10)).int(rand(10));
    
}

sub which {
    # TODO: findbin or whatever
    my $prg = shift;
    my $bin = `which $prg`;
    chomp $bin;
    return $bin;
}

sub sysprep {
    my $name = shift;
    my $virt_sysprep=which('virt-sysprep') or do {
        warn "WARNING: Missing virt-sysprep, the new domain is dirty.\n";
        return;
    };
    my @cmd = ($virt_sysprep
                ,'-d',  $name
                ,'--hostname', $name
                ,'--enable',
                ,'udev-persistent-net,bash-history,logfiles,utmp,script'
    );
    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    print $out if $out;
    print join ( " ",@cmd)."\n".$err    if $err;

}

sub provision {
    my ($base_name, $dom_name) = @_;
    confess "Missing base\n" if !$base_name;
    confess "Missing name\n" if !$dom_name;

    if ($RAVADA->search_domain($dom_name)) {
        warn "WARNING: domain $dom_name already exists\n";
        return display_uri($dom_name)
    }
    my $base = $RAVADA->search_domain($base_name) or die "ERROR: Unknown base $base_name";

    if (!$base->is_base) {
        warn "WARNING: Domain $base_name is not a base, preparing it ...\n";
        $base->prepare_base();
    }

    my $domain = $RAVADA->create_domain(name => $dom_name , id_base => $base->id );
    return view_domain($domain);
    
}

sub prepare_base {
    my $name = shift;
    my $domain = $RAVADA->search_domain($name) or die "Unknown domain $name";
    warn "Preparing $name base\n";
    $domain->prepare_base();
    warn "Done.\n";
}

sub display_uri{
    my $domain = shift;
}

sub start {
    warn "Starting daemon mode\n";
    for (;;) {
        $RAVADA->process_requests();
        sleep 1;
    }
}

sub start_domain {
    my $req = shift;
    my $id = $req->{id} or confess "Missing id in ".Dumper($req);
    my $name = $req->{name};

    my @cmd = ('virsh','start',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    print join(" ",@cmd)."\n"   if $VERBOSE;
    print $out if $VERBOSE;

    warn $err if $VERBOSE && $err;

    set_request_done($id,$err);

}

sub list_domains {

    my @list = sort { $a->name cmp $b->name } $RAVADA->list_domains ;
    return \@list;

}

sub select_base_domain {
    my $domains = shift;

    my $option;
    while (1) {
        print "Choose base domain:\n";
        for my $dom (0 .. $#$domains) {
            my $n = $dom+1;
            $n = " ".$n if length($n)<2;
            print "$n: ".$domains->[$dom]->name
                    ."\n";
        }
        print " X: EXIT\n";
        print "Option: ";
        $option = <STDIN>;
        chomp $option;
        exit if $option =~ /x/i;
        last if $option =~ /^\d+$/ && $option <= $#$domains+1 && $option>0;
        print "ERROR: Wrong option '$option'\n\n";
    }
    return $domains->[$option-1];
}

sub disks_remove {
    my $name = shift;

    my $kvm = $RAVADA->search_vm('kvm');
    if ($kvm) {
        my $dir_img = $kvm->dir_img();
        my $disk = $dir_img."/$name.img";
        if ( -e $disk ) {
            warn "Removing $disk\n";
            unlink $disk or die "I can't remove $disk";
        }
        $kvm->storage_pool->refresh();
    }
}

sub domain_remove {
    my $name = shift;
    my $dom = $RAVADA->search_domain($name);
    if (!$dom) {
        warn "ERROR: I can't find domain $name\n";
    } else {
        $dom->remove();
    }
    disks_remove($name);
}

sub add_user {
    my $login = shift;

    print "password : ";
    my $password = <STDIN>;
    chomp $password;

    Ravada::Auth::SQL::add_user($login, $password);
}

sub add_user_ldap {
    my $login = shift;

    print "password : ";
    my $password = <STDIN>;
    chomp $password;

    Ravada::Auth::LDAP::add_user($login, $password);
}


sub select_iso {
    my $sth = $RAVADA->connector->dbh->prepare("SELECT * FROM iso_images ORDER BY name");
    $sth->execute;
    my @isos;
    while (my $row = $sth->fetchrow_hashref) {
        lock_hash(%$row);
        push @isos,($row);
    }
    $sth->finish;
    my $option;
    while (1) {
        print "Choose base ISO image\n";
        for my $dom (0 .. $#isos) {
            my $n = $dom+1;
            $n = " ".$n if length($n)<2;
            print "$n: ".$isos[$dom]->{name}
                    ."\n";
        }
        print " X: EXIT\n";
        print "Option: ";
        $option = <STDIN>;
        chomp $option;
        exit if $option =~ /x/i;
        last if $option =~ /^\d+$/ && $option <= $#isos+1 && $option>0;
        print "ERROR: Wrong option '$option'\n\n";
    }
    return $isos[$option-1];
}

sub search_iso {
    my $id_iso = shift;
    my $sth = $RAVADA->connector->dbh->prepare("SELECT * FROM iso_images WHERE id = ?");
    $sth->execute($id_iso);
    my $row = $sth->fetchrow_hashref;
    die "Missing iso_image id=$id_iso" if !keys %$row;
    return $row;
}

sub download_file_progress {
    my( $data, $response, $proto ) = @_;

    warn "progress";
    print $FH_DOWNLOAD $data; # write data to file
    $DOWNLOAD_TOTAL += length($data);
    my $size = $response->header('Content-Length');
    print floor(($DOWNLOAD_TOTAL/$size)*100),"% downloaded\n"; # print percent downloaded
}

sub download_file {
    my ($url, $device) = @_;

    $url = "http://localhost/ubuntu-14.04.3-desktop-amd64.iso";
    my $ua= LWP::UserAgent->new( keep_alive => 1);

    warn "downloading $url";

    $DOWNLOAD_TOTAL = 0;
    open $FH_DOWNLOAD,">",$device or die "$! $device";
    my $res = $ua->request(HTTP::Request->new(GET => $url),
        \&download_file_progress);

    if ($res->code != 200 ) {
        die $res->status_line;
        close $FH_DOWNLOAD;
        unlink $device;
    }
    close $FH_DOWNLOAD or die "$! $device";
}

sub iso_name {
    my $iso = shift;
    my ($iso_name) = $iso->{url} =~ m{.*/(.*)};
    my $device = Ravada::Domain::KVM::dir_img()."/$iso_name";

    if (! -e $device || ! -s $device) {
        download_file($iso->{url}, $device);
    }
    return $device;
}

sub create_base {
    my ($req_base) = @_;
    my ($dom_name, $id_iso) = @_;
    if (ref($req_base) =~ /HASH/) {
        $dom_name = $req_base->{name};
        $id_iso = $req_base->{id_iso};
    } else {
        $req_base = undef;
    }

    if ( $RAVADA->search_domain($dom_name) ) {
        die "There is already a domain called '$dom_name'.\n"
            if !$FORCE;
        $RAVADA->remove_domain($dom_name);
    }

    my $iso;
    if ($id_iso) {
        $iso = search_iso($id_iso);
    } else {
        $iso = select_iso();
    }
    my $domain = $RAVADA->create_domain( name => $dom_name, id_iso => $iso->{id});
    warn "$dom_name created, available on ".$domain->display."\n";
    
    return view_domain($domain);
}

sub view_domain {
    my $domain = shift;

    print $domain->display."\n";
    if ( $REMOTE_VIEWER) {
        my @cmd = ($REMOTE_VIEWER,$domain->display);
        my ($in,$out,$err);
        run3(\@cmd,\($in, $out, $err));
    }
}

#################################################################

init();
if ($PREPARE) {
    for (@ARGV) {
        prepare_base($_);
    }
    exit;
} elsif ($REMOVE) {
    for (@ARGV) {
        domain_remove($_);
    }
    exit;
} elsif ($PROVISION) {
    for (@ARGV) {
        provision($BASE, $_);
    }
} elsif ($ADD_USER) {
    for (@ARGV) {
        add_user($_);
    }
}elsif ($ADD_USER_LDAP) {
    for (@ARGV) {
        add_user_ldap($_);
    }
}elsif ($CREATE) {
    create_base(@ARGV);
} else {
    die "Already running\n"
        if Proc::PID::File->running;
    start();
}
