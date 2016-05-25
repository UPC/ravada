package Ravada::Domain;

use warnings;
use strict;

use Carp qw(confess croak);
use Moose::Role;

our $TIMEOUT_SHUTDOWN = 20;

requires 'name';
requires 'remove';
requires 'display';

requires 'is_active';
requires 'start';
requires 'shutdown';
requires 'pause';

has 'domain' => (
    isa => 'Object'
    ,is => 'ro'
);

has 'timeout_shutdown' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => $TIMEOUT_SHUTDOWN
);



##################################################################################3
#
sub id {
    return $_[0]->_data('id');

}
sub file_base_img {
    my $file;
    eval { $file = $_[0]->_data('file_base_img') };
    return $file ;
}


##################################################################################

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_domain_db( name => $self->name);

    confess "No DB info for domain ".$self->name    if !$self->{_data};

    return $self->{_data}->{$field};
}

sub open {
    my $self = shift;

    my %args = @_;

    my $id = $args{id} or confess "Missing required argument id";
    delete $args{id};

    my $row = $self->_select_domain_db ( );
    return $self->search_domain($row->{name});
#    confess $row;
}

sub _select_domain_db {
    my $self = shift;
    my %args = @_;

    if (!keys %args) {
        my $id;
        eval { $id = $self->id  };
        if ($id) {
            %args =( id => $id );
        } else {
            %args = ( name => $self->name );
        }
    }

    my $sth = $self->connector->dbh->prepare(
        "SELECT * FROM domains WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $self->{_data} = $row;
    return $row;
}

sub _prepare_base_db {
    my $self = shift;
    my $file_img = shift;

    if (!$self->_select_domain_db) {
        $self->_insert_db( name => $self->name );
    }
    my $sth = $self->connector->dbh->prepare(
        "UPDATE domains set is_base='y',file_base_img=? "
        ." WHERE id=?"
    );
    $sth->execute($file_img , $self->id);
    $sth->finish;
    $self->{_data} = $self->_select_domain_db();
}

sub _insert_db {
    my $self = shift;
    my %field = @_;
    croak "Field name is mandatory ".Dumper(\%field)
        if !exists $field{name};
    my $query = "INSERT INTO domains "
            ."(" . join(",",sort keys %field )." )"
            ." VALUES (". join(",", map { '?' } keys %field )." ) "
    ;
    my $sth = $self->connector->dbh->prepare($query);
    eval { $sth->execute( map { $field{$_} } sort keys %field ) };
    if ($@) {
        warn "$query\n".Dumper(\%field);
        die $@;
    }
    $sth->finish;

}

sub _remove_domain_db {
    my $self = shift;

    $self->_select_domain_db or return;
    my $sth = $self->connector->dbh->prepare("DELETE FROM domains "
        ." WHERE id=?");
    $sth->execute($self->id);
    $sth->finish;
}


=head2 is_base

Returns true or  false if the domain is a prepared base

=cut

sub is_base { 
    my $self = shift;
    $self->_select_domain_db or return;

    return $self->_data('is_base') =~ /y/i 
};

1;
