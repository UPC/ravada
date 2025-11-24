package Ravada::VM::Void;

use Carp qw(carp croak);
use Data::Dumper;
use Encode;
use Encode::Locale;
use Fcntl qw(:flock O_WRONLY O_EXCL O_CREAT);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use Moose;
use Socket qw( inet_aton inet_ntoa );
use Storable qw(dclone);
use Sys::Hostname;
use URI;
use YAML qw(Dump Load);

use Ravada::Domain::Void;
use Ravada::NetInterface::Void;

no warnings "experimental::signatures";
use feature qw(signatures);

with 'Ravada::VM';

has 'type' => (
    is => 'ro'
    ,isa => 'Str'
    ,default => 'Void'
);

has 'vm' => (
    is => 'rw'
    ,isa => 'Any'
    ,builder => '_connect'
    ,lazy => 1
);

has has_networking => (
    isa => 'Bool'
    , is => 'ro'
    , default => 1
);

our $CONNECTOR = \$Ravada::CONNECTOR;

##########################################################################
#

sub _connect {
    my $self = shift;
    return 1 if ! $self->host || $self->host eq 'localhost'
                || $self->host eq '127.0.0.1'
                || $self->{_ssh};

    my ($out, $err);
    eval {
       ($out, $err)= $self->run_command("ls -l ".$self->dir_img." || mkdir -p ".$self->dir_img);
    };

    warn "ERROR: error connecting to ".$self->host." $err"  if $err;
    return 0 if $err;
    return 1;
}

sub connect($self) {
    $self->_init_storage_pool_default();

    return 1 if $self->vm;
    return $self->vm($self->_connect);
}

sub disconnect {
    my $self = shift;
    $self->vm(0);

    return if !$self->{_ssh};
    $self->{_ssh}->disconnect;
    delete $self->{_ssh};
}

sub reconnect {}

sub create_domain {
    my $self = shift;
    my %args = @_;

    croak "argument name required"       if !$args{name};
    my $id_owner = delete $args{id_owner} or confess "ERROR: The id_owner is mandatory";
    my $user = Ravada::Auth::SQL->search_by_id($id_owner)
        or confess "ERROR: User id $id_owner doesn't exist";

    my $volatile = delete $args{volatile};
    my $active = ( delete $args{active} or $volatile or $user->is_temporary or 0);
    my $listen_ip = delete $args{listen_ip};
    my $description = delete $args{description};
    my $remote_ip = delete $args{remote_ip};
    my $id = delete $args{id};
    my $storage = delete $args{storage};

    my $options = delete $args{options};
    my $network;
    $network = $options->{network} if $options && exists $options->{network};

    my $domain = Ravada::Domain::Void->new(
                                           %args
                                           , domain => $args{name}
                                           , _vm => $self
                                           ,storage => $storage
    );

    my $file_exists = $self->file_exists($domain->_config_file);

    $domain->_insert_db(name => $args{name} , id_owner => $user->id
        , id => $id
        , id_vm => $self->id
        , id_base => $args{id_base} 
        , description => $description
    ) unless $domain->is_known();

    return $domain if $file_exists && exists $args{config};

    die "Error: Domain $args{name} already exists in ".$self->name
    ." ".$domain->_config_file if $file_exists;

    $domain->_set_default_info($listen_ip, $network);
    $domain->_store( autostart => 0 );
    $domain->_store( is_active => $active );
    $domain->_store( is_volatile => ($volatile or 0 ));
    $domain->set_memory($args{memory}) if $args{memory};

    if ($args{id_base}) {
        my $owner = $user;
        my $domain_base = $self->search_domain_by_id($args{id_base});

        confess "I can't find base domain id=$args{id_base}" if !$domain_base;

        for my $base_t ($domain_base->list_files_base_target) {
            my ($file_base, $target ) = @$base_t;
            my $vol_base = Ravada::Volume->new(
                file => $file_base
                ,is_base => 1
                ,vm => $domain_base->_vm
            );
            my $vol_clone = $vol_base->clone(name => "$args{name}-$target");
            $domain->add_volume(name => $vol_clone->name
                              , target => $target
                                , file => $vol_clone->file
                                 ,type => 'file'
                             );
        }
        my $base_hw = $domain_base->_value('hardware');
        my $clone_hw = $domain->_value('hardware');
        for my $hardware( keys %{$base_hw} ) {
            next if $hardware eq 'device' || $hardware eq 'host_devices';
            $clone_hw->{$hardware} = $base_hw->{$hardware};
            next if $hardware ne 'display';
            for my $entry ( @{$clone_hw->{$hardware}} ) {
                $entry->{port} = 'auto' if $entry->{port};
                $entry->{port} = $domain->_new_free_port() if $active || $volatile;
                $entry->{ip} = $listen_ip;
            }
        }
        $domain->_store(hardware => $clone_hw);

        my $base_info = $domain_base->_value('info');
        my $clone_info = $domain->_value('info');
        for my $item ( keys %$base_info) {
            $clone_info->{$item} = $base_info->{$item}
            if $item !~ /^(mac|state)$/;
        }
        $domain->_store(info => $clone_info);

        my $drivers = {};
        $drivers = $domain_base->_value('drivers');
        $domain->_store( drivers => $drivers );
        if ( $network ) {
            for my $index ( 0 .. scalar(@{$clone_hw->{network}})-1) {
                $domain->change_hardware('network', $index ,{name => $network})
            }
        }
        $active = 0 if $domain_base->list_host_devices();
    } elsif (!exists $args{config}) {
        $storage = $self->default_storage_pool_name() if !$storage;
        my ($vda_name) = "$args{name}-vda-".Ravada::Utils::random_name(4).".void";
        $domain->add_volume(name => $vda_name
                        , capacity => ( $args{disk} or 1024)
                        , type => 'file'
                        , target => 'vda'
                        , storage => $storage
        );

        $self->_add_cdrom($domain, %args);
        $domain->_set_default_drivers();
        $domain->_set_default_info($listen_ip, $network);
        $domain->_store( is_active => $active );

    }
    $domain->set_memory($args{memory}) if $args{memory};
    if ( $active ) {
        $domain->_store( is_active => 1 );
    }
#    $domain->start();
    return $domain;
}

