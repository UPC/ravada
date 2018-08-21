package Ravada::VM::Void;

use Carp qw(carp croak);
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
use URI;

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

##########################################################################
#

sub _connect {
    my $self = shift;
    return 1 if ! $self->host || $self->host eq 'localhost'
                || $self->host eq '127.0.0.1'
                || $self->{_ssh};

    my ($out, $err)
        = $self->run_command("ls -l ".$self->dir_img." || mkdir -p ".$self->dir_img);

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
    croak "argument id_owner required"       if !$args{id_owner};

    my $domain = Ravada::Domain::Void->new(
                                           %args
                                           , domain => $args{name}
                                           , _vm => $self
    );

    $domain->_insert_db(name => $args{name} , id_owner => $args{id_owner}
        , id_vm => $self->id
        , id_base => $args{id_base} );

    if ($args{id_base}) {
        my $owner = Ravada::Auth::SQL->search_by_id($args{id_owner});
        my $domain_base = $self->search_domain_by_id($args{id_base});

        confess "I can't find base domain id=$args{id_base}" if !$domain_base;

        for my $file_base ($domain_base->list_files_base) {
            my ($dir,$vol_name,$ext) = $file_base =~ m{(.*)/(.*?)(\..*)};
            my $new_name = "$vol_name-$args{name}$ext";
            $domain->add_volume(name => $new_name
                                , path => "$dir/$new_name"
                                 ,type => 'file');
        }
        $domain->start(user => $owner)    if $owner->is_temporary;
    } else {
        my ($file_img) = $domain->disk_device();
        $domain->add_volume(name => 'void-diska' , size => ( $args{disk} or 1)
                        , path => $file_img
                        , type => 'file'
                        , target => 'vda'
        );
        $domain->_set_default_drivers();
        $domain->_set_default_info();
        $domain->_store( is_active => 0 );

    }
    $domain->set_memory($args{memory}) if $args{memory};
#    $domain->start();
    return $domain;
}

sub create_volume {
}

sub dir_img {
    return Ravada::Front::Domain::Void::_config_dir();
}

sub _list_domains_local($self, %args) {
    my $active = delete $args{active};

    confess "Wrong arguments ".Dumper(\%args)
        if keys %args;

    opendir my $ls,Ravada::Front::Domain::Void::_config_dir() or return;

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

sub import_domain {
    confess "Not implemented";
}

sub refresh_storage {}

sub free_memory { return 1024*1024 }

sub refresh_storage_pools {

}

sub list_storage_pools {
    return Ravada::Front::Domain::Void::_config_dir();
}

sub is_alive($self) {
    return 0 if !$self->vm;
    return 1;
}

#########################################################################3

1;
