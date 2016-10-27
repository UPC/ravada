package Ravada;

use warnings;
use strict;

use Carp qw(carp croak);
use Data::Dumper;
use DBIx::Connector;
use Hash::Util qw(lock_hash);
use Moose;
use POSIX qw(WNOHANG);
use YAML;

use Socket qw( inet_aton inet_ntoa );
use Sys::Hostname;

use Ravada::Auth;
use Ravada::Request;
use Ravada::VM::KVM;
use Ravada::VM::Void;

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
our $DEBUG;
our $CAN_FORK = 1;
our $CAN_LXC = 0;

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
    Ravada::Auth::init($CONFIG);
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

=head2 display_ip

Returns the default display IP read from the config file

=cut

sub display_ip {
    my $ip = $CONFIG->{display_ip};
    
    return $ip if $ip;
}

sub _init_config {
    my $file = shift;

    my $connector = shift;
    confess "Deprecated connector" if $connector;

    $CONFIG = YAML::LoadFile($file);
#    $CONNECTOR = ( $connector or _connect_dbh());
}

sub _create_vm_kvm {
    my $self = shift;

    my $cmd_qemu_img = `which qemu-img`;
    chomp $cmd_qemu_img;

    return(undef,"ERROR: Missing qemu-img") if !$cmd_qemu_img;

    my $vm_kvm;

    eval { $vm_kvm = Ravada::VM::KVM->new( connector => ( $self->connector or $CONNECTOR )) };
    my $err_kvm = $@;
    return (undef, $err_kvm)    if !$vm_kvm;
    return ($vm_kvm,$err_kvm);

    my ($internal_vm , $storage);
    eval {
        $internal_vm = $vm_kvm->vm;
        $internal_vm->list_all_domains();

        $storage = $vm_kvm->dir_img();
    };
    $vm_kvm = undef if $@ || !$internal_vm || !$storage;
    $err_kvm .= ($@ or '');
    return ($vm_kvm,$err_kvm);
}

sub _refresh_vm_kvm {
    my $self = shift;
    sleep 1;
    my @vms;
    eval { @vms = $self->vm };
    warn $@ if $@;
    return if $@ && $@ =~ /No VMs found/i;
    die $@ if $@;

    return if !scalar @vms;
    for my $n ( 0 .. $#{$self->vm}) {
        my $vm = $self->vm->[$n];
        next if ref $vm !~ /KVM/i;
        warn "Refreshing VM $n $vm" if $DEBUG;
        my ($vm2, $err) = $self->_create_vm_kvm();
        $self->vm->[$n] = $vm2;
        warn $err if $err;
    }
}

sub _create_vm {
    my $self = shift;

    my @vms = ();

    my ($vm_kvm, $err_kvm) = $self->_create_vm_kvm();
    warn $err_kvm if $err_kvm && $0 !~ /\.t$/;

    my $err = $err_kvm;

    push @vms,($vm_kvm) if $vm_kvm;

    my $vm_lxc;
    if ($CAN_LXC) {
        eval { $vm_lxc = Ravada::VM::LXC->new( connector => ( $self->connector or $CONNECTOR )) };
        push @vms,($vm_lxc) if $vm_lxc;
        my $err_lxc = $@;
        $err .= "\n$err_lxc" if $err_lxc;
    }
    if (!@vms) {
        confess "No VMs found: $err\n";
    }
    return \@vms;

}

sub _check_vms {
    my $self = shift;

    my @vm;
    eval { @vm = @{$self->vm} };
    for my $n ( 0 .. $#vm ) {
        if ($vm[$n] && ref $vm[$n] =~ /KVM/i) {
            if (!$vm[$n]->is_alive) {
                warn "$vm[$n] dead" if $DEBUG;
                $vm[$n] = $self->_create_vm_kvm();
            }
        }
    }
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

    my %args = @_;

    croak "Argument id_owner required "
        if !$args{id_owner};

    my $vm_name = $args{vm};
    delete $args{vm};

    my $request = $args{request}            if $args{request};

    my $vm;
    $vm = $self->search_vm($vm_name)   if $vm_name;
    $vm = $self->vm->[0]               if !$vm;

    carp "WARNING: no VM defined, we will use ".$vm->name
        if !$vm_name;

    confess "I can't find any vm ".Dumper($self->vm) if !$vm;

    return $vm->create_domain(@_);
}

