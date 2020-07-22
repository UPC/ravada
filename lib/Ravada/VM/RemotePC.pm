package Ravada::VM::RemotePC;

use warnings;
use strict;

=head1 NAME

Ravada::VM::RemotePC - Remote PC Managers library for Ravada

=cut

use Carp qw(croak carp cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use JSON::XS;

use Moose;

use feature qw(signatures);
no warnings "experimental::signatures";

use Ravada::Domain::RemotePC;
use Ravada::Utils;

with 'Ravada::VM';

has type => (
    is => 'ro'
    ,isa => 'Str'
    ,default => 'RemotePC'
);

has 'features_vm' => (
    is => 'ro'
    ,isa => 'HashRef'
    ,default => sub {
        my %f = (
            bind_ip => 0
            ,change_hardware => 0
            ,extra_data => 0
            ,iptables => 0
            ,memory => 0
            ,new_base => 1
            ,spice => 0
            ,volumes => 0
            ,shutdown_before_remove => 0
        );
        lock_hash(%f);
        return \%f;

    }
);

##########################################################################

sub connect {
    return 1;
}

sub _connect { return 1 }

sub disconnect {
}

sub create_domain($self,%args) {
    my $name = delete $args{name} or confess "Error: missing name argument";

    my $active = delete $args{active};
    my $request = delete $args{request};
    my $id_base = delete $args{id_base};
    my $is_base = delete $args{is_base};
    my $id_owner = delete $args{id_owner};
    my $user = Ravada::Auth::SQL->search_by_id($id_owner)
        or confess "ERROR: User id $id_owner doesn't exist";

    my $volatile = delete $args{volatile};
    confess "Error: unsupported volatile machines in ".$self->type
        if $volatile;

    my $info = ( delete $args{info} or {} );

    my $from_pool = delete $args{from_pool};
    confess "Error: create from pool shouldn't reach here "
    if $from_pool;

    confess "Error: unknown args ".Dumper(\%args) if keys %args;

    my $domain = Ravada::Domain::RemotePC->new(
        name => $name
        ,domain => $name
        ,_vm => $self
        ,active => $active
    );
    $domain->_insert_db(name => $name , id_owner => $user->id
        , id_vm => $self->id
        , id_base => $id_base
    );
    $domain->_data_extra( info => encode_json($info) );

    return $domain;
}

sub create_volume {
    die "No sense with Remote PCs";
    # We may create volumes in a shared storage for the PCs eventually
}

sub free_disk { }
sub free_memory { }
sub import_domain {
    die "Error: domain not found";
}
sub is_alive {
    return 1;
}

sub list_domains {
    die "TODO: maybe fetch from db";
}

sub search_domain($self, $name, $force=undef) {
    my $sth = $self->_dbh->prepare("SELECT * FROM domains "
        ." WHERE name = ? "
    );
    $sth->execute($name);
    my $data = $sth->fetchrow_hashref();
    return if !keys %$data;
    return Ravada::Domain::RemotePC->new(
        name => $name
        , domain => $name
        , _vm => $self
    );
}


sub list_storage_pools {
}

1;
