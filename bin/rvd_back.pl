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
use IPC::Run3;
use Socket qw( inet_aton inet_ntoa );
use Proc::PID::File;
use Sys::Hostname;
use Sys::Virt;
use XML::LibXML;
use YAML;

my $CONFIG = {
    img => {
        dir => '/var/lib/libvirt/images',
    },
    dir_tmp => "/var/tmp/provision",
    db => { user => 'root', password => '' },
    timeout_shutdown => 20,
};

my $help;
my $FORCE;
my $SECONDS_RECENT = 300;
my $DIR_TMP = $CONFIG->{dir_tmp};
my $VM_TYPE = 'qemu';

my $IP;
my ($BASE,$PREPARE, $DAEMON, $DEBUG, $REMOVE, $PROVISION );
my $REMOVE_NOW;
my $VERBOSE = $ENV{TERM};
my $FILE_CONFIG = "/etc/ravada.conf";

my $USAGE = "$0 --base=".($BASE or 'BASE')
        ." [--prepare] [--daemon] [--file-config=$FILE_CONFIG] "
        ." [--dir-tmp=$DIR_TMP] [name]\n"
        ." --prepare : prepares a base system with one of the created nodes\n"
        ." --provision : provisions a new domain\n"
        ." --remove : removes a domain\n"
        ." --remove-now : removes a domain, doesn't wait a nice shutdown\n"
        ." --daemon : listens for request from the web frontend\n"
    ;

undef $FILE_CONFIG;

GetOptions (       help => \$help
                 ,force => \$FORCE
                ,daemon => \$DAEMON
                ,remove => \$REMOVE
               ,'base=s'=> \$BASE
               ,prepare => \$PREPARE
               ,verbose => \$VERBOSE
             ,'config=s'=> \$FILE_CONFIG
             ,provision => \$PROVISION
           ,'remove-now'=> \$REMOVE_NOW
            ,'dir-tmp=s'=> \$DIR_TMP
) or exit;

#####################################################################
#
# check arguments
#
$CONFIG=YAML::LoadFile($FILE_CONFIG) if $FILE_CONFIG;

if ($REMOVE_NOW) {
    $REMOVE = 1;
    $CONFIG->{timeout_shutdown}= 1;
}

if ($REMOVE || $PROVISION) {
    if ( ! @ARGV ) {
        $help=1;
        warn "ERROR: Missing domain names.\n";
    }
    $|=1;
}
if ($PROVISION && !$BASE ) {
    warn "ERROR: Missing base\n";
    $help =1;
}

if ($help) {
    print $USAGE;
    exit;
}


###################################################################

my $VM = Sys::Virt->new( address => "$VM_TYPE:///system") 
    or die "I can't connect to $VM_TYPE local\n";

my $PARSER = XML::LibXML->new();
our $CON;
###################################################################

sub search_file_base {
    my $base = shift;

    my $sth = $CON->dbh->prepare("SELECT image FROM bases WHERE name=?");
    $sth->execute($base);
    my ($img) = $sth->fetchrow;

    if (!$img) {
        die "Base $base not found, maybe you should --prepare first\n";
    }
    return $img;
}

sub create_disk_qcow2 {
    my ($base, $name) = @_;

    my $dir_img = $CONFIG->{img}->{dir};

    my $file_base = search_file_base($base);
    my $file_out = "$dir_img/$base-$name.qcow2";

    if (!$FORCE && -e $file_out ) {
        warn "WARNING: output file $file_out already existed [skipping]\n";
        return $file_out;
    }

    if (! -e $file_base ) {
        die "CRITICAL: missing device base $file_base\n";
    }

    my @cmd = ('qemu-img','create'
                ,'-f','qcow2'
                ,"-b", $file_base
                ,$file_out
    );
    print join(" ",@cmd)."\n";

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);
    print $out  if $out;
    warn $err   if $err;

    if (! -e $file_out) {
        warn "ERROR: Output file $file_out not created at ".join(" ",@cmd)."\n";
        exit;
    }
    
    print "  qcow created\t\$?=$?\n";

    return $file_out;
}

sub create_disk {
    return create_disk_qcow2(@_);
}

sub recent_file {
    my $file = shift;
    my @stat = stat($file) or return;
    my $mtime = $stat[9];

    return time - $mtime <= $SECONDS_RECENT;
}

sub get_base_xml {
    my $base = shift;

    my $base_xml = "$DIR_TMP/$base.xml";

    if ( -e $base_xml ) {
        return $base_xml if recent_file($base_xml);
    }

    my @cmd = ('virsh','dumpxml',$base);
    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);

    open my $f_out,'>',$base_xml or die "$! $base_xml";
    print $f_out $out;
    close $f_out or die "$! $base_xml";

    return $base_xml;
}

