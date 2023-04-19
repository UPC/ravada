
package Ravada::VM::KVM;

use warnings;
use strict;

=head1 NAME

Ravada::VM::KVM - KVM Virtual Managers library for Ravada

=cut

use Carp qw(croak carp cluck);
use Data::Dumper;
use Digest::MD5;
use Encode;
use Encode::Locale;
use File::Path qw(make_path);
use Fcntl qw(:flock O_WRONLY O_EXCL O_CREAT);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use IO::Interface::Simple;
use JSON::XS;
use Mojo::DOM;
use Mojo::UserAgent;
use Moose;
use Sys::Virt;
use URI;
use XML::LibXML;

use feature qw(signatures);
no warnings "experimental::signatures";

use Ravada::Domain::KVM;
use Ravada::NetInterface::KVM;
use Ravada::NetInterface::MacVTap;
use Ravada::Utils;

with 'Ravada::VM';

##########################################################################
#

has vm => (
#    isa => 'Sys::Virt'
    is => 'rw'
    ,builder => '_connect'
    ,lazy => 1
);

has type => (
    isa => 'Str'
    ,is => 'ro'
    ,default => 'KVM'
);

#########################################################################3
#

#TODO use config file for DIR_XML
our $DIR_XML = "etc/xml";
$DIR_XML = "/var/lib/ravada/xml/" if $0 =~ m{^/usr/sbin};

our $FILE_CONFIG_QEMU = "/etc/libvirt/qemu.conf";

our $XML = XML::LibXML->new();
our %USED_MAC;

#-----------
#
# global download vars
#
our ($DOWNLOAD_FH, $DOWNLOAD_TOTAL);

our $CONNECTOR = \$Ravada::CONNECTOR;

our $WGET = `which wget`;
chomp $WGET;

our $CACHE_DOWNLOAD = 1;
our $VERIFY_ISO = 1;

our %_CREATED_DEFAULT_STORAGE = ();

our $MIN_CAPACITY = 1024 * 10;
##########################################################################


sub _connect {
    my $self = shift;

    my $vm;
    confess "undefined host" if !defined $self->host;

    my $con_type = $self->type;
    $con_type = 'qemu' if $self->type eq 'KVM';

    if ($self->host eq 'localhost') {
        my $address = "system";
        $address = "session" if $<;
        $vm = Sys::Virt->new( address => $con_type.":///$address" , readonly => $self->readonly);
    } else {
        confess "Error: You can't connect to remote VMs in readonly mode"
            if $self->readonly;
        my $transport = 'ssh';
        my $address = $con_type."+".$transport
                                            ."://".'root@'.$self->host
                                            ."/system";
        eval {
            $vm = Sys::Virt->new(
                                address => $address
                              ,auth => 1
                              ,credlist => [
                                  Sys::Virt::CRED_AUTHNAME,
                                  Sys::Virt::CRED_PASSPHRASE,
                              ]
                          );
         };
         confess $@ if $@;
    }
    if ( ! _list_storage_pools($vm) && !$_CREATED_DEFAULT_STORAGE{$self->host}) {
	    warn "WARNING: No storage pools creating default\n";
    	$self->_create_default_pool($vm);
        $_CREATED_DEFAULT_STORAGE{$self->host}++;
    }
    $self->_check_networks($vm);
    return $vm;
}

sub _list_storage_pools($vm) {
    confess if !defined $vm || !ref($vm);
   for ( ;; ) {
       my @pools;
       eval { @pools = $vm->list_all_storage_pools };
       return @pools if !$@;
       die $@ if $@ && $@ !~ /libvirt error code: 1,/;
       sleep 1;
   }
}


sub _check_networks {
    my $self = shift;
    my $vm = shift;

    for my $net ($vm->list_all_networks) {
        next if $net->is_active;

        warn "INFO: Activating KVM network ".$net->get_name."\n";
        $net->create;
        $net->set_autostart(1);
    }
}

=head2 disconnect

Disconnect from the Virtual Machine Manager

=cut

sub disconnect {
    my $self = shift;

    $self->vm(undef);
}

=head2 connect

Connect to the Virtual Machine Manager

=cut

sub connect {
    my $self = shift;
    return $self->vm if $self->vm;
    return $self->vm if $self->is_alive;

    return $self->vm($self->_connect);
#    $self->storage_pool($self->_load_storage_pool);
}

sub _reconnect($self) {
    $self->vm(undef);
    return $self->connect();
}

sub _get_pool_info($pool) {
   my $info;
   for (;;) {
       eval { $info = $pool->get_info() };
       return $info if $info;
       die $@ if $@ && $@ !~ /libvirt error code: 1,/;
       sleep 1;
   }
}

sub _load_storage_pool {
    my $self = shift;

    confess "no hi ha vm" if !$self->vm;

    my $vm_pool;
    my $available;

    if ($self->default_storage_pool_name) {
        return( $self->vm->get_storage_pool_by_name($self->default_storage_pool_name)
            or confess "ERROR: Unknown storage pool: ".$self->default_storage_pool_name);
    }

    for my $pool (_list_storage_pools($self->vm)) {
        next if !$pool->is_active;
        my $info = _get_pool_info($pool);
        next if defined $available
                && $info->{available} <= $available;

        my $doc = $XML->load_xml(string => $pool->get_xml_description);

        my ($path) =$doc->findnodes('/pool/target/path/text()');
        next if !$path;

        $vm_pool = $pool;
        $available = $info->{available};

    }
    confess "I can't find /pool/target/path in the storage pools xml\n"
        if !$vm_pool;

    return $vm_pool;

}

=head2 storage_pool

Returns a storage pool usable by the domain to store new volumes.

=cut

sub storage_pool {
    my $self = shift;

    return $self->_load_storage_pool();
}

=head2 search_volume

Searches for a volume in all the storage pools known to the Virtual Manager

Argument: the filenaname;
Returns the volume as a Sys::Virt::StorageGol. If called in array context returns a
list of all the volumes.

    my $iso = $vm->search_volume("debian-8.iso");

    my @disk = $vm->search_volume("windows10-clone.img");

=cut

sub search_volume($self,$file,$refresh=0) {
    confess "ERROR: undefined file" if !defined $file;

    my ($name) = $file =~ m{.*/(.*)};
    $name = $file if !defined $name;

    my $vol;
    for my $pool (_list_storage_pools($self->vm)) {
        next if !$pool->is_active;
        if ($refresh) {
            for ( 1 .. 10 ) {
               eval { $pool->refresh() };
               last if !$@;
               warn "WARNING: on search volume $@";
               sleep 1;
            }
            sleep 1;
        }
        eval { $vol = $pool->get_volume_by_name($name) };
        die $@ if $@ && $@ !~ /^libvirt error code: 50,/;
    }

    return $self->search_volume_re(qr(^$name$),$refresh);
}

=head2 search_volume_path

Searches for a volume in all the storage pools known to the Virtual Manager

Argument: the filenaname;
Returns the path of the volume. If called in array context returns a
list of all the paths to all the matching volumes.

    my $iso = $vm->search_volume("debian-8.iso");

    my @disk = $vm->search_volume("windows10-clone.img");



=cut

sub search_volume_path {
    my $self = shift;
    my @volume = $self->search_volume(@_);

    my @vol2 = map { $_->get_path() if ref($_) } @volume;

    return $vol2[0] if !wantarray;
    return @vol2;
}

=head2 search_volume_re

Searches for a volume in all the storage pools known to the Virtual Manager

Argument: a regular expression;
Returns the volume. If called in array context returns a
list of all the matching volumes.

    my $iso = $vm->search_volume(qr(debian-\d+\.iso));

    my @disk = $vm->search_volume(qr(windows10-clone.*\.img));

=cut

sub search_volume_re($self,$pattern,$refresh=0) {

    confess "'$pattern' doesn't look like a regexp to me ".ref($pattern)
        if !ref($pattern) || ref($pattern) ne 'Regexp';

    $self->_refresh_storage_pools()    if $refresh;

    my @volume;
    for my $pool (_list_storage_pools($self->vm)) {
        next if !$pool->is_active;
       my @vols;
       for ( 1 .. 10) {
           eval { @vols = $pool->list_all_volumes() };
           last if !$@ || $@ =~ / no storage pool with matching uuid/;
           warn "WARNING: on search volume_re: $@";
           sleep 1;
       }
       for my $vol ( @vols ) {
           my $file;
           eval { ($file) = $vol->get_path =~ m{.*/(.*)} };
           confess $@ if $@ && $@ !~ /libvirt error code: 50,/;
           next if !$file || $file !~ $pattern;


           return $vol if !wantarray;
           push @volume,($vol);
       }
    }
    if (!scalar @volume && !$refresh && !$self->readonly
            && time - ($self->{_time_refreshed} or 0) > 60) {
        $self->{_time_refreshed} = time;
        @volume = $self->search_volume_re($pattern,"refresh");
        return $volume[0] if !wantarray && scalar @volume;
    }
    return if !wantarray && !scalar@volume;
    return @volume;
}

sub remove_file($self,@files) {
    for my $file (@files) {
        if ($self->is_local) {
            unlink $file or die "$! $file";
            next;
        }
        my $vol = $self->search_volume($file);
        if (!$vol) {
            $self->_refresh_storage_pools();
            $vol = $self->search_volume($file);
        }
        if (!$vol) {
            warn "Warning: '$file' not found\n";
        }
        $vol->delete if $vol;
    }
}

sub _list_volumes($self) {
    my @volumes;
    for my $pool (_list_storage_pools($self->vm)) {
        next if !$pool->is_active;
       my @vols;
       for ( 1 .. 10) {
           eval { @vols = $pool->list_all_volumes() };
           last if !$@ || $@ =~ / no storage pool with matching uuid/;
           warn "WARNING: on search volume_re: $@";
           sleep 1;
       }
       push @volumes,@vols;
    }
    return @volumes;
}

sub _list_used_volumes_known($self) {
    my $sth = $self->_dbh->prepare(
        "SELECT id,name FROM domains WHERE id_vm=?"
    );
    $sth->execute($self->id);
    my @used;
    while ( my ($id, $name) = $sth->fetchrow) {
        my $dom = $self->search_domain($name);
        my $xml = $dom->xml_description();
        my @vols = $self->_find_all_volumes($xml);
        push @used,@vols;
    }
    return @used;
}

sub _find_all_volumes_bs($self, $disk) {
    my @volumes;
    for my $bs ($disk->findnodes("backingStore")) {
        my ($source) = $bs->findnodes("source");
        if ($source) {
            my $file = $source->getAttribute('file');
            push @volumes,($file) if $file;
        }
        my @bs = $self->_find_all_volumes_bs($bs);
        push @volumes,@bs if scalar(@bs);
    }
    return @volumes;
}

