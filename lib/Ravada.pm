package Ravada;

use warnings;
use strict;

use Data::Dumper;
use DBIx::Connector;
use JSON::XS;
use Moose;
use YAML;

use Ravada::Request;
use Ravada::VM::KVM;
use Ravada::VM::LXC;

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
    if ($self->config()) {
        _init_config($self->config);
    } else {
        _init_config($FILE_CONFIG) if -e $FILE_CONFIG;
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

sub _create_vm_kvm {
    my $self = shift;

    my $cmd_qemu_img = `which qemu-img`;
    chomp $cmd_qemu_img;

    return(undef,"ERROR: Missing qemu-img") if !$cmd_qemu_img;

    my $vm_kvm;

    eval { $vm_kvm = Ravada::VM::KVM->new( connector => ( $self->connector or $CONNECTOR )) };
    my $err_kvm = $@;

    my ($internal_vm , $storage);
    eval {
        $internal_vm = $vm_kvm->vm;
        $internal_vm->list_all_domains();

        $storage = $vm_kvm->dir_img();
    };
    $vm_kvm = undef if $@ || !$internal_vm || !$storage;
    return ($vm_kvm,$@);
}

sub _create_vm {
    my $self = shift;

    my @vms = ();

    my ($vm_kvm, $err_kvm) = $self->_create_vm_kvm();

    push @vms,($vm_kvm) if $vm_kvm;

    my $vm_lxc;
    eval { $vm_lxc = Ravada::VM::LXC->new( connector => ( $self->connector or $CONNECTOR )) };
    push @vms,($vm_lxc) if $vm_lxc;
    my $err_lxc = $@;

    if (!@vms) {
        die "No VMs found: $err_lxc\n$err_kvm\n";
    }
    return \@vms;

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

    my $domain = $self->search_domain($name, 1)
        or confess "ERROR: I can't find domain $name";
    $domain->remove();
}

=head2 search_domain

  my $domain = $ravada->search_domain($name);

=cut

sub search_domain {
    my $self = shift;
    my $name = shift;
    my $import = shift;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain($name);
        return if !$domain;
        my $id;
        eval { $id = $domain->id };
        # TODO import the domain in the database with an _insert_db or something
        return $domain if $id || $import;
    }
    return;
}

=head2 search_domain_by_id

  my $domain = $ravada->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain_by_id($id);
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

=head2 list_domains_data

List all domains in raw format. Return a list of id => { name , id , is_active , is_base }

   my $list = $ravada->list_domains_data();

   $c->render(json => $list);

=cut

sub list_domains_data {
    my $self = shift;
    my @domains;
    for my $domain ($self->list_domains()) {
        eval { $domain->id };
        warn $@ if $@;
        next if $@;
        push @domains, {                id => $domain->id 
                                    , name => $domain->name
                                  ,is_base => $domain->is_base
                                ,is_active => $domain->is_active
                               
                           }
    }
    return \@domains;
}


=head2 list_bases

List all base domains

  my @list = $ravada->list_domains();


=cut

sub list_bases {
    my $self = shift;
    my @domains;
    for my $vm (@{$self->vm}) {
        for my $domain ($vm->list_domains) {
            eval { $domain->id };
            warn $@ if $@;
            next    if $@;
            push @domains,($domain) if $domain->is_base;
        }
    }
    return @domains;
}

=head2 list_bases_data

List information about the bases

=cut

sub list_bases_data {
    my $self = shift;
    my @data;
    for ($self->list_bases ) {
        push @data,{ id => $_->id , name => $_->name };
    }
    return \@data;
}

=head2 list_images

List all ISO images

=cut

sub list_images {
    my $self = shift;
    my @domains;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM iso_images ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @domains,($row);
    }
    $sth->finish;
    return @domains;
}

=head2 list_images_data

List information about the images

=cut

sub list_images_data {
    my $self = shift;
    my @data;
    for ($self->list_images ) {
        push @data,{ id => $_->{id} , name => $_->{name} };
    }
    return \@data;
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
        warn "Processing request $id";
        my $req = Ravada::Request->open($id);
        $self->_execute($req);
        warn $req->status();
    }
    $sth->finish;
}

=head2 list_requests

Returns a list of ruquests : ( id , domain_name, status, error )

=cut

sub list_requests {
    my $self = shift;
    my $sth = $CONNECTOR->dbh->prepare("SELECT id, args, status, error "
        ." FROM requests "
        ." WHERE status <> 'done' "
    );
    $sth->execute;
    my @reqs;
    my ($id, $j_args, $status, $error);
    $sth->bind_columns(\($id, $j_args, $status, $error));

    while ( $sth->fetch) {
        my $args = decode_json($j_args) if $j_args;

        push @reqs,{ id => $id, status => $status, error => $error , name => $args->{name}};
    }
    $sth->finish;
    return \@reqs;
}

sub _execute {
    my $self = shift;
    my $request = shift;

    my $sub = $self->_req_method($request->command);

    die "Unknown command ".$request->command
        if !$sub;

    return $sub->($self,$request);

}

sub _cmd_create {
    my $self = shift;
    my $request = shift;

    $request->status('creating domain');
    my $domain;
    eval {$domain = $self->create_domain(%{$request->args}) };

    $request->status('done');
    $request->error($@);

}

sub _cmd_remove {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    eval { $self->remove_domain($request->args('name')) };
    $request->status('done');
    $request->error($@);

}

sub _cmd_start {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $name = $request->args('name');
    eval { 
        my $domain = $self->search_domain($name);
        die "Unknown domain '$name'\n" if !$domain;
        $domain->start();
    };
    $request->status('done');
    $request->error($@);

}

sub _cmd_prepare_base {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $name = $request->args('name');
    eval { 
        my $domain = $self->search_domain($name);
        die "Unknown domain '$name'\n" if !$domain;
        $domain->prepare_base();
    };
    $request->status('done');
    $request->error($@);

}


sub _cmd_shutdown {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $name = $request->args('name');
    eval { 
        my $domain = $self->search_domain($name);
        die "Unknown domain '$name'\n" if !$domain;
        $domain->shutdown();
    };
    $request->status('done');
    $request->error($@);

}


sub _req_method {
    my $self = shift;
    my  $cmd = shift;

    my %methods = (

          start => \&_cmd_start
        ,create => \&_cmd_create
        ,remove => \&_cmd_remove
      ,shutdown => \&_cmd_shutdown
  ,prepare_base => \&_cmd_prepare_base
    );
    return $methods{$cmd};
}

=head2 search_vm

Searches for a VM of a given type

  my $vm = $ravada->search_vm('kvm');

=cut

sub search_vm {
    my $self = shift;
    my $type = shift;

    confess "Missing VM type"   if !$type;

    my $class = 'Ravada::VM::'.uc($type);
    for my $vm (@{$self->vm}) {
        return $vm if ref($vm) eq $class;
    }
    return;
}

=head1 AUTHOR

Francesc Guasch-Ortiz	, frankie@telecos.upc.edu

=head1 SEE ALSO

Sys::Virt

=cut

1;
