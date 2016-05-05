package Ravada::VM::KVM;

use Carp qw(croak);
use Data::Dumper;
use Encode;
use Encode::Locale;
use Fcntl qw(:flock O_WRONLY O_EXCL O_CREAT);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use LWP::UserAgent;
use Moose;
use Socket qw( inet_aton inet_ntoa );
use Sys::Hostname;
use Sys::Virt;
use URI;
use XML::LibXML;

with 'Ravada::VM';

##########################################################################

has vm => (
    isa => 'Sys::Virt'
    ,is => 'ro'
    ,builder => 'connect'
    ,lazy => 1
);

has storage_pool => (
    isa => 'Sys::Virt::StoragePool'
    ,is => 'ro'
    ,builder => '_load_storage_pool'
    ,lazy => 1
);

#########################################################################3
#

our $DIR_XML = "etc/xml";

our $DEFAULT_DIR_IMG;
our $XML = XML::LibXML->new();
our $IP = _init_ip();

#-----------
#
# global download vars
#
our ($DOWNLOAD_FH, $DOWNLOAD_TOTAL);

##########################################################################

sub connect {
    my $self = shift;

    my $vm;
    confess "undefined host" if !defined $self->host;

    if ($self->host eq 'localhost') {
        $vm = Sys::Virt->new( address => $self->type.":///system");
    } else {
        $vm = Sys::Virt->new( address => $self->type."+ssh"."://".$self->host."/system");
    }
    return $vm;
}

sub _load_storage_pool {
    my $self = shift;

    my $vm_pool;

    for my $pool ($self->vm->list_storage_pools) {
        my $doc = $XML->load_xml(string => $pool->get_xml_description);

        my ($path) =$doc->findnodes('/pool/target/path/text()');
        next if !$path;

        $DEFAULT_DIR_IMG = $path;
        $vm_pool = $pool;
    }
    die "I can't find /pool/target/path in the storage pools xml\n"
        if !$vm_pool;

    return $vm_pool;

}

sub domain_create {
    my $self = shift;
    my %args = @_;
    lock_hash(%args);
    
    croak "argument name required"       if !$args{name};
    croak "argument id_iso_image or id_base required" 
        if !$args{id_iso} && !$args{id_base};

    if ($args{id_iso}) {
        return $self->_domain_create_from_iso(@_);
    } else {
        confess "TODO";
    }

}

sub _domain_create_from_iso {
    my $self = shift;
    my %args = @_;

    croak "argument id_iso required" 
        if !$args{id_iso};

    my $vm = $self->vm;
    my $storage = $self->storage_pool;

    my $iso = $self->_search_iso($args{id_iso});

    my $device_cdrom = _iso_name($iso);
    my $device_disk = ( $args{device_disk} or undef );

    my $xml = $self->_define_xml($args{name} , "$DIR_XML/$iso->{xml}");

    _xml_modify_cdrom($xml, $device_cdrom);
    _xml_modify_disk($xml, $device_disk)    if $device_disk;
}

sub _iso_name {
    my $iso = shift;
    my ($iso_name) = $iso->{url} =~ m{.*/(.*)};
    my $device = "$DEFAULT_DIR_IMG/$iso_name";

    if (! -e $device || ! -s $device) {
        _download_file_external($iso->{url}, $device);
    }
    return $device;
}

sub _download_file_lwp_progress {
    my( $data, $response, $proto ) = @_;
    print $DOWNLOAD_FH $data; # write data to file
    $DOWNLOAD_TOTAL += length($data);
    my $size = $response->header('Content-Length');
    warn floor(($DOWNLOAD_TOTAL/$size)*100),"% downloaded\n"; # print percent downloaded
}

sub _download_file_lwp {
    my ($url_req, $device) = @_;

    unlink $device or die "$! $device" if -e $device;

    $DOWNLOAD_FH = undef;
    $DOWNLOAD_TOTAL = 0;
    sysopen($DOWNLOAD_FH, $device, O_WRONLY|O_EXCL|O_CREAT) ||
		      die "Can't open $device $!";

    my $ua = LWP::UserAgent->new(keep_alive => 1);

    my $url = URI->new(decode(locale => $url_req)) or die "Error decoding $url_req";
    warn $url;

    my $res = $ua->request(HTTP::Request->new(GET => $url)
        ,sub {
            my ($data, $response) = @_;

            unless (fileno $DOWNLOAD_FH) {
                open $DOWNLOAD_FH,">",$device || die "Can't open $device $!\n";
            }
            binmode($DOWNLOAD_FH);
            print $DOWNLOAD_FH $data or die "Can't write to $device: $!\n";
            $DOWNLOAD_TOTAL += length($data);
            my $size = $response->header('Content-Length');
            warn floor(($DOWNLOAD_TOTAL/$size)*100),"% downloaded\n"; # print percent downloaded
        }
    );
    close $DOWNLOAD_FH or die "$! $device";

    close $DOWNLOAD_FH if fileno($DOWNLOAD_FH);
    $DOWNLOAD_FH = undef;

    warn $res->status_line;
}

