package Ravada::VM::Void;

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
use URI;

use Ravada::Domain::Void;
use Ravada::NetInterface::Void;

with 'Ravada::VM';

has 'vm' => (
    is => 'rw'
);

has 'type' => (
    is => 'ro'
    ,isa => 'Str'
    ,default => 'Void'
);

##########################################################################
#

sub connect {}
sub disconnect {}
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

    }
    $domain->set_memory($args{memory}) if $args{memory};
#    $domain->start();
    return $domain;
}

sub create_volume {
}

sub dir_img {
    return $Ravada::Domain::Void::DIR_TMP;
}

sub list_domains {
    my $self = shift;

    opendir my $ls,$Ravada::Domain::Void::DIR_TMP or return;

    my @domain;
    while (my $file = readdir $ls ) {
        next if $file !~ /\.yml$/;
        $file =~ s/\.\w+//;
        $file =~ s/(.*)\.qcow.*$/$1/;
        next if $file !~ /\w/;

        my $domain = Ravada::Domain::Void->new(
                    domain => $file
                     , _vm => $self
        );
        next if !$domain->is_known;
        push @domain , ($domain);
    }

    closedir $ls;

    return @domain;
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
        return $domain;
    }
    return;
}

sub list_networks {
    return Ravada::NetInterface::Void->new();
}

sub search_volume {
    my $self = shift;
    my $pattern = shift;

    opendir my $ls,$self->dir_img or die $!;
    while (my $file = readdir $ls) {
        return $self->dir_img."/".$file if $file eq $pattern;
    }
    closedir $ls;
    return;
}

sub search_volume_path {
    return search_volume(@_);
}

sub search_volume_path_re {
    my $self = shift;
    my $pattern = shift;

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

sub ping { return 1 }

sub is_active { return 1 }

#########################################################################3

1;