sub _add_cdrom($self, $domain, %args) {
    my $id_iso = delete $args{id_iso};
    my $iso_file = delete $args{iso_file};
    return if !$id_iso && !$iso_file;

    if ($id_iso && ! $iso_file) {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM iso_images WHERE id=?");
        $sth->execute($id_iso);
        my $row = $sth->fetchrow_hashref();
        return if !$row->{has_cd};
        $iso_file = $row->{device};
        if (!$iso_file) {
            $iso_file = $row->{name};
            $iso_file =~ s/\s/_/g;
            $iso_file=$self->dir_img."/".lc($iso_file).".iso";
            if (! -e $iso_file ) {
                $self->write_file($iso_file,Dump({iso => "ISO mock $row->{name}"}));
            }
        }
    }
    $iso_file = '' if $iso_file eq '<NONE>';
    $domain->add_volume(
        file => $iso_file
        , device => 'cdrom'
        , type => 'cdrom'
        , target => 'hdc'
    );
}

sub create_volume {
}

sub dir_img($self=undef) {
    return Ravada::Front::Domain::Void::_config_dir()
    if !defined($self) || !ref($self);

    return $self->_storage_path($self->default_storage_pool_name);
}

sub _storage_path($self, $storage) {
    confess if !defined $storage;
    my @list = $self->list_storage_pools(1);
    my ($sp) = grep { $_->{name} eq $storage } @list;

    confess "Error: unknown storage '$storage'" if !$sp;

    return $sp->{path};
}

sub _list_domains_local($self, %args) {
    my $active = delete $args{active};

    confess "Wrong arguments ".Dumper(\%args)
        if keys %args;

    opendir my $ls,dir_img or return;

    my @domain;
    while (my $file = readdir $ls ) {
        my $domain = $self->_is_a_domain($file) or next;
        next if defined $active && $active && !$domain->is_active;
        push @domain , ($domain);
    }

    closedir $ls;

    return @domain;
}

sub _is_a_domain($self, $file) {

    chomp $file;

    return if $file !~ /\.yml$/;
    $file =~ s/\.\w+$//;
    $file =~ s/(.*)\.qcow.*$/$1/;
    return if $file !~ /\w/;

    my $domain = Ravada::Domain::Void->new(
                    domain => $file
                     , _vm => $self
    );
    return if !$domain->is_known;
    return $domain;
}

