package Ravada::Front;

use strict;
use warnings;

use Hash::Util qw(lock_hash);
use JSON::XS;
use Moose;
use Ravada;
use Ravada::Network;

use Data::Dumper;

has 'config' => (
    is => 'ro'
    ,isa => 'Str'
    ,default => $Ravada::FILE_CONFIG
);
has 'connector' => (
        is => 'rw'
);
has 'backend' => (
    is => 'ro',
    isa => 'Ravada'

);

has 'fork' => (
    is => 'rw'
    ,isa => 'Int'
    ,default => 1
);

our $CONNECTOR;# = \$Ravada::CONNECTOR;
our $TIMEOUT = 5;
our @VM_TYPES = ('KVM');

our %VM;

=head2 BUILD

Internal constructor

=cut

sub BUILD {
    my $self = shift;
    if ($self->connector) {
        $CONNECTOR = $self->connector;
    } else {
        Ravada::_init_config($self->config());
        $CONNECTOR = Ravada::_connect_dbh();
    }
}

=head2 list_bases

Returns a list of the base domains as a listref

    my $bases = $rvd_front->list_bases();

=cut

sub list_bases {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains where is_base=1");
    $sth->execute();
    
    my @bases = ();
    while ( my $row = $sth->fetchrow_hashref) {
        push @bases, ($row);
    }
    $sth->finish;

    return \@bases;
}

=head2 list_domains

Returns a list of the domains as a listref

    my $bases = $rvd_front->list_domains();

=cut

sub list_domains {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains ");
    $sth->execute();
    
    my @domains = ();
    while ( my $row = $sth->fetchrow_hashref) {
        my $domain ;
        eval { $domain   = $self->search_domain($row->{name}) };
        $row->{is_active} = 1 if $domain && $domain->is_active;
        $row->{is_locked} = 1 if $domain && $domain->is_locked;
        $row->{is_paused} = 1 if $domain && $domain->is_paused;
        push @domains, ($row);
    }
    $sth->finish;

    return \@domains;
}

=head2 list_vm_types

Returns a reference to a list of Virtual Machine Managers known by the system

=cut

sub list_vm_types {
    my $self = shift;

    return $self->{cache}->{vm_types} if $self->{cache}->{vm_types};

    my $result = [@VM_TYPES];

    $self->{cache}->{vm_types} = $result if $result->[0];

    return $result;
}

=head2 list_iso_images

Returns a reference to a list of the ISO images known by the system

=cut

sub list_iso_images {
    my $self = shift;

    my @iso;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM iso_images ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @iso,($row);
    }
    $sth->finish;
    return \@iso;
}

=head2 list_lxc_templates

Returns a reference to a list of the LXC templates known by the system

=cut


sub list_lxc_templates {
    my $self = shift;

    my @template;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM lxc_templates ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @template,($row);
    }
    $sth->finish;
    return \@template;

}

=head2 list_users

Returns a reference to a list of the users

=cut

sub list_users {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM users ");
    $sth->execute();
    
    my @users = ();
    while ( my $row = $sth->fetchrow_hashref) {
        push @users, ($row);
    }
    $sth->finish;

    return \@users;
}

=head2 create_domain

Request the creation of a new domain or virtual machine

    # TODO: document the args here
    my $req = $rvd_front->create_domain( ... );

=cut

sub create_domain {
    my $self = shift;
    return Ravada::Request->create_domain(@_);
}

=head2 wait_request

Waits for a request for some seconds.

=head3 Arguments

=over 

=item * request