sub _find_all_volumes($self, $xml) {
    my @used;
    my $doc = XML::LibXML->load_xml(string => $xml);
    for my $disk ($doc->findnodes("/domain/devices/disk")) {
        my ($source) = $disk->findnodes("source");
        next if !$source;
        my $file = $source->getAttribute('file');
        push @used,($file) if $file;
        my @used_bs = $self->_find_all_volumes_bs($disk);
        push @used,@used_bs if scalar(@used_bs);
    }
    return @used;
}

sub _list_used_volumes($self) {
    my @used =$self->_list_used_volumes_known();
    for my $name ( $self->discover ) {
        my $dom = $self->vm->get_domain_by_name($name);
        push @used,$self->_find_all_volumes($dom->get_xml_description());
    }
    return @used;
}

sub list_unused_volumes($self) {
    my %used = map { $_ => 1 } $self->_list_used_volumes();
    my @unused;
    my $file;

    my $n_found=0;
    for my $vol ( $self->_list_volumes ) {

        eval { ($file) = $vol->get_path };
        confess $@ if $@ && $@ !~ /libvirt error code: 50,/;

        next if $used{$file};

        my $info;
        eval { $info = $vol->get_info() };
        die "$file $@" if $@
        && ( ref($@) =~ /Sys::Virt:Error/ && $@->cod ne 50); #storage volume not found

        next if !$info || $info->{type} eq 2;

        #        cluck Dumper([ $file, [sort grep /2023/,keys %used]]) if $file =~/2023/;
        push @unused,($file);

    }
    return @unused;
}

sub refresh_storage_pools($self) {
    $self->_refresh_storage_pools();
}

sub _refresh_storage_pools($self) {
    for my $pool (_list_storage_pools($self->vm)) {
        next if !$pool->is_active;
        for ( 1 .. 10 ) {
            eval { $pool->refresh() };
            last if !$@;
            warn $@ if $@ !~ /pool .* has asynchronous jobs running/;
            sleep 1;
        }
    }
}

=head2 refresh_storage

Refreshes all the storage pools

=cut

sub refresh_storage($self) {
    $self->_refresh_storage_pools();
    $self->_refresh_isos();
}

sub _refresh_isos($self) {
    $self->_init_connector();
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM iso_images ORDER BY name"
    );
    my $sth_update = $$CONNECTOR->dbh->prepare("UPDATE iso_images set device=? WHERE id=?");

    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {

        if ( $row->{device} && !-e $row->{device} ) {
            delete $row->{device};
            $sth_update->execute($row->{device}, $row->{id});
            next;
        }
        next if $row->{device};
        next if !$row->{url};

        my $file_re = $row->{file_re};
        my ($file);
        ($file) = $row->{url} =~ m{.*/(.*)}   if $row->{url};
        $file = $row->{rename_file} if $row->{rename_file};

        $file_re = "^$file\$" if $file;

        if (!$file_re) {
            warn "Error: ISO mismatch ".Dumper($row);
            next;
        }
        $file_re = "$file_re\$" unless $file_re =~ /\$$/;
        $file_re = "^$file_re"  unless $file_re =~ /^\$/;

        my $iso_file = $self->search_volume_path_re(qr($file_re));
        if ($iso_file) {
            $row->{device} = $iso_file;
        }
        $sth_update->execute($row->{device}, $row->{id}) if $row->{device};
    }
    $sth->finish;
}

=head2 search_volume_path_re

Searches for a volume in all the storage pools known to the Virtual Manager

Argument: a regular expression;
Returns the volume path. If called in array context returns a
list of all the paths of all the matching volumes.

    my $iso = $vm->search_volume(qr(debian-\d+\.iso));

    my @disk = $vm->search_volume(qr(windows10-clone.*\.img));

=cut


sub search_volume_path_re($self, $pattern) {
    my @vol = $self->search_volume_re($pattern);

    return if !wantarray && !scalar @vol;
    return $vol[0]->get_path if !wantarray;

    return map { $_->get_path() if ref($_) } @vol;

}

=head2 file_exists

Returns true if the file exists in this virtual manager storage

=cut

sub file_exists($self, $file) {
    return -e $file if $self->is_local;
    return $self->_file_exists_remote($file);
}