sub _list_domains_remote($self, %args) {

    my $active = delete $args{active};

    confess "Wrong arguments ".Dumper(\%args) if keys %args;

    my ($out, $err) = $self->run_command("ls -1 ".$self->dir_img);

    my @domain;
    for my $file (split /\n/,$out) {
        if ( my $domain = $self->_is_a_domain($file)) {
            next if defined $active && $active
                        && !$domain->is_active;
            push @domain,($domain);
        }
    }

    return @domain;
}

sub list_domains($self, %args) {
    return $self->_list_domains_local(%args) if $self->is_local();
    return $self->_list_domains_remote(%args);
}

sub discover($self) {
    opendir my $ls,dir_img or return;

    my %known = map { $_->name => 1 } $self->list_domains();

    my @list;
    while (my $file = readdir $ls ) {
        next if $file !~ /\.yml$/;
        $file =~ s/\.\w+//;
        $file =~ s/(.*)\.qcow.*$/$1/;
        return if $file !~ /\w/;
        next if $known{$file};
        push @list,($file);
    }
    return @list;
}

sub search_domain {
    my $self = shift;
    my $name = shift or confess "ERROR: Missing name";

    for my $domain_vm ( $self->list_domains ) {
        next if $domain_vm->name ne $name;

        my $domain = Ravada::Domain::Void->new( 
            domain => $name
            ,readonly => $self->readonly
                 ,_vm => $self
        );
        my $id;

        eval { $id = $domain->id };
        warn $@ if $@;
        return if !defined $id;#
        $domain->_insert_db_extra   if !$domain->is_known_extra();
        return $domain;
    }
    return;
}

sub list_routes {
    return Ravada::NetInterface::Void->new();
}

sub list_virtual_networks($self) {

    my $dir_net = $self->dir_img."/networks";
    if (!$self->file_exists($dir_net)) {
        my ($out, $err) = $self->run_command("mkdir","-p", $dir_net);
        die $err if $err;
    }
    my @files = $self->list_files($dir_net,qr/.yml$/);
    my @list;
    for my $file(@files) {
        my $net;
        eval { $net = Load($self->read_file("$dir_net/$file")) };
        confess $@ if $@;

        $net->{id_vm} = $self->id if !$net->{id_vm};
        $net->{is_active}=0 if !defined $net->{is_active};
        $net->{forward_mode}='nat' if !$net->{forward_mode};
        push @list,($net);
    }
    if (!@list) {
        my $net = {name => 'default'
            , autostart => 1
            , internal_id => 1
            , bridge => 'voidbr0'
            ,ip_address => '192.51.100.1'
            ,is_active => 1
            ,forward_mode => 'nat'
        };

        my $file_out = $self->dir_img."/networks/".$net->{name}.".yml";
        $self->write_file($file_out,Dump($net));
        push @list,($net);
    }
    return @list;
}

sub _new_net_id($self) {
    my %id;
    for my $net ( $self->list_virtual_networks() ) {
        $id{$net->{internal_id}}++;
    }
    my $new_id = 0;
    for (;;) {
        return $new_id if !exists $id{++$new_id};
    }
}

sub _new_net_bridge ($self) {
    my %bridge;
    my $n = 0;
    for my $net ( $self->list_virtual_networks() ) {
        $bridge{$net->{bridge}}++;
    }
    my $new_id = 0;
    for (;;) {
        my $new_bridge = 'voidbr'.$new_id;
        return $new_bridge if !exists $bridge{$new_bridge};
        $new_id++;
    }
}

sub new_network($self, $name='net') {

    my @networks = $self->list_virtual_networks();

    my %base = (
        name => $name
        ,ip_address => ['192.168.','.0']
        ,bridge => 'voidbr'
    );
    my $new = {ip_netmask => '255.255.255.0'};
    for my $field ( keys %base) {
        my %old = map { $_->{$field} => 1 } @networks;
        my $n = 0;
        my $base = ($base{$field} or $field);
        my $value;
        for ( 0 .. 255 ) {
            if (ref($base)) {
                $value = $base->[0].$n.$base->[1]
            } else {
                $value = $base.$n;
            }
            last if !$old{$value};
            $n++;
        }
        $new->{$field} = $value;
    }
    return $new;
}

