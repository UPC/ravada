use warnings;
use strict;

package Ravada::VM;

use Carp qw(croak);
use Data::Dumper;
use Moose::Role;

requires 'connect';

# global DB Connection


# domain
requires 'create_domain';
requires 'search_domain';

# storage volume
requires 'create_volume';

############################################################

has 'host' => (
          isa => 'Str'
         , is => 'ro',
    , default => 'localhost'
);

has 'type' => (
          isa => 'Str'
         , is => 'ro',
    , default => 'qemu'
);

has 'storage_pool' => (
     isa => 'Object'
    , is => 'ro'
);

has 'default_dir_img' => (
      isa => 'String'
     , is => 'ro'
);

has 'connector' => (
     is => 'ro'
    ,isa => 'DBIx::Connector'
    ,lazy => 1
    ,builder => '_build_connector'
);
sub _build_connector { die "Database not connected" if !$Ravada::CONNECTOR;
    return $Ravada::CONNECTOR;
}

############################################################
#
sub _domain_remove_db {
    my $self = shift;
    my $name = shift;
    my $sth = $self->connector->dbh->prepare("DELETE FROM domains WHERE name=?");
    $sth->execute($name);
    $sth->finish;
}

sub _domain_insert_db {
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

sub domain_remove {
    my $self = shift;
    $self->domain_remove_vm();
    $self->_domain_remove_bd();
}

1;