=item * timeout (optional defaults to $Ravada::Front::TIMEOUT

=back

Returns: the request

=cut

sub wait_request {
    my $self = shift;
    my $req = shift or confess "Missing request";

    my $timeout = ( shift or $TIMEOUT );

    if ( $self->backend ) {
        if ($self->fork ) {
            $self->backend->process_requests();
        } else {
            $self->backend->_process_requests_dont_fork();
        }
    }

    for ( 1 .. $timeout ) {
        last if $req->status eq 'done';
        sleep 1;
    }
    $req->status("timeout")
        if $req->status eq 'working';
    return $req;

}

=head2 ping_backend

Checks if the backend is alive.

Return true if alive, false otherwise.

=cut

sub ping_backend {
    my $self = shift;

    my $req = Ravada::Request->ping_backend();
    $self->wait_request($req, 2);

    return 1 if $req->status() eq 'done';
    return 0;
}

=head2 open_vm

Connects to a Virtual Machine Manager ( or VMM ( or VM )).
Returns a read-only connection to the VM.

=cut

sub open_vm {
    my $self = shift;
    my $type = shift or confess "I need vm type";
    my $class = "Ravada::VM::$type";

    return $VM{$type} if $VM{$type};

    my $proto = {};
    bless $proto,$class;

    $VM{$type} = $proto->new(readonly => 1);
    return $VM{$type};
}

=head2 search_clone

Search for a clone of a domain owned by an user.

    my $domain_clone = $rvd_front->(id_base => $domain_base->id , id_owner => $user->id);

=head3 arguments

=over

=item id_base : The id of the base domain

=item id_user

=back

Returns the domain

=cut

sub search_clone {
    my $self = shift;
    my %args = @_;
    confess "Missing id_owner " if !$args{id_owner};
    confess "Missing id_base" if !$args{id_base};

    my ($id_base , $id_owner) = ($args{id_base} , $args{id_owner} );

    delete $args{id_base};
    delete $args{id_owner};

    confess "Unknown arguments ".Dumper(\%args) if keys %args;

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,name FROM domains "
        ." WHERE id_base=? AND id_owner=? "
    );
    $sth->execute($id_base, $id_owner);

    my ($id_domain, $name) = $sth->fetchrow;
    $sth->finish;

    return if !$id_domain;

    return $self->search_domain($name);

}

=head2 search_domain

Searches a domain by name

    my $domain = $rvd_front->search_domain($name);

Returns a Ravada::Domain object

=cut

sub search_domain {
    my $self = shift;

    my $name = shift;

    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains WHERE name=?");
    $sth->execute($name);

    my $row = $sth->fetchrow_hashref;

    return if !keys %$row;

    my $vm_name = $row->{vm} or confess "Unknown vm for domain $name";

    my $vm = $self->open_vm($vm_name);
    my $domain = $vm->search_domain($name);

    return $domain;
}

=head2 list_requests

Returns a list of ruquests : ( id , domain_name, status, error )

=cut

sub list_requests {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT id, command, args, date_changed, status, error "
        ." FROM requests "
        ." WHERE command NOT IN (SELECT command FROM requests WHERE command = 'list_vm_types')"
        ." ORDER BY date_changed DESC LIMIT 4"
    );
    $sth->execute;
    my @reqs;
    my ($id, $command, $j_args, $date_changed, $status, $error);
    $sth->bind_columns(\($id, $command, $j_args, $date_changed, $status, $error));

    while ( $sth->fetch) {
        my $args = decode_json($j_args) if $j_args;

        push @reqs,{ id => $id,  command => $command, date_changed => $date_changed, status => $status, error => $error , name => $args->{name}};
    }
    $sth->finish;
    return \@reqs;
}

=head2 search_domain_by_id

  my $domain = $ravada->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains WHERE id=?");
    $sth->execute($id);

    my $row = $sth->fetchrow_hashref;

    return if !keys %$row;

    lock_hash(%$row);

    return $self->search_domain($row->{name});
}

=head2 start_domain

Request to start a domain.

=head3 arguments

=over

=item user => $user : a Ravada::Auth::SQL user

=item name => $name : the domain name

=item remote_ip => $remote_ip: a Ravada::Auth::SQL user


Returns an object: Ravada::Request.

    my $req = $rvd_front->start_domain(
               user => $user
              ,name => 'mydomain'
        , remote_ip => '192.168.1.1');

=cut

sub start_domain {
    my $self = shift;
    confess "ERROR: Must call start_domain with user=>\$user, name => \$name, remote_ip => \$ip"
        if scalar @_ % 2;

    my %args = @_;

    # TODO check for user argument
    $args{uid} = $args{user}->id    if $args{user};
    delete $args{user};

    return Ravada::Request->start_domain( %args );
}

=head2 list_bases_anonymous

List the available bases for anonymous user in a remote IP

    my $list = $rvd_front->list_bases_anonymous($remote_ip);

=cut

sub list_bases_anonymous {
    my $self = shift;
    my $ip = shift or confess "Missing remote IP";

    my $net = Ravada::Network->new(address => $ip);

    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains where is_base=1");
    $sth->execute();
    
    my @bases = ();
    while ( my $row = $sth->fetchrow_hashref) {
        next if !$net->allowed_anonymous($row->{id});
        push @bases, ($row);
    }
    $sth->finish;

    return \@bases;

}

1;
