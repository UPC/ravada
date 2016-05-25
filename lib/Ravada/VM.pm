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
requires 'search_domain_by_id';

requires 'list_domains';

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

sub domain_remove {
    my $self = shift;
    $self->domain_remove_vm();
    $self->_domain_remove_bd();
}

1;
