use warnings;
use strict;

package Ravada::VM;

use Carp qw(croak);
use Data::Dumper;
use Moose::Role;

requires 'connect';

# global DB Connection

our $CONNECTOR = \$Ravada::CONNECTOR;

# domain
requires 'create_domain';
requires 'search_domain';

requires 'list_domains';

# storage volume
requires 'create_volume';

############################################################

has 'host' => (
          isa => 'Str'
         , is => 'ro',
    , default => 'localhost'
);

has 'storage_pool' => (
     isa => 'Object'
    , is => 'ro'
);

has 'default_dir_img' => (
      isa => 'String'
     , is => 'ro'
);

has 'readonly' => (
    isa => 'Str'
    , is => 'ro'
    ,default => 0
);
############################################################
#
# Method Modifiers
# 
#
before 'create_domain' => \&_check_readonly;

sub _check_readonly {
    my $self = shift;
    confess "ERROR: You can't create domains in read-only mode "
        if $self->readonly 

}

############################################################
#
sub _domain_remove_db {
    my $self = shift;
    my $name = shift;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains WHERE name=?");
    $sth->execute($name);
    $sth->finish;
}

sub domain_remove {
    my $self = shift;
    $self->domain_remove_vm();
    $self->_domain_remove_bd();
}

sub name {
    my $self = shift;

    my ($ref) = ref($self) =~ /.*::(.*)/;

    return ($ref or ref($self));
}

=head2 search_domain_by_id

Returns a domain searching by its id

    $domain = $vm->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains "
        ." WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return if !$name;

    return $self->search_domain($name);
}


1;
