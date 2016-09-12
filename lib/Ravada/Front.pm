package Ravada::Front;

use strict;
use warnings;

use Moose;
use Ravada;

has 'config' => (
    is => 'ro'
    ,isa => 'Str'
    ,default => $Ravada::FILE_CONFIG
);
has 'connector' => (
        is => 'rw'
);


our $CONNECTOR = \$Ravada::CONNECTOR;

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

sub create_domain {
    my $self = shift;
    return Ravada::Request->create_domain(@_);
}

1;