=head2 remove_domain

Removes a domain

  $ravada->remove_domain($name);

=cut

sub remove_domain {
    my $self = shift;
    my %arg = @_;

    confess "Argument name required "
        if !$arg{name};

    confess "Argument uid required "
        if !$arg{uid};

    lock_hash(%arg);

    my $domain = $self->search_domain($arg{name}, 1)
        or die "ERROR: I can't find domain '$arg{name}', maybe already removed.";

    my $user = Ravada::Auth::SQL->search_by_id( $arg{uid});
    $domain->remove( $user);
}

=head2 search_domain

  my $domain = $ravada->search_domain($name);

=cut

sub search_domain {
    my $self = shift;
    my $name = shift;
    my $import = shift;

    my $vm = $self->search_vm('Void');
    warn "No Void VM" if !$vm;
    return if !$vm;

    my $domain = $vm->search_domain($name, $import);
    return $domain if $domain;

    my @vms;
    eval { @vms = $self->vm };
    return if $@ && $@ =~ /No VMs found/i;
    die $@ if $@;

    for my $vm (@{$self->vm}) {
        my $domain = $vm->search_domain($name, $import);
        next if !$domain;
        next if !$domain->_select_domain_db && !$import;
        my $id;
        eval { $id = $domain->id };
        # TODO import the domain in the database with an _insert_db or something
        warn $@ if $@   && $DEBUG;
        return $domain if $id || $import;
    }


    return;
}

=head2 search_domain_by_id

  my $domain = $ravada->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
    my $id = shift  or confess "ERROR: missing argument id";

    my $sth = $CONNECTOR->dbh->prepare("SELECT name FROM domains WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    confess "Unknown domain id=$id" if !$name;

    return $self->search_domain($name);
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
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM domains ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @domains,($row);
    }
    $sth->finish;
    return \@domains;
}

# sub list_domains_data {
#     my $self = shift;
#     my @domains;
#     for my $domain ($self->list_domains()) {
#         eval { $domain->id };
#         warn $@ if $@;
#         next if $@;
#         push @domains, {                id => $domain->id 
#                                     , name => $domain->name
#                                   ,is_base => $domain->is_base
#                                 ,is_active => $domain->is_active
                               
#                            }
#     }
#     return \@domains;
# }


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


=pod

sub _list_images_lxc {
    my $self = shift;
    my @domains;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM lxc_templates ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @domains,($row);
    }
    $sth->finish;
    return @domains;
}

sub _list_images_data_lxc {
    my $self = shift;
    my @data;
    for ($self->list_images_lxc ) {
        push @data,{ id => $_->{id} , name => $_->{name} };
    }
    return \@data;
}

=cut

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
    my $debug = shift;
    my $dont_fork = shift;

    $self->_wait_pids_nohang();
    $self->_check_vms();

    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM requests "
        ." WHERE status='requested' OR status like 'retry %'");
    $sth->execute;
    while (my ($id)= $sth->fetchrow) {
        $self->_wait_pids_nohang();
        my $req = Ravada::Request->open($id);
        warn "executing request ".$req->id." ".$req->status()." ".$req->command
            ." ".Dumper($req->args) if $DEBUG || $debug;

        my ($n_retry) = $req->status() =~ /retry (\d+)/;
        $n_retry = 0 if !$n_retry;
        $req->status('working');
        my $err = $self->_execute($req, $dont_fork);
        $req->error($err)   if $err;
        if ($err && $err =~ /libvirt error code: 38/) {
            if ( $n_retry < 3) {
                warn $req->id." ".$req->command." to retry" if $DEBUG;
                $req->status("retry ".++$n_retry)   
            }
        }
        warn "req ".$req->id." , command: ".$req->command." , status: ".$req->status()
            ." , error: '".($req->error or 'NONE')."'" 
                if $DEBUG || $debug;

    }
    $sth->finish;
}

