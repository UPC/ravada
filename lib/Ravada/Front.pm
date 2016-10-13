package Ravada::Front;

use strict;
use warnings;

use Hash::Util qw(lock_hash);
use JSON::XS;
use Moose;
use Ravada;

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

sub list_bases {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains where is_base='y'");
    $sth->execute();
    
    my @bases = ();
    while ( my $row = $sth->fetchrow_hashref) {
        push @bases, ($row);
    }
    $sth->finish;

    return \@bases;
}

sub list_domains {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains ");
    $sth->execute();
    
    my @domains = ();
    while ( my $row = $sth->fetchrow_hashref) {
        my $domain ;
        eval { $domain   = $self->search_domain($row->{name}) };
        $row->{is_active} = 1 if $domain && $domain->is_active;
        push @domains, ($row);
    }
    $sth->finish;

    return \@domains;
}

sub list_vm_types {
    my $self = shift;

    return $self->{cache}->{vm_types} if $self->{cache}->{vm_types};

    my $result = [@VM_TYPES];

    $self->{cache}->{vm_types} = $result if $result->[0];

    return $result;
}

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

sub create_domain {
    my $self = shift;
    return Ravada::Request->create_domain(@_);
}

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

    for ( 1 .. $TIMEOUT ) {
        last if $req->status eq 'done';
        sleep 1;
    }
    $req->status("timeout")
        if $req->status eq 'working';
    return $req;

}

sub ping_backend {
    my $self = shift;

    my $req = Ravada::Request->ping_backend();
    $self->wait_request($req, 2);

    return 1 if $req->status() eq 'done';
    return 0;
}

sub open_vm {
    my $self = shift;
    my $type = shift or confess "I need vm type";
    my $class = "Ravada::VM::$type";

    my $proto = {};
    bless $proto,$class;

    return $proto->new(readonly => 1);
}

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

sub domdisplay {
    my $self = shift;
    my $name = shift    or confess "Missing domain name";
    my $user = shift    or confess "Missing user";

    my $req = Ravada::Request->domdisplay($name, $user->id);
    $self->wait_request($req, 10);

    return $req if $req->status() ne 'done';

    my $result = $req->result();
    return $result->{display};
}

sub start_domain {
    my $self = shift;
    my $name = shift;
    my $user = shift;

    return Ravada::Request->start_domain(name => $name, uid => $user->id);
}

1;