sub create_network($self, $data0, $id_owner=undef, $request=undef) {

    $data0->{internal_id} = $self->_new_net_id();

    my $data = dclone($data0);

    my $file_out = $self->dir_img."/networks/".$data->{name}.".yml";
    die "Error: network $data->{name} already created"
    if $self->file_exists($file_out);

    $data->{bridge} = $self->_new_net_bridge()
    if !exists $data->{bridge} || ! defined $data->{bridge};

    $data->{forward_mode} = 'nat' if !exists $data->{forward_mode};

    delete $data->{is_public};

    for my $field ('bridge','ip_address') {
        $self->_check_duplicated_network($field,$data);
    }

    delete $data->{is_public};
    delete $data->{id};
    delete $data->{id_vm};
    delete $data->{isolated};
    delete $data->{id_owner};

    $self->write_file($file_out,Dump($data));

    return $data;
}

sub remove_network($self, $name) {
    my $file_out = $self->dir_img."/networks/$name.yml";
    return if !$self->file_exists($file_out);
    $self->remove_file($file_out);
}


sub search_volume($self, $pattern) {

    return $self->_search_volume_remote($pattern)   if !$self->is_local;

    opendir my $ls,$self->dir_img or die $!;
    while (my $file = readdir $ls) {
        return $self->dir_img."/".$file if $file eq $pattern;
    }
    closedir $ls;
    return;
}

sub list_used_volumes($self) {
    my @disk;
    for my $domain ($self->list_domains) {
        push @disk,($domain->list_disks());
        push @disk,($domain->list_files_base()) if $domain->is_base;
        push @disk,($domain->_config_file());
        push @disk,($domain->_config_file().".lock");
    }
    return @disk
}

sub _list_volumes_sp($self, $sp) {
    die "Error: TODO remote!" if !$self->is_local;

    confess if !defined $sp;
    my $dir = $sp->{path} or die "Error: unknown path ".Dumper($sp);
    return if ! -e $dir;

    my @vol;

    opendir my $ls,$dir or die "$! $dir";
    while (my $file = readdir $ls) {
        push @vol,("$dir/$file") if -f "$dir/$file";
    }
    closedir $ls;

    return @vol;

}

sub list_volumes($self) {
    my @volumes;
    for my $sp ($self->list_storage_pools(1)) {
        for my $vol ( $self->_list_volumes_sp($sp) ) {
            push @volumes,($vol);
        }
    }
    return @volumes;
}

sub _search_volume_remote($self, $pattern) {

    my ($out, $err) = $self->run_command("ls -1 ".$self->dir_img);

    confess $err if $err;

    my $found;
    for my $file ( split /\n/,$out ) {
        $found = $self->dir_img."/".$file if $file eq $pattern;
    }

    return $found;
}

sub search_volume_path {
    return search_volume(@_);
}

sub search_volume_path_re {
    my $self = shift;
    my $pattern = shift;

    return $self->_search_volume_path_re_remote($pattern) if !$self->is_local;

    opendir my $ls,$self->dir_img or die $!;
    while (my $file = readdir $ls) {
        return $self->dir_img."/".$file if $file =~ $pattern;
    }
    closedir $ls;
    return;

}

sub _search_volume_path_re_remote($self,$pattern) {
    my ($out, $err) = $self->run_command("ls",$self->dir_img);
    for my $name ( split /\n/,$out) {
        return $self->dir_img."/$name" if $name =~ $pattern;
    }
    return;
}

sub remove_file($self, @files) {
    $self->_remove_file_os(@files);
}

sub import_domain($self, $name, $user, $backing_file) {

    my $file = $self->dir_img."/$name.yml";
    $file = $self->dir_img."/".Encode::decode_utf8($name).".yml"
    if ! -e $file;

    die "Error: domain $name not found in ".$self->dir_img if !-e $file;

    return Ravada::Domain::Void->new(
        domain => $file
        ,name => $name
        ,_vm => $self
    );

}

sub refresh_storage {}

sub refresh_storage_pools {

}

sub _init_storage_pool_default($self) {

    my $config_dir = Ravada::Front::Domain::Void::_config_dir();
    my $file_sp = "$config_dir/.storage_pools.yml";

    return if $self->file_exists($file_sp);

    my @list = ({ name => 'default', path => $config_dir, is_active => 1 });

    $self->write_file($file_sp, Dump( \@list));

}