sub _file_exists_remote($self, $file) {
    $file = $self->_follow_link($file) unless $file =~ /which$/;
    for my $pool ($self->vm->list_all_storage_pools ) {
        $self->_wait_storage( sub { $pool->refresh() } );
        my @volumes = $self->_wait_storage( sub { $pool->list_all_volumes });
        for my $vol ( @volumes ) {
            my $found;
            eval {
                my $path = $vol->get_path;
                $self->_follow_link($vol->get_path) unless $file =~ /which$/;
                $found = 1 if $path eq $file;
            };
            # volume was removed in the nick of time
            die $@ if $@ && ( !ref($@) || $@->code != 50);
            return 1 if $found;
        }
    }

    die "Error: invalid file '$file'" if $file =~ /[`;(\[" ]/;
    my ($out,$err) = $self->_ssh->capture2("ls $file");
    my @ls = split /\n/,$out;
    for (@ls) { chomp };
    return scalar(@ls);
}

sub _follow_link($self, $file) {
    my ($dir, $name) = $file =~ m{(.*)/(.*)};
    if (!defined $self->{_is_link}->{$dir} ) {
        my ($out,$err) = $self->run_command("stat", $dir );
        chomp $out;
        $out =~ m{ -> (/.*)};
        $self->{_is_link}->{$dir} = $1;
    }
    my $path = $self->{_is_link}->{$dir};
    return $file if !$path;
    return "$path/$name";

}

sub _wait_storage($self, $sub) {
    my @ret;
    for ( 1 .. 10  ) {
        eval { @ret=$sub->() };
        last if !$@;
        die $@ if !ref($@) || $@->code != 1;
        warn "Warning: $@ [retrying $_]";
        sleep 1;
    };
    return @ret;
}

=head2 dir_img

Returns the directory where disk images are stored in this Virtual Manager

=cut

sub dir_img {
    my $self = shift;

    my $pool = $self->_load_storage_pool();
    $pool = $self->_create_default_pool() if !$pool;
    my $xml = XML::LibXML->load_xml(string => $pool->get_xml_description());

    my $dir = $xml->findnodes('/pool/target/path/text()');
    die "I can't find /pool/target/path in ".$xml->toString
        if !$dir;

    return $dir;
}

=head2 dir_base

Returns the directory where base images are stored in this Virtual Manager

=cut


sub dir_base($self, $volume_size) {
    my $pool_base = $self->default_storage_pool_name;
    $pool_base = $self->base_storage_pool()    if $self->base_storage_pool();
    $pool_base = $self->storage_pool()         if !$pool_base;

    $self->_check_free_disk($volume_size * 2, $pool_base);
    return $self->_storage_path($pool_base);

}

=head2 dir_clone

Returns the directory where clone images are stored in this Virtual Manager

=cut


sub dir_clone($self) {

    my $dir_img  = $self->dir_img;
    my $clone_pool = $self->clone_storage_pool();
    $dir_img = $self->_storage_path($clone_pool) if $clone_pool;

    return $dir_img;
}

sub _storage_path($self, $storage) {
    if (!ref($storage)) {
        $storage = $self->vm->get_storage_pool_by_name($storage);
    }
    my $xml = XML::LibXML->load_xml(string => $storage->get_xml_description());

    my $dir = $xml->findnodes('/pool/target/path/text()');
    die "I can't find /pool/target/path in ".$xml->toString
        if !$dir;

    return $dir;

}

sub _create_default_pool {
    my $self = shift;
    my $vm = shift;
    $vm = $self->vm if !$vm;

    my $uuid = Ravada::VM::KVM::_new_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');

    my $dir = "/var/lib/libvirt/images";
    mkdir $dir if ! -e $dir;

    my $xml =
"<pool type='dir'>
  <name>default</name>
  <uuid>$uuid</uuid>
  <capacity unit='bytes'></capacity>
  <allocation unit='bytes'></allocation>
  <available unit='bytes'></available>
  <source>
  </source>
  <target>
    <path>$dir</path>
    <permissions>
      <mode>0711</mode>
      <owner>0</owner>
      <group>0</group>
    </permissions>
  </target>
</pool>"
;
    my $pool;
    eval {
        $pool = $vm->define_storage_pool($xml);
        $pool->create();
        $pool->set_autostart(1);
    };
    warn $@ if $@;

}

=head2 create_domain

Creates a domain.

    $dom = $vm->create_domain(name => $name , id_iso => $id_iso);
    $dom = $vm->create_domain(name => $name , id_base => $id_base);

Creates a domain and removes the CPU defined in the XML template:

    $dom = $vm->create_domain(        name => $name 
                                  , id_iso => $id_iso
                              , remove_cpu => 1);

=cut

sub create_domain {
    my $self = shift;
    my %args = @_;
    $args{active} = 1 if !defined $args{active};

    croak "argument name required"       if !$args{name};
    croak "argument id_owner required"   if !$args{id_owner};
    confess "argument id_iso or id_base or config required ".Dumper(\%args)
        if !$args{id_iso} && !$args{id_base} && !$args{config};

    my $domain;
    if ($args{id_iso}) {
        $domain = $self->_domain_create_from_iso(@_);
    } elsif($args{id_base}) {
        $domain = $self->_domain_create_from_base(@_);
    } elsif($args{config}) {
        $domain = $self->_domain_create_from_config(@_);
    } else {
        confess "TODO";
    }

    return $domain;
}

=head2 search_domain

Returns true or false if domain exists.

    $domain = $vm->search_domain($domain_name);

=cut

sub search_domain($self, $name, $force=undef) {

    eval {
        $self->connect();
    };
    if ($@ && $@ =~ /libvirt error code: 38,/) {
        warn $@;
        if (!$self->is_local) {
            warn "DISABLING NODE ".$self->name;
            $self->enabled(0);
        }
        return;
    }

    my $dom;
    eval { $dom = $self->vm->get_domain_by_name($name); };
    my $error = $@;
    return if $error =~  /error code: 42,/ && !$force;

    if ($error && $error =~ /libvirt error code: 38,/ ) {
        eval {
            $self->disconnect;
            $self->connect;
        };
        confess "Error connecting to ".$self->name." $@" if $@;
        eval { $dom = $self->vm->get_domain_by_name($name); };
        confess $@ if $@ && $@ !~  /error code: 42,/;
    } elsif ($error && $error !~ /error code: 42,/) {
        confess $error;
    }

    if (!$dom) {
        return if !$force;
        return if !$self->_domain_in_db($name);
    }

    my $domain;

        my @domain = ( );
        push @domain, ( domain => $dom ) if $dom;
        push @domain, ( id_owner => $Ravada::USER_DAEMON->id)
            if $force && !$self->_domain_in_db($name);
        eval {
            $domain = Ravada::Domain::KVM->new(
                @domain
                ,name => $name
                ,readonly => $self->readonly
                ,_vm => $self
            );
        };
        warn $@ if $@;
        if ($domain) {
            $domain->xml_description()  if $dom && $domain->is_known();
            return $domain;
        }

    return;
}

=head2 list_domains

Returns a list of the created domains

  my @list = $vm->list_domains();

=cut

sub list_domains {
    my $self = shift;
    my %args = @_;

    return if !$self->vm;

    my $active = (delete $args{active} or 0);
    my $read_only = delete $args{read_only};

    confess "Arguments unknown ".Dumper(\%args)  if keys %args;

    my $query = "SELECT id, name FROM domains WHERE id_vm = ? ";
    $query .= " AND status = 'active' " if $active;

    my $sth = $$CONNECTOR->dbh->prepare($query);

    $sth->execute( $self->id );
    my @list;
    while ( my ($id) = $sth->fetchrow) {
        my $domain;
        eval{
            if ($read_only) {
                $domain = Ravada::Front::Domain->open( $id );
            } else {
                $domain = Ravada::Domain->open( id => $id, vm => $self);
            }
        };
        die $@ if $@ && $@ !~ /Unkown domain/i;
        push @list,($domain) if $domain;
    }
    return @list;
}

sub discover($self) {
    my @known = $self->list_domains(read_only => 1);
    my %known = map { $_->name => 1 } @known;

    my @list;
    for my $dom ($self->vm->list_all_domains) {
        my $name = Encode::decode_utf8($dom->get_name);
        push @list,($name) if !$known{$name};
    }
    return @list;
}

=head2 create_volume

Creates a new storage volume. It requires a name and a xml template file defining the volume

   my $vol = $vm->create_volume(name => $name, name => $file_xml);

=cut

sub create_volume {
    my $self = shift;

    confess "Wrong arrs " if scalar @_ % 2;
    my %args = @_;

    my $name = delete $args{name}       or confess "ERROR: Missing volume name";
    my $file_xml = delete $args{xml}   or confess "ERROR: Missing XML template";

    my $size        = delete $args{size};
    $size = int($size) if defined $size;
    my $type        =(delete $args{type} or 'sys');
    my $format      =(delete $args{format} or 'qcow2');
    my $swap        =(delete $args{swap} or 0);
    my $target      = delete $args{target};
    my $capacity    = delete $args{capacity};
    my $allocation  = delete $args{allocation};

    confess "ERROR: Unknown args ".Dumper(\%args)   if keys %args;
    confess "Error: type $type can't have swap flag" if $args{swap} && $type ne 'swap';

    confess "Invalid size"          if defined $size && ( $size == 0 || $size !~ /^\d+(\.\d+)?$/);

    confess "Invalid capacity"
        if defined $capacity && ( $capacity == 0 || $capacity !~ /^\d+$/);

    confess "Capacity and size are the same, give only one of them"
        if defined $capacity && defined $size;

    $capacity = $size if defined $size;
    $allocation = int($capacity * 0.1)+1
        if !defined $allocation && $capacity;

    open my $fh,'<', $file_xml or confess "$! $file_xml";

    my $doc;
    eval { $doc = $XML->load_xml(IO => $fh) };
    die "ERROR reading $file_xml $@"    if $@;

    my $storage_pool = $self->storage_pool();

    confess $name if $name =~ /-\w{4}-vd[a-z]-\w{4}\./
        || $name =~ /\d-vd[a-z]\./;

    my $img_file = $self->_volume_path(
        target => $target
        , type => $type
        , name => $name
        , format => $format
        , storage => $storage_pool
    );

    confess if $img_file =~ /\d-vd[a-z]\./;
    my ($volume_name) = $img_file =~m{.*/(.*)};
    $doc->findnodes('/volume/name/text()')->[0]->setData($volume_name);
    $doc->findnodes('/volume/key/text()')->[0]->setData($img_file);
    my ($format_doc) = $doc->findnodes('/volume/target/format');
    $format_doc->setAttribute(type => $format);
    $doc->findnodes('/volume/target/path/text()')->[0]->setData(
                        $img_file);

    if ($capacity) {
        confess "Size '$capacity' too small, min : $MIN_CAPACITY"
        if $capacity< $MIN_CAPACITY;
        $doc->findnodes('/volume/allocation/text()')->[0]->setData(int($allocation));
        $doc->findnodes('/volume/capacity/text()')->[0]->setData($capacity);
    }
    my $vol = $self->storage_pool->create_volume($doc->toString)
        or die "volume $img_file does not exists after creating volume on ".$self->name." "
            .$doc->toString();

    return $img_file;

}

sub _volume_path {
    my $self = shift;

    my %args = @_;
    my $type = (delete $args{type} or 'sys');
    my $storage  = delete $args{storage} or confess "ERROR: Missing storage";
    my $filename = $args{name}  or confess "ERROR: Missing name";
    my $target = delete $args{target};
    my $format = delete $args{format};

    my $dir_img = $self->_storage_path($storage);
    my $suffix = "qcow2";
    $suffix = 'img' if $format && $format eq 'raw';
    $type = ''  if $type eq 'sys';
    $type = uc($type)."."   if $type;
    return "$dir_img/$filename.$type$suffix";
}

sub _domain_create_from_iso {
    my $self = shift;
    my %args = @_;
    my %args2 = %args;
    for (qw(id_iso id_owner name)) {
        delete $args2{$_};
        croak "argument $_ required"
            if !$args{$_};
    }
    my $remove_cpu = delete $args2{remove_cpu};
    my $options = delete $args2{options};
    for (qw(disk swap active request vm memory iso_file id_template volatile spice_password
            listen_ip)) {
        delete $args2{$_};
    }

    my $iso_file = delete $args{iso_file};
    confess "Unknown parameters : ".join(" , ",sort keys %args2)
        if keys %args2;

    die "Domain $args{name} already exists"
        if $self->search_domain($args{name});

    my $vm = $self->vm;
    my $iso = $self->_search_iso($args{id_iso} , $iso_file);

    die "ERROR: Empty field 'xml_volume' in iso_image ".Dumper($iso)
        if !$iso->{xml_volume};
        
    my $device_cdrom;


    confess "Template ".$iso->{name}." has no URL, iso_file argument required."
        if $iso->{has_cd} && !$iso->{url} && !$iso_file && !$iso->{device};

    if (defined $iso_file) {
        if ( $iso_file ne "<NONE>" || $iso_file ) {
            $device_cdrom = $iso_file;
        }
    }

    $device_cdrom  =$self->_iso_name($iso, $args{request})
    if !$device_cdrom && $iso->{has_cd};
    
    #if ((not exists $args{iso_file}) || ((exists $args{iso_file}) && ($args{iso_file} eq "<NONE>"))) {
    #    $device_cdrom = $self->_iso_name($iso, $args{request});
    #}
    #else {
    #    $device_cdrom = $args{iso_file};
    #}
    
    my $disk_size;
    $disk_size = $args{disk} if $args{disk};

    my $file_xml =  $DIR_XML."/".$iso->{xml_volume};

    my $xml = $self->_define_xml($args{name} , "$DIR_XML/$iso->{xml}", $options);

    _xml_remove_cdrom_device($xml);
    _xml_remove_cpu($xml)                     if $remove_cpu;
    _xml_remove_disk($xml);
    $self->_xml_modify_usb($xml);
    _xml_modify_video($xml);

    my ($domain, $spice_password)
        = $self->_domain_create_common($xml,%args);
    $domain->_insert_db(name=> $args{name}, id_owner => $args{id_owner}
        , id_vm => $self->id
    );
    $domain->add_volume( boot => 1, target => 'vda', size => $disk_size );
    $domain->add_volume( boot => 2, target => 'hda'
        ,device => 'cdrom'
        ,file => $device_cdrom
    ) if $device_cdrom && $device_cdrom ne '<NONE>';

    $domain->_set_spice_password($spice_password)
        if $spice_password;
    $domain->xml_description();

    return $domain;
}

sub _domain_create_common {
    my $self = shift;
    my $xml = shift;
    my %args = @_;

    my $id_owner = delete $args{id_owner} or confess "ERROR: The id_owner is mandatory";
    my $is_volatile = delete $args{is_volatile};
    my $listen_ip = delete $args{listen_ip};
    my $spice_password = delete $args{spice_password};
    my $user = Ravada::Auth::SQL->search_by_id($id_owner)
        or confess "ERROR: User id $id_owner doesn't exist";

    $self->_xml_modify_memory($xml,$args{memory})   if $args{memory};
    $self->_xml_modify_network($xml , $args{network})   if $args{network};
    $self->_xml_modify_mac($xml);
    my $uuid = $self->_xml_modify_uuid($xml);

    my ($graphics) = $xml->findnodes("/domain/devices/graphics");
    $self->_xml_modify_spice_port($xml, $spice_password, $listen_ip)
    if $graphics && ($spice_password || $listen_ip);

    $self->_fix_pci_slots($xml);
    $self->_xml_add_guest_agent($xml);
    $self->_xml_clean_machine_type($xml) if !$self->is_local;
    $self->_xml_add_sysinfo_entry($xml, hostname => $args{name});

    my $dom;

    for ( 1 .. 10 ) {
        eval {
            if ($user->is_temporary || $is_volatile ) {
                $dom = $self->vm->create_domain($xml->toString());
            } else {
                $dom = $self->vm->define_domain($xml->toString());
                $dom->create if $args{active};
            }
        };

        last if !$@;
        if ($@ =~ /libvirt error code: 9, .*already defined with uuid/) {
            $self->_xml_modify_uuid($xml);
        } elsif ($@ =~ /libvirt error code: 1, .* pool .* asynchronous/) {
            sleep 1;
        } else {
            last ;
        }
    }
    if ($@) {
        my $out;
		warn $self->name."\n".$@;
        my $name_out = "/var/tmp/$args{name}.xml";
        warn "Dumping $name_out";
        open $out,">",$name_out and do {
            print $out $xml->toString();
        };
        close $out;
        warn "$! $name_out" if !$out;
        confess $@;# if !$dom;
    }

    my $domain = Ravada::Domain::KVM->new(
              _vm => $self
         , domain => $dom
        , storage => $self->storage_pool
       , id_owner => $id_owner
    );
    return ($domain, $spice_password);
}

sub _create_disk {
    return _create_disk_qcow2(@_);
}

sub _create_disk_qcow2 {
    my $self = shift;
    my ($base, $name) = @_;

    confess "Missing base" if !$base;
    confess "Missing name" if !$name;

    my @files_out;

    for my $file_data ( $base->list_files_base_target ) {
        my ($file_base,$target) = @$file_data;
        my $vol_base = Ravada::Volume->new(
            file => $file_base
            ,is_base => 1
            ,vm => $self
        );
        my $clone = $vol_base->clone(name => "$name-$target");
        push @files_out,($clone->file);
    }
    return @files_out;

}

sub _random_name { return Ravada::Utils::random_name(@_); };

sub _search_domain_by_id {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domains WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    return $self->search_domain($row->{name});
}

sub _domain_create_from_config($self, %args) {
    my $config = delete $args{config};
    my $id = delete $args{id};
    my $xml = XML::LibXML->load_xml(string => $config);

    my $dom = $self->vm->define_domain($xml->toString());
    my $domain = Ravada::Domain::KVM->new(
              _vm => $self
         , domain => $dom
       , id_owner => $args{id_owner}
    );

    $domain->_insert_db(name=> $args{name}
        , id => $id
        , id_owner => $args{id_owner}
        , id_vm => $self->id
    );
    $domain->xml_description();
    return $domain;

}

sub _domain_create_from_base {
    my $self = shift;
    my %args = @_;

    confess "argument id_base or base required ".Dumper(\%args)
        if !$args{id_base} && !$args{base};

    confess "Domain $args{name} already exists"
        if $self->search_domain($args{name});

    my $base = $args{base};
    my $with_cd = delete $args{with_cd};

    my $vm_local = $self;
    $vm_local = $self->new( host => 'localhost') if !$vm_local->is_local;
    $base = $vm_local->_search_domain_by_id($args{id_base}) if $args{id_base};
    confess "Unknown base id: $args{id_base}" if !$base;

    my $vm = $self->vm;
    my $storage = $self->storage_pool;

    my $xml = XML::LibXML->load_xml(string => $base->get_xml_base());


    my @device_disk = $self->_create_disk($base, $args{name});
    if ( !defined $with_cd ) {
        $with_cd = grep (/\.iso$/ ,@device_disk);
    }
    _xml_remove_cdrom($xml) if !$with_cd;
    _xml_remove_hostdev($xml);
    my ($node_name) = $xml->findnodes('/domain/name/text()');
    $node_name->setData($args{name});

    _xml_modify_disk($xml, \@device_disk);#, \@swap_disk);

    my ($domain, $spice_password)
        = $self->_domain_create_common($xml,%args, is_volatile => $base->volatile_clones);
    $domain->_insert_db(name=> $args{name}, id_base => $base->id, id_owner => $args{id_owner}
        , id_vm => $self->id
    );
    $domain->_set_spice_password($spice_password);
    $domain->xml_description();
    return $domain;
}

sub _fix_pci_slots {
    my $self = shift;
    my $doc = shift;

    my %dupe = ("0x01/0x1" => 1); #reserved por IDE PCI
    my ($all_devices) = $doc->findnodes('/domain/devices');

    for my $dev ($all_devices->findnodes('*')) {

        # skip IDE PCI, reserved before
        next if $dev->getAttribute('type')
            && $dev->getAttribute('type') =~ /^(ide)$/i;

#        warn "finding address of type ".$dev->getAttribute('type')."\n";

        for my $child ($dev->findnodes('address')) {
            my $bus = $child->getAttribute('bus');
            my $slot = ($child->getAttribute('slot') or '');
            my $function = ($child->getAttribute('function') or '');
            my $multifunction = $child->getAttribute('multifunction');

            my $index = "$bus/$slot/$function";

            next if !defined $slot;

            if (!$dupe{$index} || ($multifunction && $multifunction eq 'on') ) {
                $dupe{$index} = $dev->toString();
                next;
            }

            my $new_slot = $slot;
            for (;;) {
                last if !$dupe{"$bus/$new_slot/$function"};
                my ($n) = $new_slot =~ m{x(\d+)};
                $n++;
                $n= "0$n" if length($n)<2;
                $new_slot="0x$n";
            }
            $dupe{"$bus/$new_slot/$function"}++;
            $child->setAttribute(slot => $new_slot);
        }
    }

}

sub _set_iso_downloading($self, $iso,$value) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE iso_images SET downloading=?"
        ." WHERE id=?"
    );
    $sth->execute($value,$iso->{id});
}

sub _iso_name($self, $iso, $req=undef, $verbose=1) {

    return '' if !$iso->{has_cd};
    my $iso_name;
    if ($iso->{rename_file}) {
        $iso_name = $iso->{rename_file};
    } else {
        ($iso_name) = $iso->{url} =~ m{.*/(.*)} if $iso->{url};
        ($iso_name) = $iso->{device} if !$iso_name;
    }

    confess "Unknown iso_name for ".Dumper($iso)    if !$iso_name;

    my $device = ($iso->{device} or $self->dir_img."/$iso_name");

    warn "Missing MD5 and SHA256 field on table iso_images FOR $iso->{url}"
        if $VERIFY_ISO && $iso->{url} && !$iso->{md5} && !$iso->{sha256};

    my $downloaded = 0;
    my $test = 0;
    $test = 1 if $req && $req->defined_arg('test');

    if ($test || ! -e $device || ! -s $device) {
        $req->status("downloading $iso_name file"
                ,"Downloading ISO file for $iso_name "
                 ." from $iso->{url}. It may take several minutes"
        )   if $req;
        _fill_url($iso);

        $self->_set_iso_downloading($iso,1);
        my $url = $self->_download_file_external($iso->{url}, $device, $verbose, $test);
        $self->_set_iso_downloading($iso,0);
        $req->output($url) if $req;
        $self->_refresh_storage_pools();
        die "Download failed, file $device missing.\n"
            if !$test && ! -e $device;

        my $verified = 0;
        for my $check ( qw(md5 sha256)) {
            if (!$iso->{$check} && $iso->{"${check}_url"}) {
                my ($url_path,$url_file);
                if ( $url =~ m{/$} ) {
                    $url_path = $url;
                    $url_file = $iso->{filename};
                } else {
                    ($url_path,$url_file) = $url =~ m{(.*)/(.+)};
                }
                $iso->{"${check}_url"} =~ s/(.*)\$url(.*)/$1$url_path$2/;
                $self->_fetch_this($iso,$check,$url_file);
            }
            next if !$iso->{$check};
            next if $test;

            die "Download failed, $check id=$iso->{id} missmatched for $device."
            ." Please read ISO "
            ." verification missmatch at operation docs.\n"
            if (! _check_signature($device, $check, $iso->{$check}));
            $verified++;
        }
        return if $test;
        die "WARNING: $device signature not verified ".Dumper($iso)    if !$verified;

        $req->status("done","File $iso->{filename} downloaded") if $req;
        $downloaded = 1;
    }
    if ($downloaded || !$iso->{device} ) {
        my $sth = $$CONNECTOR->dbh->prepare(
                "UPDATE iso_images SET device=? WHERE id=?"
        );
        $sth->execute($device,$iso->{id});
    }
    $self->_refresh_storage_pools();
    return $device;
}

sub _fill_url($iso) {
    return if $iso->{url} =~ m{.*/[^/]+\.[^/]+$};
    if ($iso->{file_re}) {
        $iso->{url} .= "/" if $iso->{url} !~ m{/$};
        $iso->{url} .= $iso->{file_re};
        $iso->{filename} = '';
        return;
    }
    confess "Error: Missing field file_re for ".$iso->{name};
}

sub _check_md5 {
    my ($file, $md5 ) =@_;
    return if !$md5;

    my  $ctx = Digest::MD5->new;
    open my $in,'<',$file or die "$! $file";
    $ctx->addfile($in);

    my $digest = $ctx->hexdigest;

    return 1 if $digest eq $md5;

    warn "$file MD5 fails\n"
        ." got  : $digest\n"
        ."expecting: $md5\n"
        ;
    return 0;
}

sub _check_sha256($file,$sha) {
    return if !$sha;
    confess "Wrong SHA256 '$sha'" if $sha !~ /[a-f0-9]{9}/;

    my @cmd = ('sha256sum',$file);
    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    die "$err ".join(@cmd)  if $err;

    my ($digest) =  $out =~ m{([0-9a-f]+)};

    return 1 if $digest eq $sha;

    warn "$file SHA256 fails\n"
        ." got  : $digest\n"
        ."expecting: $sha\n"
        ;
    return 0;
}


sub _check_signature($file, $type, $expected) {
    confess "ERROR: Wrong signature '$expected'"
        if $expected !~ /^[0-9a-f]{7}/;
    return _check_md5($file,$expected) if $type =~ /md5/i;
    return _check_sha256($file,$expected) if $type =~ /sha256/i;
    die "Unknown signature type $type";
}

sub _download_file_external_headers($self,$url) {
    my @cmd = ($WGET,"-S","--spider",$url);

    my ($in,$out,$err) = @_;
    run3(\@cmd,\$in,\$out,\$err);
    my ($status) = $err =~ /^\s*(HTTP.*\d+.*)/m;

    return $url if $status =~ /(200|301|302|307) ([\w\s]+)$/;
    # 200: OK
    # 302: redirect
    # 307: temporary redirect
    die "Error: $url not found $status";
}

sub _download_file_external($self, $url, $device, $verbose=1, $test=0) {
    $url .= "/" if $url !~ m{/$} && $url !~ m{.*/([^/]+\.[^/]+)$};
    if ($url =~ m{[^*]}) {
        my @found = $self->_search_url_file($url);
        die "Error: URL not found '$url'" if !scalar @found;
        $url = $found[-1];
    }
    if ( $url =~ m{/$} ) {
        my ($filename) = $device =~ m{.*/(.*)};
        $url = "$url$filename";
    }
    confess "ERROR: wget missing"   if !$WGET;

    $url =~ s{/./}{/}g;
    return $self->_download_file_external_headers($url)    if $test;
    return $url if -e $device;

    my @cmd = ($WGET,'-nv',$url,'-O',$device);
    my ($in,$out,$err) = @_;
    warn join(" ",@cmd)."\n"    if $verbose;
    run3(\@cmd,\$in,\$out,\$err);
    warn "out=$out" if $out && $verbose;
    warn "err=$err" if $err && $verbose;
    print $out if $out;
    chmod 0755,$device or die "$! chmod 0755 $device"
        if -e $device;

    return $url if !$err;

    if ($err && $err =~ m{\[(\d+)/(\d+)\]}) {
        if ( $1 != $2 ) {
            unlink $device or die "$! $device" if -e $device;
            die "ERROR: Expecting $1 , got $2.\n$err"
        }
        return $url;
    }
    unlink $device or die "$! $device" if -e $device;
    die $err;
}

sub _search_iso($self, $id_iso, $file_iso=undef) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM iso_images WHERE id = ?");
    $sth->execute($id_iso);
    my $row = $sth->fetchrow_hashref;
    $row->{options} = decode_json($row->{options})
    if $row->{options} && !ref($row->{options});
    die "Missing iso_image id=$id_iso" if !keys %$row;

    return $row if $file_iso && -e $file_iso;

    if ( $row->{device} && -e $row->{device} ) {
        ($row->{filename}) = $row->{device} =~ m{.*/(.*)};
    }
    $self->_fetch_filename($row);#    if $row->{file_re};
    if ($VERIFY_ISO) {
        $self->_fetch_md5($row)         if !$row->{md5} && $row->{md5_url};
        $self->_fetch_sha256($row)         if !$row->{sha256} && $row->{sha256_url};
    }

    if ( !$row->{device} && $row->{filename}) {
        if (my $volume = $self->search_volume_re(qr("^".$row->{filename}))) {
            $row->{device} = $volume->get_path;
            my $sth = $$CONNECTOR->dbh->prepare(
                "UPDATE iso_images SET device=? WHERE id=?"
            );
            $sth->execute($volume->get_path, $row->{id});
        }
    }
    my $rename_file = $row->{rename_file};

    return $row;
}

sub _download($self, $url) {
    $url =~ s{(http://.*)//(.*)}{$1/$2};
    if ($url =~ m{[^*]}) {
        my @found = $self->_search_url_file($url);
        die "Error: URL not found '$url'" if !scalar @found;
        $url = $found[-1];
    }

    my $cache;
    $cache = $self->_cache_get($url) if $CACHE_DOWNLOAD;# && $url !~ m{^http.?://localhost};
    return $cache if $cache;

    my $ua = $self->_web_user_agent();
    my $res;
    for ( 1 .. 10 ) {
        eval { $res = $ua->get($url)->res};
        last if $res;
    }
    die $@ if $@;
    confess "ERROR ".$res->code." ".$res->message." : $url"
        unless $res->code == 200 || $res->code == 301 || $res->code == 302;

    return $self->_cache_store($url,$res->body);
}

sub _match_url($self,$url) {
    return $url if $url !~ m{\*|\+};

    my ($url1, $match,$url2) = $url =~ m{(.*/)([^/]*[*+][^/]*)/?(.*)};
    $url2 = '' if !$url2;

    confess "No url1 from $url" if !defined $url1;
    my $dom = $self->_ua_get($url1);
    my @found;
    my $links = $dom->find('a')->map( attr => 'href');
    for my $link (@$links) {
        next if !defined $link;
        $link =~ s{/$}{};
        next if $link !~ qr($match);
        my $new_url = "$url1$link/$url2";
        push @found,($self->_match_url($new_url));
    }
    return @found;
}

sub _ua_get($self, $url) {
    my $cache = $self->_cache_get($url);
    if ( $cache ) {
        my $dom = Mojo::DOM->new($cache);
        return $dom;
    }
    my ($ip) = $url =~ m{://(.*?)[:/]};
    sleep 1 if !$ip || $self->{_url_get}->{$ip};
    my $ua = $self->_web_user_agent();
    my $res;
    for my $try ( 1 .. 3 ) {
        $res = $ua->get($url)->res;
        last if $res && defined $res->code;
        sleep 1+$try;
    }
    confess "Error getting '$url'" if !$res;

    if (!defined $res->code || !($res->code == 200 || $res->code == 301)) {
        my $msg = "Error getting '$url'";
        $msg .= " ".$res->code if defined $res->code;
        $msg .= " ".$res->message if defined $res->message;
        die "$msg\n";
    }

    $self->_cache_store($url,$res->body);
    return $res->dom;

}

sub _cache_get($self, $url) {
    my $file = _cache_filename($url);

    my @stat = stat($file)  or return;
    return if time-$stat[9] > 600;
    open my $in ,'<' , $file or return;
    return join("",<$in>);
}

sub _cache_store($self, $url, $content) {

    my $file = _cache_filename($url);
    open my $out ,'>' , $file or die "$! $file";
    print $out $content;
    close $out;
    return $content;

}

sub _cache_filename($url) {
    confess "Undefined url" if !$url;

    my $file = $url;

    $file =~ tr{/:}{_-};
    $file =~ tr{a-zA-Z0-9_-}{_}c;
    $file =~ s/__+/_/g;

    my ($user) = getpwuid($>);
    my $dir = "/var/tmp/$user/ravada_cache/";
    make_path($dir)    if ! -e $dir;
    return "$dir/$file";
}

sub _fetch_filename {
    my $self = shift;
    my $row = shift;

    if (!$row->{file_re} && !$row->{url} && $row->{device}) {
         my ($file) = $row->{device} =~ m{.*/(.*)};
         $row->{filename} = $file;
         return;
    }
    return if !$row->{file_re} && !$row->{url} && !$row->{device};
    if (!$row->{file_re}) {
        my ($new_url, $file);
        ($new_url, $file) = $row->{url} =~ m{(.*)/(.*)} if $row->{url};
        ($file) = $row->{device} =~ m{.*/(.*)}
            if !$file && $row->{device};
        confess "No filename in $row->{name} $row->{url}" if !$file;

        $row->{url} = $new_url;
        $row->{file_re} = "^$file";
    }
    confess "No file_re" if !$row->{file_re};
    $row->{file_re} .= '$'  if $row->{file_re} !~ m{\$$};

    my @found;
    if ($row->{rename_file}) {
        @found = $self->search_volume_re(qr("^".$row->{rename_file}));
    } else {
        @found = $self->search_volume_re(qr($row->{file_re}));
    }
    if (@found) {
        $row->{device} = $found[0]->get_path;
        ($row->{filename}) = $found[0]->get_path =~ m{.*/(.*)};
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE iso_images SET device=?"
            ." WHERE id=?"
        );
        $sth->execute($row->{device}, $row->{id});
        return;
    } else {
        @found = $self->_search_url_file($row->{url}, $row->{file_re}) if !@found;
        die "No ".qr($row->{file_re})." found on $row->{url}" if !@found;
    }

    my $url = $found[-1];
    my ($file) = $url =~ m{.*/(.*)};

    $row->{url} = $url;
    $row->{filename} = ($row->{rename_file} or $file);

#    $row->{url} .= "/" if $row->{url} !~ m{/$};
#    $row->{url} .= $file;
}

sub _search_url_file($self, $url_re, $file_re=undef) {

    if (!$file_re) {
        my $old_url_re = $url_re;
        ($url_re, $file_re) = $old_url_re =~ m{(.*)/(.*)};
        confess "ERROR: Missing file part in $old_url_re"
            if !$file_re;
        if ($url_re =~ /\.\.$/) {
            $url_re =~ s{(.*)/.*/\.\.$}{$1};
        }
    }

    $file_re .= '$' if $file_re !~ m{\$$};
    my @found;
    for my $url ($self->_match_url($url_re)) {
        my @file = $self->_match_file($url, $file_re);
        push @found, @file if scalar @file;
    }
    return (sort @found);
}
sub _web_user_agent($self) {

    my $ua = Mojo::UserAgent->new();

    $ua->max_redirects(3);
    $ua->proxy->detect;

    return $ua;
}

sub _match_file($self, $url, $file_re) {

    $url .= '/' if $url !~ m{/$};

    my $dom = $self->_ua_get($url);
    return if !$dom;

    my @found;

    my $links = $dom->find('a')->map( attr => 'href');
    for my $link (@$links) {
        next if !defined $link || $link !~ qr($file_re);
        push @found, ($url.$link);
    }
    return @found;
}

sub _fetch_this($self, $row, $type, $file = $row->{filename}){

    confess "Error: missing file or filename ".Dumper($row) if !$file;

    $file=~ s{.*/(.+)}{$1} if $file =~ m{/} && $file !~ m{/$};

    my ($url, $file2) = $row->{url} =~ m{(.*)/(.+)};
    $url = $row->{url} if $row->{url} =~ m{/$};
    my $url_orig = $row->{"${type}_url"};
    $file = $file2 if $file2 && $file2 !~ /\*|\^/ && $file2 !~ m{/$};

    $url_orig =~ s{(.*)\$url(.*)}{$1$url$2}  if $url_orig =~ /\$url/;

    confess "error: file missing '$file' ".Dumper($row) if $file =~ m{/$};
    confess "error " if $url_orig =~ /\$/;

    my $content = $self->_download($url_orig);

    for my $line (split/\n/,$content) {
        next if $line =~ /^#/;
        my $value;
        ($value) = $line =~ m{$file.* ([a-f0-9]+)}i       if !$value;
        ($value) = $line =~ m{\s*([a-f0-9]+).*$file}i     if !$value;
        ($value) = $line =~ m{$file.* ([a-f0-9]+)}i       if !$value;
        ($value) = $line =~ m{$file.* ([a-f0-9]+)}i       if !$value;
        ($value) = $line =~ m{^\s*([a-f0-9]+)\s+.*?$file} if !$value;
        if ($value) {
            $row->{$type} = $value;
            my $sth = $$CONNECTOR->dbh->prepare("UPDATE iso_images set $type = ? "
                                                ." WHERE id = ? ");
                                            $sth->execute($value, $row->{id});
            return $value;
        }
    }

    warn "No $type for $file in ".$row->{"${type}_url"}."\n"
        .$url_orig."\n"
        .$content;

    return;
}

sub _fetch_md5($self,$row) {
    my $signature = $self->_fetch_this($row,'md5');
    die "ERROR: Wrong signature '$signature'"
         if $signature !~ /^[0-9a-f]{9}/;
    return $signature;
}


sub _fetch_sha256($self,$row) {
    my $signature = $self->_fetch_this($row,'sha256');
    confess "ERROR: Wrong signature '$signature'"
         if defined $signature && $signature !~ /^[0-9a-f]{9}/;
    return $signature;
}

###################################################################################
#
# XML methods
#

sub _define_xml($self, $name, $xml_source, $options=undef) {
    my $doc = $XML->parse_file($xml_source) or die "ERROR: $! $xml_source\n";

        my ($node_name) = $doc->findnodes('/domain/name/text()');
    $node_name->setData($name);

    $self->_xml_modify_mac($doc);
    $self->_xml_modify_uuid($doc);
    $self->_xml_modify_spice_port($doc);
    _xml_modify_video($doc);
    $self->_xml_modify_options($doc, $options);

    return $doc;

}

sub _xml_modify_options($self, $doc, $options=undef) {
    return if !$options || !scalar(keys (%$options));
    my $uefi = delete $options->{uefi};
    my $machine = delete $options->{machine};
    my $arch = delete $options->{arch};
    my $bios = delete $options->{'bios'};
    confess "Error: bios=$bios and uefi=$uefi clash"
    if defined $uefi && defined $bios
        && ($bios !~/uefi/i && $uefi || $bios =~/uefi/i && !$uefi);

    $uefi = 1 if $bios && $bios =~ /uefi/i;

    confess "Arguments unknown ".Dumper($options)  if keys %$options;
    if ($machine) {
        $self->_xml_set_machine($doc, $machine);
    }
    if ($arch) {
        $self->_xml_set_arch($doc, $arch);
    }
    if ( $uefi ) {
        #        $self->_xml_add_libosinfo_win2k16($doc);
        my ($xml_name) = $doc->findnodes('/domain/name');
        $self->_xml_add_uefi($doc, $xml_name->textContent);
    }
    my ($type) = $doc->findnodes('/domain/os/type');

    my $machine_found = $type->getAttribute('machine');
    if ($machine_found =~ /pc-i440fx/ && !$uefi) {
        $self->_xml_remove_vmport($doc);
        $self->_xml_remove_ide($doc);
    }
    if ($machine_found =~ /q35/ ) {
        $self->_xml_set_pcie($doc);
        $self->_xml_remove_ide($doc);
        $self->_xml_remove_vmport($doc);
    } else {
        $self->_xml_set_pci_noe($doc);
    }

}

sub _xml_set_arch($self, $doc, $arch) {
    my ($type) = $doc->findnodes('/domain/os/type');
    $type->setAttribute(arch => $arch);
}



sub _xml_set_machine($self, $doc, $machine) {
    my ($type) = $doc->findnodes('/domain/os/type');
    $type->setAttribute(machine => $machine);
}

sub _xml_remove_ide($self, $doc) {
    my ($devices) = $doc->findnodes("/domain/devices");
    for my $controller ($doc->findnodes("/domain/devices/controller")) {
        next if $controller->getAttribute('type') ne 'ide';
        $devices->removeChild($controller);
    }
    for my $disk ($doc->findnodes("/domain/devices/disk")) {
        my ($target) = $disk->findnodes("target");
        $target->setAttribute('bus' => 'sata') if $target->getAttribute('bus') eq 'ide';

        my ($address) = $disk->findnodes("address");
        $disk->removeChild($address);
    }

}

sub _xml_remove_vmport($self, $doc) {
    my ($features) = $doc->findnodes("/domain/features");
    my ($vmport) = $features->findnodes("vmport");
    return if !$vmport;
    $features->removeChild($vmport);
}


sub _xml_set_pcie($self, $doc) {
    for my $controller ($doc->findnodes("/domain/devices/controller")) {
        next if $controller->getAttribute('type') ne 'pci';
        $controller->setAttribute('model' => 'pcie-root');
    }
}

sub _xml_set_pci_noe($self, $doc) {
    my $changed = 0;
    for my $controller ($doc->findnodes("/domain/devices/controller")) {
        next if $controller->getAttribute('type') ne 'pci';

        $controller->setAttribute('model' => 'pci-root')
        if $controller->getAttribute('model') eq 'pcie-root';

        $changed++;
    }

    return if !$changed;
    my %slot;
    for my $address ($doc->findnodes("/domain/devices/*/address")) {
        next if $address->getAttribute('type') ne'pci';
        my ($n) = $address->getAttribute('slot') =~ /0x0*(\d+)/;
        $slot{$n}++;
    }

    my $n = 2;
    for my $address ($doc->findnodes("/domain/devices/*/address")) {
        next if $address->getAttribute('type') ne'pci';
        next if $address->getAttribute('slot') !~ /^0x00+$/;

        my $new_slot = "0x0$n";
        for (;;) {
            $new_slot = "0x0$n";
            last if !$slot{$n}++;
            $n++;
        }
        $address->setAttribute('slot' => $new_slot);
    }

    # video can't be 0x00 nor 0x01
    for my $address ($doc->findnodes("/domain/devices/video/address")) {
        next if $address->getAttribute('type') ne'pci';
        next if $address->getAttribute('slot') !~ /^0x0*(0|1)$/;
        my $new_slot = "0x0$n";
        for (;;) {
            $new_slot = "0x0$n";
            last if !$slot{$n}++;
            $n++;
        }
        $address->setAttribute('slot' => $new_slot);
    }

}


sub _xml_add_libosinfo_win2k16($self, $doc) {
    my ($domain) = $doc->findnodes('/domain');
    my ($metadata) = $domain->findnodes('metadata');
    if (!$metadata) {
        $metadata = $domain->addNewChild(undef,"metadata");
    }
    my $libosinfo = $metadata->addNewChild(undef,'libosinfo:libosinfo');
    $libosinfo->setAttribute('xmlns:libosinfo' =>
        "http://libosinfo.org/xmlns/libvirt/domain/1.0"
    );
    my $os = $libosinfo->addNewChild(undef, 'libosinfo:os');
    $os->setAttribute('id' => "http://microsoft.com/win/2k16" );

}

sub _xml_add_uefi($self, $doc, $name) {
    my ($os) = $doc->findnodes('/domain/os');
    my ($loader) = $doc->findnodes('/domain/os/loader');
    if (!$loader) {
        $loader= $os->addNewChild(undef,"loader");
    }
    $loader->setAttribute('readonly' => 'yes');
    $loader->setAttribute('type' => 'pflash');

    my $ovmf = '/usr/share/OVMF/OVMF_CODE.fd';

    my ($type) = $doc->findnodes('/domain/os/type');
    if ($type->getAttribute('arch') =~ /x86_64/
            && $type->getAttribute('machine') =~ /pc-q35/) {
        $ovmf = '/usr/share/OVMF/OVMF_CODE_4M.fd';
    }
    my ($text) = $loader->findnodes("text()");
    if ($text) {
        $text->setData($ovmf);
    } else {
        $loader->appendText($ovmf);
    }

    my ($nvram) =$doc->findnodes("/domain/os/nvram");
    if (!$nvram) {
        $nvram = $os->addNewChild(undef,"nvram");
    }
    $nvram->appendText("/var/lib/libvirt/qemu/nvram/$name.fd");
}

sub _xml_remove_cpu {
    my $doc = shift;
    my ($domain) = $doc->findnodes('/domain') or confess "Missing node domain";
    my ($cpu) = $domain->findnodes('cpu');
    $domain->removeChild($cpu)  if $cpu;
}

sub _xml_remove_disk($doc){
    my ($dev) = $doc->findnodes('/domain/devices')
        or confess "Missing node domain/devices";
    for my $disk ( $dev->findnodes('disk') ) {
        $dev->removeChild($disk)
            if $disk && $disk->getAttribute('device') eq 'disk';
    }
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

    return if $video->getAttribute('type') eq 'qxl';

    $video->setAttribute(type => 'qxl');
    $video->setAttribute( ram => 65536 );
    $video->setAttribute( vram => 65536 );
    $video->setAttribute( vgamem => 16384 );
    $video->setAttribute( heads => 1 );

    warn "WARNING: more than one video card found\n".
        $video->toString().$video2->toString()  if $video2;

}

sub _xml_modify_spice_port($self, $doc, $password=undef, $listen_ip=$self->listen_ip) {

    $listen_ip = $self->listen_ip if !defined $listen_ip;
    my ($graph) = $doc->findnodes('/domain/devices/graphics')
        or confess "ERROR: I can't find graphics in ".$self->name;
    #$graph->setAttribute(type => 'spice');
    $graph->setAttribute(autoport => 'yes');
    $graph->setAttribute(listen=> $listen_ip );
    $graph->setAttribute(passwd => $password)    if $password;

    my ($listen) = $doc->findnodes('/domain/devices/graphics/listen');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"listen");
    }

    $listen->setAttribute(type => 'address');
    $listen->setAttribute(address => $listen_ip);
}

sub _xml_modify_uuid {
    my $self = shift;
    my $doc = shift;
    my ($uuid) = $doc->findnodes('/domain/uuid/text()');

    my $new_uuid = $self->_unique_uuid($uuid);
    $uuid->setData($new_uuid);

    return $new_uuid;
}

sub _unique_uuid($self, $uuid='1805fb4f-ca45-aaaa-bbbb-94124e760434',@) {
    my @uuids = @_;
    if (!scalar @uuids) {
        for my $dom ($self->vm->list_all_domains) {
            eval { push @uuids,($dom->get_uuid_string) };
            confess $@ if $@ && $@ !~ /^libvirt error code: 42,/;
        }
    }
    my ($pre,$first,$last) = $uuid =~ m{^([0-9a0-f]{6})(.*)([0-9a-f]{6})$};
    confess "I can't split model uuid '$uuid'" if !$first;

    for my $domain ($self->vm->list_all_domains) {
        eval { push @uuids,($domain->get_uuid_string) };
        confess $@ if $@ && $@ !~ /^libvirt error code: 42,/;
    }

    for (1..100) {
        my $new_pre = '';
        $new_pre = sprintf("%x",int(rand(0x10))).$new_pre while length($new_pre)<6;

        my $new_last = '';
        $new_last = sprintf("%x",int(rand(0x10))).$new_last while length($new_last)<6;

        my $new_uuid = "$new_pre$first$new_last";
        die "Wrong length ".length($new_uuid)." should be ".length($uuid)
            ."\n"
            .$new_uuid
            ."\n"
            .$uuid
        if length($new_uuid) != length($uuid);

        return $new_uuid if !grep /^$new_uuid$/,@uuids;
    }
    confess "I can't find a new unique uuid";
}

sub _xml_modify_memory {
    my $self = shift;
     my $doc = shift;
  my $memory = shift;

    my $found++;
    my ($mem) = $doc->findnodes('/domain/currentMemory/text()');
    $mem->setData($memory);

    ($mem) = $doc->findnodes('/domain/memory/text()');
    $mem->setData($memory);

}

sub _xml_modify_network {
    my $self = shift;
     my $doc = shift;
    my $network = shift;

    my ($type, $source );
    if (ref($network) =~ /^Ravada/) {
        ($type, $source) = ($network->type , $network->source);
    } else {
        $network = decode_json($network);
        ($type, $source) = ($network->{type} , $network->{source});
    }

    confess "Unknown network type " if !defined $type;
    confess "Unknown network xml_source" if !defined $source;

    my @interfaces = $doc->findnodes('/domain/devices/interface');
    if (scalar @interfaces>1) {
        warn "WARNING: ".scalar @interfaces." found, changing the first one";
    }
    my $if = $interfaces[0];
    $if->setAttribute(type => $type);

    my ($node_source) = $if->findnodes('./source');
    $node_source->removeAttribute('network');
    for my $field (keys %$source) {
        $node_source->setAttribute($field => $source->{$field});
    }
}

sub _xml_modify_usb {
    my $self = shift;
     my $doc = shift;

    my ($devices) = $doc->findnodes('/domain/devices');

    $self->_xml_remove_usb($devices);
    $self->_xml_add_usb_xhci($devices);

#    $self->_xml_add_usb_ehci1($devices);
#    $self->_xml_add_usb_uhci1($devices);
#    $self->_xml_add_usb_uhci2($devices);
#    $self->_xml_add_usb_uhci3($devices);

    my $num_usb = 3;
    $self->_xml_add_usb_redirect($devices, $num_usb);

}

sub _xml_add_usb_redirect {
    my $self = shift;
    my $devices = shift;
    my $items = shift;

    my $dev=_search_xml(
          xml => $devices
        ,name => 'redirdev'
        , bus => 'usb'
        ,type => 'spicevmc'
    );
    $items = $items - 1 if $dev;
    
    for (my $var = 0; $var < $items; $var++) {
        $dev = $devices->addNewChild(undef,'redirdev');
        $dev->setAttribute( bus => 'usb');
        $dev->setAttribute(type => 'spicevmc');
    }

}

sub _search_xml {
    my %arg = @_;

    my $name = $arg{name};
    delete $arg{name};
    my $xml = $arg{xml};
    delete $arg{xml};

    confess "Undefined xml => \$xml"
        if !$xml;

    for my $item ( $xml->findnodes($name) ) {
        my $missing = 0;
        for my $attr( sort keys %arg ) {
           $missing++

                if !$item->getAttribute($attr)
                    || $item->getAttribute($attr) ne $arg{$attr}
        }
        return $item if !$missing;
    }
    return;
}

sub _xml_remove_usb {
    my $self = shift;
    my $doc = shift;

    my ($devices) = $doc->findnodes("/domain/devices");
    for my $usb ($devices->findnodes("controller")) {
        next if $usb->getAttribute('type') ne 'usb';
        $devices->removeChild($usb);
    }
}

sub _xml_add_usb_xhci($self, $devices, $model='qemu-xhci') {
    my $ctrl = _search_xml(
                           xml => $devices
                         ,name => 'controller'
                         ,type => 'usb'
                         ,model => $model
        );
    return if $ctrl;
    my $controller = $devices->addNewChild(undef,"controller");
    $controller->setAttribute(type => 'usb');
    $controller->setAttribute(index => '0');
    $controller->setAttribute(model => $model);

    my $address = $controller->addNewChild(undef,'address');
    $address->setAttribute(type => 'pci');
    $address->setAttribute(domain => '0x0000');
    $address->setAttribute(bus => '0x00');
    $address->setAttribute(slot => '0x07');
    $address->setAttribute(function => '0x0');
}

sub _xml_add_usb_ehci1 {

    my $self = shift;
    my $devices = shift;

    my $model = 'ich9-ehci1';
    my $ctrl_found = _search_xml(
                           xml => $devices
                         ,name => 'controller'
                         ,type => 'usb'
                         ,model => $model
        );
    if ($ctrl_found) {
#        warn "$model found \n".$ctrl->toString."\n";
        return;
    }
    for my $ctrl ($devices->findnodes('controller')) {
        next if $ctrl->getAttribute('type') ne 'usb';
        next if $ctrl->getAttribute('model')
                && $ctrl->getAttribute('model') eq $model;

        $ctrl->setAttribute(model => $model);

        for my $child ($ctrl->childNodes) {
            if ($child->nodeName eq 'address') {
                $child->setAttribute(slot => '0x08');
                $child->setAttribute(function => '0x7');
            }
        }
    }


}

sub _xml_add_usb_uhci1 {
    my $self = shift;
    my $devices = shift;

    return if _search_xml(
                           xml => $devices
                         ,name => 'controller'
                         ,type => 'usb'
                         ,model => 'ich9-uhci1'
    );
    # USB uhci1
    my $controller = $devices->addNewChild(undef,"controller");
    $controller->setAttribute(type => 'usb');
    $controller->setAttribute(index => '0');
    $controller->setAttribute(model => 'ich9-uhci1');

    my $master = $controller->addNewChild(undef,'master');
    $master->setAttribute(startport => 0);

    my $address = $controller->addNewChild(undef,'address');
    $address->setAttribute(type => 'pci');
    $address->setAttribute(domain => '0x0000');
    $address->setAttribute(bus => '0x00');
    $address->setAttribute(slot => '0x08');
    $address->setAttribute(function => '0x0');
    $address->setAttribute(multifunction => 'on');
}

sub _xml_add_usb_uhci2 {
    my $self = shift;
    my $devices = shift;

    return if _search_xml(
                           xml => $devices
                         ,name => 'controller'
                         ,type => 'usb'
                         ,model => 'ich9-uhci2'
    );
    # USB uhci2
    my $controller = $devices->addNewChild(undef,"controller");
    $controller->setAttribute(type => 'usb');
    $controller->setAttribute(index => '0');
    $controller->setAttribute(model => 'ich9-uhci2');

    my $master = $controller->addNewChild(undef,'master');
    $master->setAttribute(startport => 2);

    my $address = $controller->addNewChild(undef,'address');
    $address->setAttribute(type => 'pci');
    $address->setAttribute(domain => '0x0000');
    $address->setAttribute(bus => '0x00');
    $address->setAttribute(slot => '0x08');
    $address->setAttribute(function => '0x1');
}

sub _xml_add_usb_uhci3 {
    my $self = shift;
    my $devices = shift;


    return if _search_xml(
                           xml => $devices
                         ,name => 'controller'
                         ,type => 'usb'
                         ,model => 'ich9-uhci3'
    );
    # USB uhci2
    my $controller = $devices->addNewChild(undef,"controller");
    $controller->setAttribute(type => 'usb');
    $controller->setAttribute(index => '0');
    $controller->setAttribute(model => 'ich9-uhci3');

    my $master = $controller->addNewChild(undef,'master');
    $master->setAttribute(startport => 4);

    my $address = $controller->addNewChild(undef,'address');
    $address->setAttribute(type => 'pci');
    $address->setAttribute(domain => '0x0000');
    $address->setAttribute(bus => '0x00');
    $address->setAttribute(slot => '0x08');
    $address->setAttribute(function => '0x2');

}

sub _xml_add_guest_agent {
    my $self = shift;
    my $doc = shift;
    
    my ($devices) = $doc->findnodes('/domain/devices');
    
    return if _search_xml(
                            xml => $devices
                            ,name => 'channel'
                            ,type => 'unix'
    );
    
    my $channel = $devices->addNewChild(undef,"channel");
    $channel->setAttribute(type => 'unix');
    
    my $source = $channel->addNewChild(undef,'source');
    $source->setAttribute(mode => 'bind');
    
    my $target = $channel->addNewChild(undef,'target');
    $target->setAttribute(type => 'virtio');
    $target->setAttribute(name => 'org.qemu.guest_agent.0');
    
}

sub _xml_clean_machine_type($self, $doc) {
    my ($os_type) = $doc->findnodes('/domain/os/type');
    $os_type->setAttribute( machine => 'pc');
}

sub _xml_add_sysinfo($self,$doc) {
    my ($smbios) = $doc->findnodes('/domain/os/smbios');
    if (!$smbios) {
        my ($os) = $doc->findnodes('/domain/os');
        $smbios = $os->addNewChild(undef,'smbios');
    }
    $smbios->setAttribute(mode => 'sysinfo');

}

sub _xml_add_sysinfo_entry($self, $doc, $field, $value) {
    $self->_xml_add_sysinfo($doc);
    my ($oemstrings) = $doc->findnodes('/domain/sysinfo/oemStrings');
    if (!$oemstrings) {
        my ($domain) = $doc->findnodes('/domain');
        my $sysinfo = $domain->addNewChild(undef,'sysinfo');
        $sysinfo->setAttribute( type => 'smbios' );
        $oemstrings = $sysinfo->addNewChild(undef,'oemStrings');
    }
    my @entries = $oemstrings->findnodes('entry');
    my $hostname;
    for (@entries) {
        $hostname = $_ if $_->textContent =~ /^$field/;
    }
    if ($hostname) {
        $oemstrings->removeChild($hostname);
    }
    ($hostname) = $oemstrings->addNewChild(undef,'entry');
    $hostname->appendText("$field: $value");
}
sub _xml_remove_hostdev {
    my $doc = shift;

    for my $devices ( $doc->findnodes('/domain/devices') ) {
        for my $node_hostdev ( $devices->findnodes('hostdev') ) {
            $devices->removeChild($node_hostdev);
        }
    }
}

sub _xml_remove_cdrom_device {
    my $doc = shift;

    my ($devices) = $doc->findnodes('/domain/devices');
    for my $disk ($devices->findnodes('disk')) {
        if ( $disk->nodeName eq 'disk'
            && $disk->getAttribute('device') eq 'cdrom') {
            $devices->removeChild($disk);
        }
    }
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
                    $context->removeChild($disk);
                }
            }
        }
    }
}

sub _xml_modify_disk {
  my $doc = shift;
  my $device = shift          or confess "Missing device";
  my $swap = shift;

  #  <source file="/var/export/vmimgs/ubuntu-mate.img" dev="/var/export/vmimgs/clone01.qcow2"/>

  my $cont = 0;
  my $cont_swap = 0;
  for my $disk ($doc->findnodes('/domain/devices/disk')) {

    for my $child ($disk->childNodes) {
        next if $disk->getAttribute('device') ne 'disk';
        if ($child->nodeName eq 'driver') {
            $child->setAttribute(type => 'qcow2');
        } elsif ($child->nodeName eq 'source') {
            my $new_device
                    = $device->[$cont] or confess "Missing device $cont "
                    .$child->toString."\n"
                    .Dumper($device);
            $cont++;
            $child->setAttribute(file => $new_device);
        }
    }
  }
}

sub _unique_mac {
    my $self = shift;

    my $mac = shift;

    $mac = lc($mac);

    for my $dom ($self->vm->list_all_domains) {
        my $doc;
        eval { $doc = $XML->load_xml(string => $dom->get_xml_description()) } ;
        next if !$doc;

        for my $nic ( $doc->findnodes('/domain/devices/interface/mac')) {
            my $nic_mac = $nic->getAttribute('address');
            if ( $mac eq lc($nic_mac) ) {
                return 0;
            }
        }
    }
    return 1;
}

sub _new_uuid {
    my $uuid = shift;

    my ($principi, $f1,$f2) = $uuid =~ /(.*)(.)(.)/;

    return $principi.int(rand(10)).int(rand(10));

}

sub _read_used_macs($self) {
    return if keys %USED_MAC;
    for my $dom ($self->vm->list_all_domains) {
        my $doc;
        eval { $doc = $XML->load_xml(string => $dom->get_xml_description()) } ;
        next if !$doc;

        for my $nic ( $doc->findnodes('/domain/devices/interface/mac')) {
            my $nic_mac = lc($nic->getAttribute('address'));
            $USED_MAC{$nic_mac}++;
        }
    }
}

sub _new_mac($self,$mac='52:54:00:a7:49:71') {

    $self->_read_used_macs();
    my @macparts = split/:/,$mac;
    $macparts[5] = sprintf"%02X",($$ % 254);

    my @tried;
    my $foundit;
    for ( 1 .. 1000 ) {
            my $pos = int(rand(scalar(@macparts)-3))+3;
            for ( 0 .. 2 ) {
                my $num =sprintf "%02X", rand(0xff);
                die "Missing num " if !defined $num;
                $macparts[$pos] = $num;
                $pos++;
                $pos = 3 if $pos>5;
            }
            my $new_mac = lc(join(":",@macparts));
            push @tried,($new_mac);

            return $new_mac if !$USED_MAC{$new_mac}++ && $self->_unique_mac($new_mac);
    }
    die "I can't find a new unique mac\n".Dumper(\@tried) if !$foundit;

}

sub _xml_modify_mac {
    my $self = shift;
    my $doc = shift or confess "Missing XML doc";

    for my $if_mac ($doc->findnodes('/domain/devices/interface/mac') ) {
        my $mac = $if_mac->getAttribute('address');

        my $new_mac = $self->_new_mac($mac);;
        $if_mac->setAttribute(address => $new_mac);
    }
}

=pod

sub xml_add_graphics_image {
    my $doc = shift or confess "Missing XML doc";

    my ($graph) = $doc->findnodes('/domain/devices/graphics')
        or die "ERROR: I can't find graphic";

    my ($listen) = $doc->findnodes('/domain/devices/graphics/image');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"image");
    }
    $listen->setAttribute(compression => 'auto_glz');
}

=cut

sub _xml_add_graphics_jpeg {
    my $self = shift;
    my $doc = shift or confess "Missing XML doc";

    my ($graph) = $doc->findnodes('/domain/devices/graphics')
        or die "ERROR: I can't find graphic";

    my ($listen) = $doc->findnodes('/domain/devices/graphics/jpeg');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"jpeg");
    }
    $listen->setAttribute(compression => 'auto');
}

sub _xml_add_graphics_zlib {
    my $self = shift;
    my $doc = shift or confess "Missing XML doc";

    my ($graph) = $doc->findnodes('/domain/devices/graphics')
        or die "ERROR: I can't find graphic";

    my ($listen) = $doc->findnodes('/domain/devices/graphics/zlib');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"zlib");
    }
    $listen->setAttribute(compression => 'auto');
}

sub _xml_add_graphics_playback {
    my $self = shift;
    my $doc = shift or confess "Missing XML doc";

    my ($graph) = $doc->findnodes('/domain/devices/graphics')
        or die "ERROR: I can't find graphic";

    my ($listen) = $doc->findnodes('/domain/devices/graphics/playback');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"playback");
    }
    $listen->setAttribute(compression => 'on');
}

sub _xml_add_graphics_streaming {
    my $self = shift;
    my $doc = shift or confess "Missing XML doc";

    my ($graph) = $doc->findnodes('/domain/devices/graphics')
        or die "ERROR: I can't find graphic";

    my ($listen) = $doc->findnodes('/domain/devices/graphics/streaming');

    if (!$listen) {
        $listen = $graph->addNewChild(undef,"streaming");
    }
    $listen->setAttribute(mode => 'filter');
}

=head2 list_networks

Returns a list of networks known to this VM. Each element is a Ravada::NetInterface object

=cut

sub list_networks {
    my $self = shift;

    $self->connect() if !$self->vm;
    my @nets = $self->vm->list_all_networks();
    my @ret_nets;

    for my $net (@nets) {
        push @ret_nets ,( Ravada::NetInterface::KVM->new( name => $net->get_name ) );
    }

    for my $if (IO::Interface::Simple->interfaces) {
        next if $if->is_loopback();
        next if !$if->address();
        next if $if =~ /virbr/i;

        # that should catch bridges
        next if $if->hwaddr =~ /^[00:]+00$/;

        push @ret_nets, ( Ravada::NetInterface::MacVTap->new(interface => $if));
    }

    $self->vm(undef);
    return @ret_nets;
}

=head2 import_domain

Imports a KVM domain in Ravada

    my $domain = $vm->import_domain($name, $user);

=cut

sub import_domain($self, $name, $user, $spinoff=1) {

    my $domain_kvm;
    eval { $domain_kvm = $self->vm->get_domain_by_name($name) };
    confess $@ if $@;

    confess "ERROR: unknown domain $name in KVM" if !$domain_kvm;

    my $domain = Ravada::Domain::KVM->new(
                      _vm => $self
                  ,domain => $domain_kvm
                , storage => $self->storage_pool
    );

    return $domain;
}

=head2 is_alive

Returns true if the virtual manager connection is active, false otherwise.

=cut

sub is_alive($self) {
    return 0 if !$self->vm;
    my $is_alive = $self->vm->is_alive;
    return 0 if !$is_alive;
    eval {
        $self->vm->get_hostname();
    };
    warn $@ if $@;
    return 1 if !$@;
    return 0;
}

sub list_storage_pools($self, $data=undef) {
    confess "No VM " if !$self->vm;

    my @pools = _list_storage_pools($self->vm);
    if ($data) {
        my @ret;
        for my $pool (@pools) {
            push @ret,(_storage_data($pool));
        }
        return @ret;
    }

    return
        map { $_->get_name }
        grep { $_-> is_active }
        @pools;
}

sub _storage_data($pool) {
    my $p = {
        name => $pool->get_name
        ,is_active => $pool->is_active
    };
    my $xml = XML::LibXML->load_xml(
        string => $pool->get_xml_description()
    );
    my ($capacity) = $xml->findnodes("/pool/capacity");
    $p->{size} = $capacity->textContent / 1024 / 1024 / 1024;
    my ($available) = $xml->findnodes("/pool/available");
    $p->{available} = int($available->textContent/1024/1024/1024);

    my ($allocation) = $xml->findnodes("/pool/allocation");
    $p->{used} = int($allocation->textContent/1024/1024/1024);

    if ($p->{size}) {
        $p->{pc_used} = int($p->{used}/$p->{size}*100);
    }

    my ($path) = $xml->findnodes("/pool/target/path");
    $p->{path} = $path->textContent();

    $p->{size} = int($p->{size});

    return $p;
}

sub storage_info($self, $name) {
    my $pool = $self->vm->get_storage_pool_by_name($name)
        or die "Error: no storage pool '$name'\n";

    return _storage_data($pool);

}

sub free_memory($self) {
    confess "ERROR: VM ".$self->name." inactive"
        if !$self->is_alive;

    return $self->_free_memory_overcommit();

    my $free_available = $self->_free_memory_available();
    my $free_stats = $self->_free_memory_overcommit();

    $free_available = $free_stats if $free_stats < $free_available;

    return $free_available;
}

# TODO: enable this check from free memory with a config flag
#   though I don't think it would be suitable to use
#   Insights welcome
sub _free_memory_overcommit($self) {
    my $info = $self->vm->get_node_memory_stats();
    return ($info->{free} + $info->{buffers} + $info->{cached});
}

sub _free_memory_available($self) {
    my $info = $self->vm->get_node_memory_stats();
    my $used = 0;
    for my $domain ( $self->list_domains(active => 1, read_only => 1) ) {
        my $info = $domain->get_info();
        my $memory = ($info->{memory} or $info->{max_mem} or 0);
        $used += $memory;
    }
    my $free_mem = $info->{total} - $used;
    $free_mem = 0 if $free_mem < 0;
    my $free_real = $self->_free_memory_overcommit;

    $free_mem = $free_real if $free_real < $free_mem;

    return $free_mem;
}

sub _fetch_dir_cert($self) {
    return '' if $<;
    my $in = $self->read_file($FILE_CONFIG_QEMU);
    for my $line (split /\n/,$in) {
        chomp $line;
        $line =~ s/#.*//;
        next if !length($line);
        next if $line !~ /^\s*spice_tls_x509_cert_dir\s*=\s*"(.*)"\s*/;
        return $1 if $1;
    }
    close $in;
    return '';
}

sub free_disk($self, $pool_name = undef ) {
    my $pool;
    if ($pool_name) {
        $pool = $self->vm->get_storage_pool_by_name($pool_name);
    } else {
        $pool = $self->storage_pool();
    }
    my $info;
    for ( ;; ) {
        eval { $info = $pool->get_info() };
        last if !$@;
        warn "WARNING: free disk $@" if $@;
        sleep 1;
    }
    return $info->{available};
}

sub list_machine_types($self) {

    my %todo = map { $_ => 1 }
    ('isapc', 'microvm', 'xenfv','xenpv');

    my %ret_types;
    my $xml = $self->vm->get_capabilities();
    my $doc = XML::LibXML->load_xml(string => $xml);
    for my $node_arch ($doc->findnodes("/capabilities/guest/arch")) {
        my $arch = $node_arch->getAttribute('name');
        my %types;
        for my $node_machine (sort { $a->textContent cmp $b->textContent } $node_arch->findnodes("machine")) {
            my $machine = $node_machine->textContent;
            next if $machine !~ /^(pc-i440fx|pc-q35)-(\d+.\d+)/
            && $machine !~ /^(pc)-(\d+\d+)$/
            && $machine !~ /^([a-z]+)$/;

            next if $todo{$machine};
            my $version = ( $2 or 0 );
            $types{$1} = [ $version,$machine ]
            if !exists $types{$1} || $version > $types{$1}->[0];
        }
        my @types;
        for (keys %types) {
            push @types,($types{$_}->[1]);
        }
        $ret_types{$arch} = [sort @types];
    }
    return %ret_types;
}

sub _is_ip_nat($self, $ip0) {
    my $ip = NetAddr::IP->new($ip0);
    for my $net ( $self->vm->list_networks ) {
        my $xml = XML::LibXML->load_xml(string
            => $net->get_xml_description());
        my ($xml_ip) = $xml->findnodes("/network/ip");
        next if !$xml_ip;
        my $address = $xml_ip->getAttribute('address');
        my $netmask = $xml_ip->getAttribute('netmask');
        my $net = NetAddr::IP->new($address,$netmask);
        return 1 if $ip->within($net);
    }
    return 0;
}

sub get_library_version($self) {
    return $self->vm->get_library_version();
}

1;
