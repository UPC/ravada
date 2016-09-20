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

use Ravada::Domain::KVM;

with 'Ravada::VM';

##########################################################################
#

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

has type => (
    isa => 'Str'
    ,is => 'ro'
    ,default => 'qemu'
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

our $CONNECTOR = \$Ravada::CONNECTOR;

##########################################################################

=head2 connect

Connect to the Virtual Machine Manager

=cut

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

=head2 dir_img

Returns the directory where disk images are stored in this Virtual Manager

=cut

sub dir_img {
    my $self = shift;
    return $DEFAULT_DIR_IMG if $DEFAULT_DIR_IMG;
    
    $self->_load_storage_pool();
    return $DEFAULT_DIR_IMG;
}

=head2 create_domain

Creates a domain.

    $dom = $vm->create_domain(name => $name , id_iso => $id_iso);
    $dom = $vm->create_domain(name => $name , id_base => $id_base);

=cut

sub create_domain {
    my $self = shift;
    my %args = @_;

    $args{active} = 1 if !defined $args{active};
    
    croak "argument name required"       if !$args{name};
    croak "argument id_owner required"   if !$args{id_owner};
    croak "argument id_iso or id_base required ".Dumper(\%args)
        if !$args{id_iso} && !$args{id_base};

    my $domain;
    if ($args{id_iso}) {
        $domain = $self->_domain_create_from_iso(@_);
    } elsif($args{id_base}) {
        $domain = $self->_domain_create_from_base(@_);
    } else {
        confess "TODO";
    }

    return $domain;
}

=head2 search_domain

Returns true or false if domain exists.

    $domain = $vm->search_domain($domain_name);

=cut

sub search_domain {
    my $self = shift;
    my $name = shift or confess "Missing name";

    for ($self->vm->list_all_domains()) {
        next if $_->get_name ne $name;

        my $domain;
        eval {
            $domain = Ravada::Domain::KVM->new(
                domain => $_
                ,storage => $self->storage_pool
            );
        };
        warn $@ if $@;
        return $domain if $domain;
    }
    return;
}

=head2 search_domain_by_id

Returns a domain searching by its id

    $domain = $vm->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains "
        ." WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return if !$name;

    return $self->search_domain($name);
}

=head2 list_domains

Returns a list of the created domains

  my @list = $vm->list_domains();

=cut

sub list_domains {
    my $self = shift;

    my @list;
    for my $name ($self->vm->list_all_domains()) {
        my $domain ;
        my $id;
        eval { $domain = Ravada::Domain::KVM->new(
                          domain => $name
                        ,storage => $self->storage_pool
                    );
             $id = $domain->id();
        };
        push @list,($domain) if $domain && $id;
    }
    return @list;
}

=head2 create_volume

Creates a new storage volume. It requires a name and a xml template file defining the volume

   my $vol = $vm->create_volume($name, $file_xml);

=cut

sub create_volume {
    my $self = shift;
    my ($name, $file_xml) = @_;
    confess "Missing volume name"   if !$name;
    confess "Missing xml template"  if !$file_xml;

    open my $fh,'<', $file_xml or die "$! $file_xml";
    my $dir_img = $DEFAULT_DIR_IMG;

    my $doc = $XML->load_xml(IO => $fh);

    $doc->findnodes('/volume/name/text()')->[0]->setData("$name.img");
    $doc->findnodes('/volume/key/text()')->[0]->setData("$dir_img/$name.img");
    $doc->findnodes('/volume/target/path/text()')->[0]->setData(
                "$dir_img/$name.img");

    my $vol = $self->storage_pool->create_volume($doc->toString);
    warn "volume $dir_img/$name.img does not exists after creating volume"
            if ! -e "$dir_img/$name.img";
    return "$dir_img/$name.img";

}

=head2 search_volume

Searches a volume

    my $vol =$vm->search_volume($name);

=cut

sub search_volume {
    my $self = shift;
    my $name = shift or confess "Missing volume name";

    my $vol;
    eval { $vol = $self->storage_pool->get_volume_by_name($name) };
    return $vol;
}