sub init {
    if ( ! -d $DIR_TMP ) {
        mkdir $DIR_TMP or die "$! $DIR_TMP";
    }
    init_db();
    init_ip();
}

sub init_ip {
    my $name = hostname() or die "CRITICAL: I can't find the hostname.\n";
    $IP = inet_ntoa(inet_aton($name)) 
        or die "CRITICAL: I can't find IP of $name in the DNS.\n";

    if ($IP eq '127.0.0.1') {
        #TODO Net:DNS
        $IP= `host $name`;
        chomp $IP;
        $IP =~ s/.*?address (\d+)/$1/;
    }
    die "I can't find IP with hostname $name ( $IP )\n"
        if !$IP || $IP eq '127.0.0.1';
}

sub init_db {
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_pass = ($CONFIG->{db}->{pass} or undef);
    $CON = DBIx::Connector->new("DBI:mysql:ravada"
                        ,$db_user,$db_pass,{RaiseError => 1
                        , PrintError=> 0 }) or die "I can't connect";

}

sub new_uuid {
    my $uuid = shift;
    

    my ($principi, $f1,$f2) = $uuid =~ /(.*)(.)(.)/;

    return $principi.int(rand(10)).int(rand(10));
    
}

sub modify_domain {

    my ($name, $base_xml, $device) = @_;
    warn "modify domain $base_xml"  if $DEBUG;
    my $doc = $PARSER->parse_file($base_xml) or die "ERROR: $! $base_xml\n";

#    modify_network($data);
#    $data->{name} = $name;
    my ($node_name) = $doc->findnodes('/domain/name/text()');
    $node_name->setData($name);

    modify_mac($doc);
    modify_uuid($doc);
    modify_spice_port($doc);
    modify_disk($doc, $device);
    modify_video($doc);

#    open my $out ,">","$name.xml" or die $!;
#    print $out $doc->toString();
#    close $out;
    return $doc;
}

sub modify_video {
    my $doc = shift;

    my ( $video , $video2 ) = $doc->findnodes('/domain/devices/video');
    $video->setAttribute(type => 'qxl');
    $video->setAttribute( ram => 65536 );
    $video->setAttribute( vram => 65536 );
    $video->setAttribute( vgamem => 16384 );
    $video->setAttribute( heads => 1 );
    
    warn "WARNING: more than one video card found\n".
        $video->toString().$video2->toString()  if$video2;
}

sub modify_disk {
    my $doc = shift;
    my $device = shift          or confess "Missing device";

#  <source file="/var/export/vmimgs/ubuntu-mate.img" dev="/var/export/vmimgs/clone01.qcow2"/>

    my $cont = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        die "ERROR: base disks only can have one device" if $cont++>1;
        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'driver') {
                $child->setAttribute(type => 'qcow2');
            } elsif ($child->nodeName eq 'source') {
                $child->setAttribute(file => $device);
            }
        }
    }

}

sub modify_spice_port {
    my $doc = shift;

    my ($graph) = $doc->findnodes('/domain/devices/graphics') 
        or die "ERROR: I can't find graphic";
    $graph->setAttribute(type => 'spice');
    $graph->setAttribute(autoport => 'yes');
    $graph->setAttribute(listen=> $IP );

    my ($listen) = $doc->findnodes('/domain/devices/graphics/listen');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"listen");
    }

    $listen->setAttribute(type => 'address');
    $listen->setAttribute(address => $IP);

}

sub modify_uuid {
    my $doc = shift;
    my ($uuid) = $doc->findnodes('/domain/uuid/text()');

    warn "modify uuid";

    random:while (1) {
        my $new_uuid = new_uuid($uuid);
        next if $new_uuid eq $uuid;
        for my $dom ($VM->list_all_domains) {
            next random if $dom->get_uuid_string eq $new_uuid;
        }
        $uuid->setData($new_uuid);
        last;
    }
}

sub unique_mac {
    my $mac = shift;

    $mac = lc($mac);

    warn "checking $mac is unique"  if $DEBUG;

    for my $dom ($VM->list_all_domains) {
        my $base_xml = get_base_xml($dom->get_name);
        my $doc = $PARSER->parse_file($base_xml) or die "ERROR: $! $base_xml\n";

        for my $nic ( $doc->findnodes('/domain/devices/interface/mac')) {
            my $nic_mac = $nic->getAttribute('address');
            return 0 if $mac eq lc($nic_mac);
        }
    }
    return 1;
}

