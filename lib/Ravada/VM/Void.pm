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
use Sys::Hostname;
use URI;
use YAML qw(Dump);

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
    confess if $args{name} eq 'tst_vm_v20_volatile_clones_02' && !$listen_ip;
    my $remote_ip = delete $args{remote_ip};
    my $domain = Ravada::Domain::Void->new(
                                           %args
                                           , domain => $args{name}
                                           , _vm => $self
    );
    my ($out, $err) = $self->run_command("/usr/bin/test",
         "-e ".$domain->_config_file." && echo 1" );
    chomp $out;
    die "Error: Domain $args{name} already exists " if $out;
    $domain->_set_default_info($listen_ip);
    $domain->_store( autostart => 0 );
    $domain->_store( is_active => $active );
    $domain->set_memory($args{memory}) if $args{memory};

    $domain->_insert_db(name => $args{name} , id_owner => $user->id
        , id_vm => $self->id
        , id_base => $args{id_base} 
        , description => $description
    );

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
        my $drivers = {};
        $drivers = $domain_base->_value('drivers');
        $domain->_store( drivers => $drivers );
    } else {
        my ($file_img) = $domain->disk_device();
        my ($vda_name) = "$args{name}-vda-".Ravada::Utils::random_name(4).".void";
        $file_img =~ m{.*/(.*)} if $file_img;
        $domain->add_volume(name => $vda_name
                        , capacity => ( $args{disk} or 1024)
                        , file => $file_img
                        , type => 'file'
                        , target => 'vda'
        );

        $self->_add_cdrom($domain, %args);
        $domain->_set_default_drivers();
        $domain->_set_default_info($listen_ip);
        $domain->_store( is_active => $active );

    }
    $domain->set_memory($args{memory}) if $args{memory};
    if ( $volatile || $user->is_temporary ) {
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

sub dir_img {
    return Ravada::Front::Domain::Void::_config_dir();
}

sub dir_base  { return dir_img }
sub dir_clone { return dir_img }

sub _storage_path($self, $storage) {
    confess "Error: unknown storage '$storage'" if $storage ne 'default';
    return dir_img;
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
    $file =~ s/\.\w+//;
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

sub list_networks {
    return Ravada::NetInterface::Void->new();
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

    die "TODO remote" if !$self->is_local;

    opendir my $ls,$self->dir_img or die $!;
    while (my $file = readdir $ls) {
        return $self->dir_img."/".$file if $file =~ m{$pattern};
    }
    closedir $ls;
    return;

}

sub import_domain($self, $name, $user, $backing_file) {

    my $file = $self->dir_img."/$name.yml";

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

sub list_storage_pools {
    return 'default';
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

#########################################################################3

1;