sub _domain_create_from_iso {
    my $self = shift;
    my %args = @_;

    for (qw(id_iso id_owner)) {
        croak "argument $_ required" 
            if !$args{$_};
    }

    die "Domain $args{name} already exists"
        if $self->search_domain($args{name});

    my $vm = $self->vm;
    my $storage = $self->storage_pool;

    my $iso = $self->_search_iso($args{id_iso});

    my $device_cdrom = _iso_name($iso);

    my $device_disk = $self->create_volume($args{name}, $DIR_XML."/".$iso->{xml_volume});

    my $xml = $self->_define_xml($args{name} , "$DIR_XML/$iso->{xml}");

    _xml_modify_cdrom($xml, $device_cdrom);
    _xml_modify_disk($xml, $device_disk)    if $device_disk;

    my $dom = $self->vm->define_domain($xml->toString());
    $dom->create if $args{active};

    my $domain = Ravada::Domain::KVM->new(domain => $dom , storage => $self->storage_pool);
    $domain->_insert_db(name => $args{name}, id_owner => $args{id_owner});
    return $domain;
}
sub _create_disk {
    return _create_disk_qcow2(@_);
}

sub _create_disk_qcow2 {
    my $self = shift;
    my ($base, $name) = @_;

    confess "Missing base" if !$base;
    confess "Missing name" if !$name;

    my $dir_img  = $DEFAULT_DIR_IMG;

    my $file_out = "$dir_img/$name.qcow2";

    if (-e $file_out ) {
        die "WARNING: output file $file_out already existed [skipping]\n";
    }

    die "ERROR: Missing file_base_img in base ".$base->id
        ." "
        .Dumper($base->_select_domain_db)
            if ! $base->file_base_img;

    my @cmd = ('qemu-img','create'
                ,'-f','qcow2'
                ,"-b", $base->file_base_img
                ,$file_out
    );
#    warn join(" ",@cmd)."\n";

    my ($in, $out, $err);
    run3(\@cmd,\$in,\$out,\$err);
    print $out  if $out;
    warn $err   if $err;

    if (! -e $file_out) {
        warn "ERROR: Output file $file_out not created at ".join(" ",@cmd)."\n";
        exit;
    }
    
    return $file_out;
}

sub _search_domain_by_id {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domains WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    return $self->search_domain($row->{name});
}

sub _domain_create_from_base {
    my $self = shift;
    my %args = @_;

    confess "argument id_base or base required ".Dumper(\%args) 
        if !$args{id_base} && !$args{base};

    die "Domain $args{name} already exists"
        if $self->search_domain($args{name});

    my $base = $args{base}  if $args{base};

    $base = $self->_search_domain_by_id($args{id_base}) if $args{id_base};

    my $vm = $self->vm;
    my $storage = $self->storage_pool;
    my $xml = XML::LibXML->load_xml(string => $base->domain->get_xml_description());

    my $device_disk = $self->_create_disk($base, $args{name});
#    _xml_modify_cdrom($xml);
    _xml_remove_cdrom($xml);
    my ($node_name) = $xml->findnodes('/domain/name/text()');
    $node_name->setData($args{name});

    _xml_modify_disk($xml, $device_disk);
    $self->_xml_modify_mac($xml);
    $self->_xml_modify_uuid($xml);
    _xml_modify_spice_port($xml);
    _xml_modify_video($xml);


    my $dom = $self->vm->define_domain($xml->toString());
    $dom->create;

    my $domain = Ravada::Domain::KVM->new(domain => $dom , storage => $self->storage_pool);

    $domain->_insert_db(name => $args{name}, id_base => $base->id, id_owner => $args{id_owner});
    return $domain;
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

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM iso_images WHERE id = ?");
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
        for my $child ($disk->childNodes) {
            if ($child->nodeName eq 'source') {
                $child->setAttribute(file => $iso);
                return;
            }
        }

    }
    die "I can't find CDROM on ". join("\n",map { $_->toString() } @nodes);
}

sub _xml_remove_cdrom {
    my $doc = shift;

    my ($node_devices )= $doc->findnodes('/domain/devices');
    my $devices = $doc->findnodes('/domain/devices');
    for my $context ($devices->get_nodelist) {
        for my $disk ($context->findnodes('./disk')) {
#            warn $node->toString();
            if ( $disk->nodeName eq 'disk'
                && $disk->getAttribute('device') eq 'cdrom') {

                my ($source) = $disk->findnodes('./source');
                if ($source) {
#                    warn "\n\t->removing ".$source->nodeName." ".$source->getAttribute('file')
#                        ."\n";
                    $disk->removeChild($source);
                }
            }
        }
    }
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
    my $doc = shift or confess "Missing XML doc";

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

1;