sub modify_mac {
    my $doc = shift;

    warn "Modify mac";

    my ($if_mac) = $doc->findnodes('/domain/devices/interface/mac')
        or exit;
    my $mac = $if_mac->getAttribute('address');

    my @macparts = split/:/,$mac;

    my $new_mac;
    for my $last ( 0 .. 99 ) {
        $last = "0$last" if length($last)<2;
        $macparts[-1] = $last;
        $new_mac = join(":",@macparts);
        last if unique_mac($new_mac);
        $new_mac = undef;
    }
    die "I can't find a new unique mac" if !$new_mac;
    $if_mac->setAttribute(address => $new_mac);
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
    my ($base, $dom_name) = @_;
    confess "Missing base\n" if !$base;
    confess "Missing name\n" if !$dom_name;

    if (domain_exists($dom_name)) {
        warn "WARNING: domain $dom_name already exists\n";
        return display_uri($dom_name)
    }

    my $base_xml = get_base_xml($base);
    my $disk_new = create_disk($base, $dom_name);
    my $domain_data = modify_domain($dom_name , $base_xml, $disk_new);
    my $dom = $VM->define_domain($domain_data->toString());
    
    sysprep($dom_name);
    $dom->create();

    return display_uri($dom_name);
    
}

sub display_uri{
    my $name = shift;
    my @cmd = ('virsh','domdisplay',$name);

    my ($in, $out, $err);


    for ( 1 .. 10 ) {
        run3(\@cmd, \($in,$out,$err));
        chomp $out;
        my ($port) = $out =~ m{^spice:.*?(\d+)$};
        return $out if $port;
        warn "No port in ".join(" ",@cmd);
    }
    die join(" ",@cmd)."\n$err" if $err;

    die "I can't find port in $out for $name";#   if !$port;

}

sub start {
    warn "Starting daemon mode\n";
    for (;;) {
        check_req_new_domain();
        check_req_action();
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

sub set_request_done {

    my ($id, $err) = @_;

    $err = '' if !$err;
    my $sth = $CON->dbh->prepare("UPDATE domains_req SET error=?,done='y' "
                        ." WHERE id=?");
    $sth->execute($err,$id);

}

sub check_req_action {
    my $sth = $CON->dbh->prepare(
        "SELECT r.* , name "
        ." FROM domains_req r, domains d"
        ." WHERE r.id_domain = d.id "
        ."      AND ( isnull(r.done) OR r.done <> 'y' )"
    );
    $sth->execute;

    my ($req) = $sth->fetchrow_hashref;
    return if !exists $req->{name};

    my $name = $req->{name};

    lock_hash(%$req);

    warn Dumper($req);
    if ($req->{'start'}) {
        if (!domain_exists($name)) {
            eval {
                my $base_name = search_domain_base($req->{id_domain})
                    or die "Missing id_domain=$req->{id_domain}";
                provision($base_name,$name);
            };
            warn $@ if $@;
            return set_request_done($req->{id}, ($@ or ''));
        }
        start_domain($req);
    } else {
        warn "I don't know how to deal with request ".Dumper($req);
    }
}

sub search_domain_base {
    my $id_domain = shift;
    my $sth = $CON->dbh->prepare(
        "SELECT b.name FROM bases b , domains d "
        ." WHERE d.id=?"
        ."  AND d.id_base = b.id"
    );
    $sth->execute($id_domain);
    return $sth->fetchrow;
}

sub check_req_new_domain {
        my $sth = $CON->dbh->prepare(
            "SELECT d.id,b.name, d.name "
            ." FROM bases b, domains d "
            ." WHERE b.id = d.id_base "
            ."    AND isnull(d.error) AND created='n' "
        );
        $sth->execute;
        while (my ($id, $base, $name) = $sth->fetchrow) {
            warn "$base / $name\n";
            my $uri;
            eval { $uri=provision($base,$name) };
            if ($@) {
                domain_error($id, $@);
            } else {
                my $sth2 = $CON->dbh->prepare(
                    "UPDATE domains set created='y', uri =? "
                    ." WHERE id=?"
                );
                $sth2->execute($uri , $id);
                $sth2->finish;
                warn "Created domain $name";
            }
        }
}

sub domain_error {
    my ($id, $error) = @_;
    my $sth_err = $CON->dbh->prepare(
                    "UPDATE domains set error=? "
                    ." WHERE id=?"
                );
    $sth_err->execute($error, $id);
    $sth_err->finish;

}

sub prepare_base {
    my $domains = list_domains();

    die "CRITICAL: No domains available, build some first.\n"
        if !scalar(@$domains);

    my $base_dom = select_base_domain($domains);

    print "building base from ".$base_dom->get_name."\n";

    check_used_base($base_dom);

    my $file_qcow  = create_qcow_base($base_dom);

    my $sth = $CON->dbh->prepare("INSERT INTO bases (name,image) "
        ." VALUES(?,?) ");
    $sth->execute($base_dom->get_name, $file_qcow);
    $sth->finish;
    
    print "Base for ".$base_dom->get_name." prepared.\n";
}

sub search_drive {
    my $domain = shift;

    my $base_xml = get_base_xml($domain->get_name);
    my $doc = $PARSER->parse_file($base_xml) or die "ERROR: $! $base_xml\n";

    my $cont = 0;
    my $img;
    my $list_disks = '';

    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        $list_disks .= $disk->toString();

        die "ERROR: base disks only can have one device\n" 
                .$list_disks
            if $cont++>1;

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
#                die $child->toString();
                $img = $child->getAttribute('file');
                $cont++;
            }
        }
    }
    return $img;
}


