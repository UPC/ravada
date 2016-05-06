package Ravada;

use warnings;
use strict;

use DBIx::Connector;
use Moose;
use YAML;

use Ravada::VM::KVM;


our $FILE_CONFIG = "/etc/ravada.conf";

###########################################################################

our $CONNECTOR;
our $CONFIG = {};
_init_config($FILE_CONFIG) if -e $FILE_CONFIG;
_connect_dbh();


has 'vm' => (
          is => 'ro'
        ,isa => 'ArrayRef'
       ,lazy => 1
     , builder => '_create_vm'
);

has 'connector' => (
        is => 'ro'
);

sub BUILD {
    my $self = shift;
    $CONNECTOR = $self->connector if $self->connector;
}

sub _connect_dbh {
    my $driver= ($CONFIG->{db}->{driver} or 'mysql');;
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_pass = ($CONFIG->{db}->{password} or undef);
    return DBIx::Connector->new("DBI:$driver"
                        ,$db_user,$db_pass,{RaiseError => 1
                        , PrintError=> 0 });

}

sub _init_config {
    my $file = shift;
    $CONFIG = YAML::LoadFile($file);
    _connect_dbh();
}

sub _create_vm {
    my $self = shift;
    return [ Ravada::VM::KVM->new( connector => $self->connector ) ];
}

sub create_domain {
    my $self = shift;

    return $self->vm->[0]->create_domain(@_);
}

sub search_domain {
    my $self = shift;
    my $name = shift;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain($name);
        return $domain if $domain;
    }
}
1;