sub _process_requests_dont_fork {
    my $self = shift;
    my $debug = shift;
    return $self->process_requests($debug, 1);
}

=head2 list_vm_types

Returnsa list ofthe types of Virtual Machines available on this system

=cut

sub list_vm_types {
    my $self = shift;
    
    my %type;
    for my $vm (@{$self->vm}) {
            my ($name) = ref($vm) =~ /.*::(.*)/;
            $type{$name}++;
    }
    return sort keys %type;
}

sub _execute {
    my $self = shift;
    my $request = shift;
    my $dont_fork = shift;

    my $sub = $self->_req_method($request->command);

    confess "Unknown command ".$request->command
            if !$sub;

    if ($dont_fork || !$CAN_FORK ) {
        
        eval { $sub->($self,$request) };
        my $err = ($@ or '');
        $request->error($err);
        $request->status('done') if $request->status() ne 'done';
        return $err;
    }

    my $pid = fork();
    die "I can't fork" if !defined $pid;
    if ($pid == 0) {
        $request->status("forked $$");
        eval { 
            $sub->($self,$request);
        };
        my $err = ( $@ or '');
        $request->error($err);
        $request->status('done') if $request->status() ne 'done';
        exit;
    }
    $self->_add_pid($pid, $request->id);
    $self->_refresh_vm_kvm();
    return '';
}

sub _cmd_domdisplay {
    my $self = shift;
    my $request = shift;

    $request->status('working');

    my $name = $request->args('name');
    confess "Unknown name for request ".Dumper($request)  if!$name;
    my $domain = $self->search_domain($request->args->{name});
    my $user = Ravada::Auth::SQL->search_by_id( $request->args->{uid});
    $request->error('');
    my $display = $domain->display($user);
    $request->result({display => $display});

    $request->status('done');

}

sub _cmd_screenshot {
    my $self = shift;
    my $request = shift;

    my $id_domain = $request->args('id_domain');
    my $domain = $self->search_domain_by_id($id_domain);
    $request->error('');
    my $bytes = 0;
    if (!$domain->can_screenshot) {
        die "I can't take a screenshot of the domain ".$domain->name;
    } else {
        $bytes = $domain->screenshot($request->args('filename'));
        $bytes = $domain->screenshot($request->args('filename'))    if !$bytes;
    }
    $request->error("No data received") if !$bytes;
    $request->status('done');

}


sub _cmd_create{
    my $self = shift;
    my $request = shift;

    $request->status('creating domain');
    warn "$$ creating domain"   if $DEBUG;
    my $domain;

    $domain = $self->create_domain(%{$request->args},request => $request);

    my $msg = '';

    if ($domain) {
       $msg = 'Domain '
            ."<a href=\"/machine/view/".$domain->id.".html\">"
            .$request->args('name')."</a>"
            ."created."
        ;
    }

    $request->status('done',$msg);

}

sub _wait_pids_nohang {
    my $self = shift;
    return if !keys %{$self->{pids}};

    my $kid = waitpid(-1 , WNOHANG);
    return if !$kid || $kid == -1;

    $self->_set_req_done($kid);
    delete $self->{pids}->{$kid};

}

sub _set_req_done {
    my $self = shift;
    my $pid = shift;

    my $id_request = $self->{pids}->{$pid};
    return if !$id_request;

    my $req = Ravada::Request->open($id_request);
    $req->status('done')    if $req->status =~ /working/i;
}

