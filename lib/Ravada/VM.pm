use warnings;
use strict;

package Ravada::VM;

use Moose::Role;

requires 'connect';

# global DB Connection


# domain
requires 'domain_create';
requires 'domain_remove_vm';
requires 'prepare_base';

# storage volume
requires 'volume_create';

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
sub domain_remove_db {
    my $self = shift;
    my $name = shift;
    my $sth = $self->connector->dbh->prepare("DELETE FROM domains WHERE name=?");
    $sth->execute($name);
    $sth->finish;
}

sub domain_remove {
    my $self = shift;
    $self->domain_remove_vm();
    $self->domain_remove_bd();
}

1;
