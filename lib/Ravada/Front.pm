package Ravada::Front;

use strict;
use warnings;

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


our $CONNECTOR = \$Ravada::CONNECTOR;
our $TIMEOUT = 5;

=head2 BUILD

Internal constructor

=cut

sub BUILD {
    my $self = shift;
    $$CONNECTOR = $self->connector if $self->connector;
    Ravada::_init_config($self->config, $self->connector);
}

sub list_bases {
    my $self = shift;
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domains where is_base='y'");
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
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domains ");
    $sth->execute();
    
    my @domains = ();
    while ( my $row = $sth->fetchrow_hashref) {
        push @domains, ($row);
    }
    $sth->finish;

    return \@domains;
}

sub list_vm_types {
    my $self = shift;

    my $req = Ravada::Request->list_vm_types();
    _wait_request($req);

    die "ERROR: Timeout waiting for request ".$req->id
        if $req->status() eq 'timeout';

    return $req->result();
}

sub create_domain {
    my $self = shift;
    return Ravada::Request->create_domain(@_);
}

sub _wait_request {
    my $req = shift;
    my $timeout = ( shift or $TIMEOUT );

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
    _wait_request($req, 2);
    return 1 if $req->status() eq 'done';
    return 0;
}

1;