sub create_qcow_base {
    my $base_dom= shift;
    
    my $base_name = $base_dom->get_name;
    my $base_img = search_drive($base_dom);
    my $qcow_img = $CONFIG->{img}->{dir}."/$base_name.ro.qcow2";
    my @cmd = ('qemu-img','convert',
                '-O','qcow2', $base_img
                ,$qcow_img
    );

    print "...\n";
    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);
    print $out  if $out;
    warn $err   if $err;

    if (! -e $qcow_img) {
        warn "ERROR: Output file $qcow_img not created at ".join(" ",@cmd)."\n";
        exit;
    }

    chmod 0555,$qcow_img;
    return $qcow_img;
}

sub check_used_base {
    my $dom= shift;

    my $sth = $CON->dbh->prepare("SELECT id FROM bases WHERE name=?");
    $sth->execute($dom->get_name);
    my ($id) = $sth->fetchrow;
    $sth->finish;

    return if !defined $id;

    print "Base ".$dom->get_name." already in use, overwriting.\n";
    $sth = $CON->dbh->prepare("DELETE FROM bases WHERE id=?");
    $sth->execute($id);
    $sth->finish;
}

sub list_domains {
    my @domains_sorted = sort { $a->get_name cmp $b->get_name } 
        $VM->list_all_domains();

    return \@domains_sorted
}

sub domain_exists {
    my $name = shift;
    my $domains = list_domains();
    for (@$domains) {
        return 1 if $_->get_name() eq $name;
    }
    return 0;
}

sub select_base_domain {
    my $domains = shift;

    my $option;
    while (1) {
        print "Choose base domain:\n";
        for my $dom (0 .. $#$domains) {
            my $n = $dom+1;
            $n = " ".$n if length($n)<2;
            print "$n: ".$domains->[$dom]->get_name
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

sub domain_open {
    my $name = shift;
    for ($VM->list_all_domains) {
        return $_ if $_->get_name eq $name;
    }
    return;
}

sub dom_wait_down {
    my $dom = shift;
    my $seconds = (shift or $CONFIG->{timeout_shutdown});
    for my $sec ( 0 .. $seconds) {
        return if !$dom->is_active;
        print "Waiting for ".$dom->get_name." to shutdown." if !$sec;
        print ".";
        sleep 1;
    }
    print "\n";
}

sub domain_remove_disks {
    my $dom = shift;
    my $doc = $PARSER->load_xml(string => $dom->get_xml_description);

    my $removed = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        next if $disk->getAttribute('device') ne 'disk';

        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                my $file = $child->getAttribute('file');
                next if !-e $file;
                unlink $file or die "$! $file";
                $removed++;
            }
        }
    }

    warn "WARNING: No disk files removed for ".$dom->get_name."\n"
        if !$removed;

}

sub dom_is_base {
    my $dom_name = shift;
    my $sth = $CON->dbh->prepare(
        "SELECT id FROM bases WHERE name=?"
    );
    $sth->execute($dom_name);
    my @row = $sth->fetchrow;
    return ($row[0] or undef);
}

sub domain_remove {
    my $dom_name= shift;
    if (dom_is_base($dom_name)) {
        warn "ERROR: node $dom_name is base, it can't be removed\n"
            ." TODO: check if there are children and do force.\n";
        return;
    }
    my $dom = domain_open($dom_name) or die "I can't find domain $dom_name";
    $dom->shutdown  if $dom->is_active();
    dom_wait_down($dom);
    $dom->destroy   if $dom->is_active();

    domain_remove_disks($dom);

    $dom->undefine();
    warn "Domain $dom_name removed\n";

#    shutdown_node($node);
#    undefine_node($node);
#    remove_disk($node);
}

#################################################################

init();
if ($PREPARE) {
    prepare_base();
    exit;
} elsif ($REMOVE) {
    for (@ARGV) {
        domain_remove($_);
    }
    exit;
} elsif ($PROVISION) {
    for (@ARGV) {
        print provision($BASE, $_)."\n";
    }
} else {
    die "Already running\n"
        if Proc::PID::File->running;
    start();
}