sub _find_storage_pool($self, $file) {

    my ($path) = $file =~ m{(.*)/};

    return $self->{_storage_pool_path}->{$path}
    if $self->{_storage_pool_path} && exists $self->{_storage_pool_path}->{$path};

    my $found;
    for my $sp ($self->list_storage_pools(1)) {
        if ($sp->{path} eq $path) {
            $found = $sp->{name};
            last;
        }
    }
    return '' if !$found;
    $self->{_storage_pool_path}->{$path} = $found;
    return $found;
}

sub list_storage_pools($self, $info=0) {
    my @list;
    my $config_dir = Ravada::Front::Domain::Void::_config_dir();

    $self->_init_storage_pool_default();

    my $file_sp = "$config_dir/.storage_pools.yml";
    my $extra= Load($self->read_file($file_sp));
    push @list,(@$extra) if $extra;

    my ($default) = grep { $_->{name} eq 'default'} @list;
    if (!$default) {
        push @list,({name =>'default',path => dir_img(), is_active => 1});
    }

    if($info) {
        for my $entry (@list) {
            $entry->{is_active}=1 if !exists $entry->{is_active};
        }
        return @list;
    }
    my @names = map { $_->{name} } @list;
    return @names;
}


sub is_alive($self) {
    return 0 if !$self->vm;
    return $self->ping(undef,0);
}

sub free_memory {
    my $self = shift;

    open my $mem,'<',"/proc/meminfo" or die "$! /proc/meminfo";
    my $memory = <$mem>;
    close $mem;

    chomp $memory;
    $memory =~ s/.*?(\d+).*/$1/;
    for my $domain ( $self->list_domains(active => 1) ) {
        next if !$domain->is_active;
        $memory -= $domain->get_info->{memory};
    }
    return $memory;
}

sub _fetch_dir_cert {
    confess "TODO";
}

sub free_disk($self, $storage_pool = undef) {
    my $df = `df`;
    for my $line (split /\n/, $df) {
        my @info = split /\s+/,$line;
        return $info[3] * 1024 if $info[5] eq '/';
    }
    die "Not found";
}

=head2 file_exists

Returns true if the file exists in this virtual manager storage

=cut