sub _wait_pids {
    my $self = shift;
    my $request = shift;

    $request->status('waiting for other tasks')     if $request;

    for my $pid ( keys %{$self->{pids}}) {
        $request->status("waiting for pid $pid")    if $request;

#        warn "Checking for pid '$pid' created at ".localtime($self->{pids}->{$pid});
        my $kid = waitpid($pid,0);
#        warn "Found $kid";
        $self->_set_req_done($pid);

        delete $self->{pids}->{$kid};
        return if $kid  == $pid;
    }
}

sub _add_pid {
    my $self = shift;
    my $pid = shift;
    my $id_req = shift;

    $self->{pids}->{$pid} = $id_req;
}

sub _cmd_remove {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    confess "Unknown user id ".$request->args->{uid}
        if !defined $request->args->{uid};

    $self->remove_domain(name => $request->args('name'), uid => $request->args('uid'));

}

sub _cmd_pause {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $name = $request->args('name');
    my $domain = $self->search_domain($name);
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $domain->pause($user);

    $request->status('done');

}

sub _cmd_resume {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $name = $request->args('name');
    my $domain = $self->search_domain($name);
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $domain->resume($user);

    $request->status('done');

}


sub _cmd_start {
    my $self = shift;
    my $request = shift;

    $request->status("working $$");
    my $name = $request->args('name');

    my $domain = $self->search_domain($name);
    die "Unknown domain '$name'" if !$domain;

    my $uid = $request->args('uid');
    my $user = Ravada::Auth::SQL->search_by_id($uid);

    $domain->start($user);
    my $msg = 'Domain '
            ."<a href=\"/machine/view/".$domain->id.".html\">"
            .$request->args('name')."</a>"
            ."started"
        ;
    $request->status('done', $msg);

}

sub _cmd_prepare_base {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $id_domain = $request->id_domain   or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $domain->prepare_base($user);

}

sub _cmd_remove_base {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $id_domain = $request->id_domain or confess "Missing request id_domain";
    my $uid = $request->args('uid')     or confess "Missing argument uid";

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    my $domain = $self->search_domain_by_id($id_domain);

    die "Unknown domain id '$id_domain'\n" if !$domain;

    $domain->remove_base($user);

}



sub _cmd_shutdown {
    my $self = shift;
    my $request = shift;

    $request->status('working');
    my $uid = $request->args('uid');
    my $name = $request->args('name');
    my $timeout = ($request->args('timeout') or 60);

    my $domain;
    $domain = $self->search_domain($name);
    die "Unknown domain '$name'\n" if !$domain;

    my $user = Ravada::Auth::SQL->search_by_id( $uid);

    $domain->shutdown(timeout => $timeout, name => $name, user => $user);

}

sub _cmd_list_vm_types {
    my $self = shift;
    my $request = shift;
    $request->status('working');
    my @list_types = $self->list_vm_types();
    $request->result(\@list_types);
    $request->status('done');
}

sub _cmd_ping_backend {
    my $self = shift;
    my $request = shift;

    $request->status('done');
    return 1;
}

sub _req_method {
    my $self = shift;
    my  $cmd = shift;

    my %methods = (

          start => \&_cmd_start
         ,pause => \&_cmd_pause
        ,create => \&_cmd_create
        ,remove => \&_cmd_remove
        ,resume => \&_cmd_resume
      ,shutdown => \&_cmd_shutdown
    ,domdisplay => \&_cmd_domdisplay
    ,screenshot => \&_cmd_screenshot
   ,remove_base => \&_cmd_remove_base
  ,ping_backend => \&_cmd_ping_backend
  ,prepare_base => \&_cmd_prepare_base
 ,list_vm_types => \&_cmd_list_vm_types
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

    if ($type =~ /Void/i) {
        return Ravada::VM::Void->new();
    }

    my @vms;
    eval { @vms = @{$self->vm} };
    return if $@ && $@ =~ /No VMs found/i;
    die $@ if $@;

    for my $vm (@vms) {
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
