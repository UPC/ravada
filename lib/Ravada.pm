package Ravada;

use warnings;
use strict;

use Data::Dumper;
use DBIx::Connector;
use Moose;
use YAML;

use Ravada::VM::KVM;

=head1 NAME

Ravada - Remove Virtual Desktop Manager

=head1 SYNOPSIS

  use Ravada;

  my $ravada = Ravada->new()

=cut


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
        is => 'rw'
);

has 'config' => (
    is => 'ro'
    ,isa => 'Str'
);

=head2 BUILD

Internal constructor

=cut


sub BUILD {
    my $self = shift;
    if ($self->config ) {
        _init_config($self->config);
    }
    if ( $self->connector ) {
        $CONNECTOR = $self->connector 
    } else {
        $CONNECTOR = $self->_connect_dbh();
        $self->connector($CONNECTOR);
    }

}

sub _connect_dbh {
    my $driver= ($CONFIG->{db}->{driver} or 'mysql');;
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_pass = ($CONFIG->{db}->{password} or undef);
    my $db = ( $CONFIG->{db}->{db} or 'ravada' );
    return DBIx::Connector->new("DBI:$driver:$db"
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
    return [ Ravada::VM::KVM->new( connector => ( $self->connector or $CONNECTOR )) ];
}

=head2 create_domain

Creates a new domain based on an ISO image or another domain.

  my $domain = $ravada->create_domain( 
         name => $name
    , id_iso => 1
  );


  my $domain = $ravada->create_domain( 
         name => $name
    , id_base => 3
  );


=cut


sub create_domain {
    my $self = shift;

    return $self->vm->[0]->create_domain(@_);
}

=head2 remove_domain

Removes a domain

  $ravada->remove_domain($name);

=cut

sub remove_domain {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my $domain = $self->search_domain($name)
        or confess "ERROR: I can't find domain $name";
    $domain->remove();
}

=head2 search_domain

  my $domain = $ravada->search_domain($name);

=cut

sub search_domain {
    my $self = shift;
    my $name = shift;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain($name);
        return $domain if $domain;
    }
}

=head2 list_domains

  List all created domains

  my @list = $ravada->list_domains();

=cut

sub list_domains {
    my $self = shift;
    my @domains;
    for my $vm (@{$self->vm}) {
        for my $domain ($vm->list_domains) {
            push @domains,($domain);
        }
    }
    return @domains;
}

=head2 remove_volume

  $ravada->remove_volume($file);

=cut

sub remove_volume {
    my $self = shift;

    my $file = shift;
    my ($name) = $file =~ m{.*/(.*)};

    my $removed = 0;
    for my $vm (@{$self->vm}) {
        my $vol = $vm->search_volume($name);
        next if !$vol;

        $vol->delete();
        $removed++;
    }
    if (!$removed && -e $file ) {
        warn "volume $file not found. removing file $file.\n";
        unlink $file or die "$! $file";
    }

}

=head2 process_requests

This is run in the ravada backend. It processes the commands requested by the fronted

  $ravada->process_requests();

=cut

sub process_requests {
    my $self = shift;

    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM requests WHERE status='requested'");
    $sth->execute;
    while (my ($id)= $sth->fetchrow) {
        $self->_execute(Ravada::Request->open($id));
    }
    $sth->finish;
}

sub _execute {
    my $self = shift;
    my $request = shift;

    if ($request->command() eq 'create' ) {
        $request->status('working');
        eval { $self->create_domain(%{$request->args}) };
        $request->status('done');
        $request->error($@);
    } elsif ($request->command eq 'remove') {
        $request->status('working');
        eval { $self->remove_domain($request->args('name')) };
        $request->status('done');
        $request->error($@);

    } else {
        die "Unknown command ".$request->command;
    }
}

=head1 AUTHOR

Francesc Guasch-Ortiz	, frankie@telecos.upc.edu

=head1 SEE ALSO

Sys::Virt

=cut

1;
