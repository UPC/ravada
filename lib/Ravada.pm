package Ravada;

use warnings;
use strict;

use Data::Dumper;
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

sub remove_domain {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my $domain = $self->search_domain($name)
        or confess "ERROR: I can't find domain $name";
    $domain->remove();
}

sub search_domain {
    my $self = shift;
    my $name = shift;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain($name);
        return $domain if $domain;
    }
}

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
1;