sub _download_file_external {
    my ($url,$device) = @_;
    my @cmd = ("/usr/bin/lwp-download",$url,$device);
    my ($in,$out,$err) = @_;
    warn join(" ",@cmd)."\n";
    run3(\@cmd,\$in,\$out,\$err);
    print $out if $out;
    die $err if $err;
}

sub _search_iso {
    my $self = shift;
    my $id_iso = shift or croak "Missing id_iso";

    my $sth = $self->connector->dbh->prepare("SELECT * FROM iso_images WHERE id = ?");
    $sth->execute($id_iso);
    my $row = $sth->fetchrow_hashref;
    die "Missing iso_image id=$id_iso" if !keys %$row;
    return $row;
}

###################################################################################
#
# XML methods
#

sub _define_xml {
    my $self = shift;
    my ($name, $xml_source) = @_;
    my $doc = $XML->parse_file($xml_source) or die "ERROR: $! $xml_source\n";

        my ($node_name) = $doc->findnodes('/domain/name/text()');
    $node_name->setData($name);

    $self->_xml_modify_mac($doc);
    $self->_xml_modify_uuid($doc);
    _xml_modify_spice_port($doc);
    _xml_modify_video($doc);

    return $doc;

}

sub _xml_modify_video {
    my $doc = shift;

    my ( $video , $video2 ) = $doc->findnodes('/domain/devices/video/model');
    ( $video , $video2 ) = $doc->findnodes('/domain/devices/video')
        if !$video;

    die "I can't find video in "
                .join("\n"
                     ,map { $_->toString() } $doc->findnodes('/domain/devices/video'))
        if !$video;
    $video->setAttribute(type => 'qxl');
    $video->setAttribute( ram => 65536 );
    $video->setAttribute( vram => 65536 );
    $video->setAttribute( vgamem => 16384 );
    $video->setAttribute( heads => 1 );
    
    warn "WARNING: more than one video card found\n".
        $video->toString().$video2->toString()  if $video2;

}

sub _xml_modify_spice_port {
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

sub _xml_modify_uuid {
    my $self = shift;
    my $doc = shift;
    my ($uuid) = $doc->findnodes('/domain/uuid/text()');

    random:while (1) {
        my $new_uuid = _new_uuid($uuid);
        next if $new_uuid eq $uuid;
        for my $dom ($self->vm->list_all_domains) {
            next random if $dom->get_uuid_string eq $new_uuid;
        }
        $uuid->setData($new_uuid);
        last;
    }
}

sub _xml_modify_cdrom {
    my ($doc, $iso) = @_;

    my @nodes = $doc->findnodes('/domain/devices/disk');
    for my $disk (@nodes) {
        next if $disk->getAttribute('device') ne 'cdrom';
        if (!$iso) {
            warn "TODO remove cdrom\n";
            return;
        }
        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                $child->setAttribute(file => $iso);
                return;
            }
        }

    }
    die "I can't find CDROM on ". join("\n",map { $_->toString() } @nodes);
}

sub _xml_modify_disk {
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

sub _unique_mac {
    my $self = shift;

    my $mac = shift;

    $mac = lc($mac);

    for my $dom ($self->vm->list_all_domains) {
        my $doc = $XML->load_xml(string => $dom->get_xml_description()) or die "ERROR: $!\n";

        for my $nic ( $doc->findnodes('/domain/devices/interface/mac')) {
            my $nic_mac = $nic->getAttribute('address');
            return 0 if $mac eq lc($nic_mac);
        }
    }
    return 1;
}

sub _new_uuid {
    my $uuid = shift;
    
    my ($principi, $f1,$f2) = $uuid =~ /(.*)(.)(.)/;

    return $principi.int(rand(10)).int(rand(10));
    
}

sub _xml_modify_mac {
    my $self = shift;
    my $doc = shift;

    my ($if_mac) = $doc->findnodes('/domain/devices/interface/mac')
        or exit;
    my $mac = $if_mac->getAttribute('address');

    my @macparts = split/:/,$mac;

    my $new_mac;
    for my $last ( 0 .. 99 ) {
        $last = "0$last" if length($last)<2;
        $macparts[-1] = $last;
        $new_mac = join(":",@macparts);
        last if $self->_unique_mac($new_mac);
        $new_mac = undef;
    }
    die "I can't find a new unique mac" if !$new_mac;
    $if_mac->setAttribute(address => $new_mac);
}


#############################################################################
#
# inits
#
sub _init_ip {
    my $name = hostname() or die "CRITICAL: I can't find the hostname.\n";
    my $ip = inet_ntoa(inet_aton($name)) 
        or die "CRITICAL: I can't find IP of $name in the DNS.\n";

    if ($ip eq '127.0.0.1') {
        #TODO Net:DNS
        $ip= `host $name`;
        chomp $ip;
        $ip =~ s/.*?address (\d+)/$1/;
    }
    die "I can't find IP with hostname $name ( $ip )\n"
        if !$ip || $ip eq '127.0.0.1';

    return $ip;
}

sub domain_remove_vm {}

sub prepare_base {}

sub volume_create {}

1;