sub file_exists( $self, $file ) {
    return -e $file if $self->is_local;

    my $ssh = $self->_ssh;
    confess "Error: no ssh connection to ".$self->name if ! $ssh;

    confess "Error: dangerous filename '$file'"
        if $file =~ /[`|"(\\\[]/;
    my ($out, $err) = $self->run_command("/bin/ls -1 $file");

    return 1 if !$err;
    return 0;
}

sub _is_ip_nat($self, $ip) {
    return 1;
}

sub _search_iso($self, $id, $device = undef) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM iso_images "
        ." WHERE id=?"
    );
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    $row->{device} = $device if defined $device;
    return $row;
}

sub _iso_name($self, $iso, $request=undef, $verbose=0) {

    return '' if !$iso->{has_cd};

    my $name = ($iso->{device} or $iso->{rename_file} or $iso->{file_re});
    confess Dumper($iso) if !$name;
    $name =~ s/(.*)\.\*(.*)/$1$2/;
    $name =~ s/(.*)\.\+(.*)/$1.$2/;
    $name =~ s/(.*)\[\\d.*?\]\+(.*)/${1}1$2/;
    $name =~ s/^\^(.*)\$$/$1/;
    confess $name if $name =~ m{[*+\\]};

    $name = $self->_storage_path($self->default_storage_pool_name)."/".$name unless $name =~ m{^/};

    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE iso_images "
        ." SET device=? WHERE id=?"
    );
    $sth->execute($name, $iso->{id});

    open my $out,">",$name or die "$! $name";
    print $out "...\n";
    close $out;

    return $name;
}

sub _search_url_file($self, $url) {
    my ($url0,$file) = $url =~ m{(.*)/(.*)};
    confess "Undefined file in url=$url" if !$file;
    my $file0 = $file;
    $file =~ s/(.*)\.\*(.*)/$1$2/;
    $file =~ s/(.*)\.\+(.*)/$1.$2/;
    $file =~ s/(.*)\[\\d.*?\]\+(.*)/${1}1$2/;
    $file =~ s/(.*)\\d\+(.*)/${1}1$2/;
    confess Dumper($url, $file0,$file) if $file =~ m{[*+\\]}
    || $file !~ /\.iso$/;

    return "$url0/$file";
}

sub _download_file_external($self, $url, $device) {
}

sub get_library_version($self) {
    my ($n1,$n2,$n3) = $Ravada::VERSION =~ /(\d+)\.(\d+)\.(\d+)/;
    return $n1*1000000
    +$n2*1000
    +$n3;
}

sub create_storage_pool($self, $name, $dir) {

    die "Error: $dir does not exist\n" if ! -e $dir;

    my @list;
    my $file_sp = dir_img."/.storage_pools.yml";
    @list = $self->list_storage_pools(1) if -e $file_sp;

    my ($already) = grep { $_->{name} eq $name } @list;
    die "Error: duplicated storage pool $name" if $already;

    push @list,{ name => $name, path => $dir, is_active => 1 };

    $self->write_file($file_sp, Dump( \@list));

    return @list;
}

sub active_storage_pool($self, $name, $value) {

    my @list = $self->list_storage_pools(1);

    my $config_dir = Ravada::Front::Domain::Void::_config_dir();
    my $file_sp = "$config_dir/.storage_pools.yml";

    for my $entry (@list) {
        $entry->{is_active} = $value;
    }

    $self->write_file($file_sp, Dump( \@list));
}
sub get_cpu_model_names($self,$arch='x86_64') {
    return qw(486 qemu32 qemu64);
}

sub has_networking { return 1 };

sub _check_duplicated_network($self, $field, $data) {
    my @networks = $self->list_virtual_networks();
    my ($found) = grep {$data->{name} ne $_->{name}
        && $_->{$field} eq $data->{$field} } @networks;
    return if !$found;

    $field = 'Network' if $field eq 'ip_address';
    die "Error: $field is already in use in $found->{name}";
}

sub change_network($self,$data) {
    my $id = delete $data->{internal_id} or confess "Missing internal_id ".Dumper($data);
    confess if exists $data->{is_public};

    my @networks = $self->list_virtual_networks();
    my ($net0) = grep { $_->{internal_id} eq $id } @networks;

    my $file_out = $self->dir_img."/networks/".$net0->{name}.".yml";
    my $net= {};
    eval { $net = Load($self->read_file($file_out)) };
    confess $@ if $@;

    my $changed = 0;
    for my $field ('name', sort keys %$data) {
        next if $field =~ /^_/ || $field eq 'is_public';
        if (!exists $net->{$field}) {
            $net->{$field} = $data->{$field};
            $changed++;
            next;
        }
        next if exists $data->{$field} && exists $net->{$field}
        && defined $data->{$field} && defined $net->{$field}
        && $data->{$field} eq $net->{$field};

        if ($field eq 'name') {
            die "Error: network can not be renamed";
        }

        if ($field eq 'bridge' || $field eq 'ip_address') {
            $self->_check_duplicated_network($field,$data);
        }
        $net->{$field} = $data->{$field};
        $changed++;
    }
    return if !$changed;

    delete $net->{is_public};
    delete $net->{id};
    delete $net->{id_vm};

    $self->write_file($file_out,Dump($net));
}

sub remove_storage_pool($self, $name) {

    my $file_sp = $self->dir_img."/.storage_pools.yml";
    my $sp_list = Load($self->read_file($file_sp));
    my @sp2;
    for my $sp (@$sp_list) {
        push @sp2,($sp) if $sp->{name} ne $name;
    }

    $self->write_file($file_sp, Dump( \@sp2));
}

sub copy_file($self, $orig, $dst) {
    if ($self->is_local) {
        copy($orig, $dst) or die "$! $orig $dst";
    } else {
        $dst =~ tr/[a-zA-Z0-9_\-\.\/]/_/c;
        die "Invalid file '$orig'" unless $orig =~ /^[a-zA-Z0-9_\-\.\/]+$/;
        die "Invalid file '$dst'" unless $dst =~ /^[a-zA-Z0-9_\-\.\/]+$/;
        $self->run_command("cp",$orig,$dst);
    }
}

#########################################################################3

1;
