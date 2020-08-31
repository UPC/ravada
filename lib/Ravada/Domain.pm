package Ravada::Domain;

use warnings;
use strict;

=head1 NAME

Ravada::Domain - Domains ( Virtual Machines ) library for Ravada

=cut

use Carp qw(carp confess croak cluck);
use Data::Dumper;
use File::Copy qw(copy move);
use File::Rsync;
use Hash::Util qw(lock_hash unlock_hash);
use Image::Magick;
use JSON::XS;
use Moose::Role;
use NetAddr::IP;
use IPC::Run3 qw(run3);
use Time::Piece;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Domain::Driver;
use Ravada::Utils;

our $TIMEOUT_SHUTDOWN = 20;
our $CONNECTOR;

our $MIN_FREE_MEMORY = 1024*1024;
our $IPTABLES_CHAIN = 'RAVADA';

our %PROPAGATE_FIELD = map { $_ => 1} qw( run_timeout shutdown_disconnected);

our $TIME_CACHE_NETSTAT = 60; # seconds to cache netstat data output
our $RETRY_SET_TIME=10;

_init_connector();

requires 'name';
requires 'remove';
requires 'display_info';

requires 'is_active';
requires 'is_hibernated';
requires 'is_paused';
requires 'is_removed';

requires 'start';
requires 'shutdown';
requires 'shutdown_now';
requires 'force_shutdown';
requires '_do_force_shutdown';

requires 'pause';
requires 'resume';

requires 'rename';
requires 'dettach';
requires 'set_time';

#storage
requires 'add_volume';
requires 'remove_volume';
requires 'list_volumes';
requires 'list_volumes_info';

requires 'disk_device';

requires 'disk_size';

#hardware info

requires 'get_info';
requires 'set_memory';
requires 'set_max_mem';

requires 'autostart';
requires 'hybernate';
requires 'hibernate';

#remote methods
requires 'migrate';

requires 'get_driver';
requires 'get_controller_by_name';
requires 'list_controllers';
requires 'set_controller';
requires 'remove_controller';
requires 'change_hardware';
#
##########################################################

has 'domain' => (
    isa => 'Any'
    ,is => 'rw'
);

has 'timeout_shutdown' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => $TIMEOUT_SHUTDOWN
);

has 'readonly' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => 0
);

has 'storage' => (
    is => 'ro'
    ,isa => 'Object'
    ,required => 0
);

has '_vm' => (
    is => 'rw',
    ,isa => 'Object'
    ,required => 0
);

has 'description' => (
    is => 'rw'
    ,isa => 'Str'
    ,required => 0
    ,trigger => \&_update_description
);

##################################################################################3
#


##################################################################################3
#
# Method Modifiers
#

around 'display_info' => \&_around_display_info;
around 'display_file_tls' => \&_around_display_file_tls;

around 'add_volume' => \&_around_add_volume;
around 'remove_volume' => \&_around_remove_volume;
around 'list_volumes_info' => \&_around_list_volumes_info;

before 'remove' => \&_pre_remove_domain;
#\&_allow_remove;
 after 'remove' => \&_after_remove_domain;

around 'prepare_base' => \&_around_prepare_base;
#before 'prepare_base' => \&_pre_prepare_base;
# after 'prepare_base' => \&_post_prepare_base;

#before 'start' => \&_start_preconditions;
# after 'start' => \&_post_start;
around 'start' => \&_around_start;

before 'pause' => \&_allow_shutdown;
 after 'pause' => \&_post_pause;

before 'hybernate' => \&_allow_shutdown;
 after 'hybernate' => \&_post_hibernate;

before 'hibernate' => \&_allow_shutdown;
 after 'hibernate' => \&_post_hibernate;

before 'resume' => \&_allow_manage;
 after 'resume' => \&_post_resume;

before 'shutdown' => \&_pre_shutdown;
after 'shutdown' => \&_post_shutdown;

around 'shutdown_now' => \&_around_shutdown_now;
around 'force_shutdown' => \&_around_shutdown_now;

before 'remove_base' => \&_pre_remove_base;
after 'remove_base' => \&_post_remove_base;
after 'spinoff' => \&_post_spinoff;

before 'rename' => \&_pre_rename;
after 'rename' => \&_post_rename;

after 'dettach' => \&_post_dettach;

before 'clone' => \&_pre_clone;

after 'screenshot' => \&_post_screenshot;

after '_select_domain_db' => \&_post_select_domain_db;

before 'migrate' => \&_pre_migrate;
after 'migrate' => \&_post_migrate;

around 'get_info' => \&_around_get_info;
around 'set_max_mem' => \&_around_set_max_mem;
around 'set_memory' => \&_around_set_memory;

around 'is_active' => \&_around_is_active;

around 'is_hibernated' => \&_around_is_hibernated;

around 'autostart' => \&_around_autostart;

before 'set_controller' => \&_pre_change_hardware;
before 'remove_controller' => \&_pre_change_hardware;
before 'change_hardware' => \&_pre_change_hardware;

after 'set_controller' => \&_post_change_hardware;
after 'remove_controller' => \&_post_change_hardware;
after 'change_hardware' => \&_post_change_hardware;

around 'name' => \&_around_name;

##################################################
#

sub BUILD {
    my $self = shift;
    my $args = shift;

    my $name;
    $name = $args->{name}               if exists $args->{name};

    $self->{_name} = $name  if $name;

    $self->_init_connector();

    $self->is_known();
}

sub _check_clean_shutdown($self) {
    return if !$self->is_known || $self->readonly || $self->is_volatile;

    if (( $self->_data('status') eq 'active' && !$self->is_active )
        || $self->_active_iptables(id_domain => $self->id)) {
            $self->_post_shutdown();
    }
}

sub _set_last_vm($self,$force=0) {
    my $id_vm;
    $id_vm = $self->_data('id_vm')  if $self->is_known();
    return $self->_set_vm($id_vm, $force)   if $id_vm;
}

sub _set_vm($self, $vm, $force=0) {
    if (!ref($vm)) {
        $vm = Ravada::VM->open($vm);
    }

    my $domain;
    eval { $domain = $vm->search_domain($self->name) };
    die $@ if $@ && $@ !~ /no domain with matching name/;
    if ($domain && ($force || $domain->is_active)) {
       $self->_vm($vm);
       $self->domain($domain->domain);
        $self->_update_id_vm();
    }
    return $vm->id;

}

sub _check_equal_storage_pools($self, $vm2) {
    my $vm1 = $self->_vm;
    my @sp;
    push @sp,($vm1->default_storage_pool_name)  if $vm1->default_storage_pool_name;
    push @sp,($vm1->base_storage_pool)  if $vm1->base_storage_pool;
    push @sp,($vm1->clone_storage_pool) if $vm1->clone_storage_pool;

    my %sp1 = map { $_ => 1 } @sp;

    my @sp1 = grep /./,keys %sp1;

    my %sp2 = map { $_ => 1 } $vm2->list_storage_pools();

    for my $pool ( @sp1 ) {
        next if $sp2{ $pool };
        die "Error: Storage pool '$pool' not found on node ".$vm2->name."\n"
            .Dumper([keys %sp2]);
    }
    return 1;
}

sub _vm_connect {
    my $self = shift;
    $self->_vm->connect();
}

sub _vm_disconnect {
    my $self = shift;
    $self->_vm->disconnect();
}

sub _around_start($orig, $self, @arg) {

    $self->_start_preconditions(@arg);

    my %arg;
    if (!(scalar(@arg) % 2) ) {
        %arg = @arg;
    } else {
        $arg{user} = $arg[0];
    }

    my $listen_ip = delete $arg{listen_ip};
    my $remote_ip = $arg{remote_ip};

    for (;;) {
        eval { $self->_start_checks(@arg) };
        my $error = $@;
        if ($error) {
            if ( $error =~/base file not found/ && !$self->_vm->is_local) {
                $self->_request_set_base();
                next;
            } elsif ($error =~ /No free memory/) {
                warn $error;
                die $error if $self->is_local;
                my $vm_local = $self->_vm->new( host => 'localhost' );
                $self->migrate($vm_local);
                next;
            }
        }
        die $error if $error;
        if (!defined $listen_ip) {
            my $display_ip;
            if ($remote_ip) {
                my $set_password = 0;
                my $network = Ravada::Network->new(address => $remote_ip);
                $set_password = 1 if $network->requires_password();
                $display_ip = $self->_listen_ip($remote_ip);
                $arg{set_password} = $set_password;
            } else {
                $display_ip = $self->_listen_ip();
            }
            $arg{listen_ip} = $display_ip;
        }
        $$CONNECTOR->disconnect;
        eval { $self->$orig(%arg) };
        $error = $@;
        last if !$error;
        warn "WARNING: $error ".$self->_vm->name." ".$self->_vm->enabled if $error;
        if ($error && $self->id_base && !$self->is_local && $self->_vm->enabled) {
            $self->_request_set_base();
            next;
        }
        die $@;
    }
    $self->_post_start(%arg);

}

sub _request_set_base($self) {
    my $base = Ravada::Domain->open($self->id_base);
    $base->_set_base_vm_db($self->_vm->id,0);
    Ravada::Request->set_base_vm(
        uid => Ravada::Utils::user_daemon->id
        ,id_domain => $base->id
        ,id_vm => $self->_vm->id
    );
    my $vm_local = $self->_vm->new( host => 'localhost' );
    $self->_set_vm($vm_local, 1);
}

sub _start_preconditions{
    my ($self) = @_;

    die "Domain ".$self->name." is a base. Bases can't get started.\n"
        if $self->is_base();

    my $request;
    my $id_vm;
    if (scalar @_ %2 ) {
        my @args = @_;
        shift @args;
        my %args = @args;
        my $user = delete $args{user};
        my $remote_ip = delete $args{remote_ip};
        $request = delete $args{request} if exists $args{request};
        $id_vm = delete $args{id_vm};

        confess "ERROR: Unknown argument ".join("," , sort keys %args)
            ."\n\tknown: remote_ip, user"   if keys %args;
        _allow_manage_args(@_);
    } else {
        _allow_manage(@_);
    }
    #_check_used_memory(@_);
    $self->status('starting');
}

sub _start_checks($self, @args) {
    return if $self->_search_already_started('fast');
    my $vm_local = $self->_vm->new( host => 'localhost' );
    my $vm = $vm_local;

    my ($id_vm, $request);
    if (!scalar(@args) % 2) {
        my %args = @args;

        # We may be asked to start the machine in a specific id_vmanager
        $id_vm = delete $args{id_vm};
        $request = delete $args{request} if exists $args{request};
    }
    # If not specific id_manager we go to the last id_vmanager unless it was localhost
    # If the last VManager was localhost it will try to balance here.
    $id_vm = $self->_data('id_vm')
    if !$id_vm && defined $self->_data('id_vm')
    && $self->_data('id_vm') != $vm_local->id;

    if ($id_vm) {
        $vm = Ravada::VM->open($id_vm);
        if ( !$vm->enabled || !$vm->ping ) {
            $vm = $vm_local;
            $id_vm = undef;
        }
    }

    # if it is a clone ( it is not a base )
    if ($self->id_base) {
        $self->_check_tmp_volumes();
#        $self->_set_last_vm(1)
        if ( !$self->is_local
            && ( !$self->_vm->enabled || !base_in_vm($self->id_base,$self->_vm->id)
                || !$self->_vm->ping) ) {
            $self->_set_vm($vm_local, 1);
        }
        if ( !$vm->is_alive ) {
            $vm->disconnect();
            $vm->connect;
            $vm = $vm_local if !$vm->is_local && !$vm->is_alive;
        };
        if ($id_vm) {
            $self->_set_vm($vm);
        } else {
            $self->_balance_vm();
        }
        $self->rsync(request => $request)  if !$self->is_volatile && !$self->_vm->is_local();
    } elsif (!$self->is_local) {
        $self->_set_vm($vm_local, 1);
    }
    $self->_check_free_vm_memory();
    #TODO: remove them and make it more general now we have nodes
    #$self->_check_cpu_usage($request);
}

sub _search_already_started($self, $fast = 0) {
    my $sql = "SELECT id FROM vms where vm_type=?";
    $sql .= " AND is_active=1" if $fast;
    my $sth = $$CONNECTOR->dbh->prepare($sql);
    $sth->execute($self->_vm->type);
    my %started;
    while (my ($id) = $sth->fetchrow) {
        my $vm = Ravada::VM->open($id);
        next if !$vm->enabled;

        my $vm_active;
        eval {
            $vm_active = $vm->is_active;
        };
        my $error = $@;
        if ($error) {
            warn $error;
            $vm->enabled(0) if !$vm->is_local;
            next;
        }
        next if !$vm_active;

        my $domain;
        eval { $domain = $vm->search_domain($self->name) };
        if ( $@ ) {
            warn $@;
            $vm->enabled(0) if !$vm->is_local;
            next;
        }
        next if !$domain;
        if ( $domain->is_active || $domain->is_hibernated ) {
            $self->_set_vm($vm,'force');
            $started{$vm->id}++;

            my $status = 'shutdown';
            $status = 'active'  if $domain->is_active;
            $domain->_data(status => $status);
        }
    }
    if (keys %started > 1) {
        for my $id_vm (sort keys %started) {
            Ravada::Request->shutdown_domain(
                id_domain => $self->id
                , uid => $self->id_owner
                , id_vm => $id_vm
                ,timeout => $TIMEOUT_SHUTDOWN
            );
        }
    }
    return keys %started;
}

sub _balance_vm($self) {
    return if $self->{_migrated};

    my $base;
    $base = Ravada::Domain->open($self->id_base) if $self->id_base;

    my $vm_free;
    for (;;) {
        $vm_free = $self->_vm->balance_vm($base);
        return if !$vm_free;

        last if $vm_free->id == $self->_vm->id;
        eval { $self->migrate($vm_free) };
        last if !$@;
        if ($@ && $@ =~ /file not found/i) {
            $base->_set_base_vm_db($vm_free->id,0) unless $vm_free->is_local;
            Ravada::Request->set_base_vm(
                uid => Ravada::Utils::user_daemon->id
                ,id_domain => $base->id
                ,id_vm => $vm_free->id
            );
            next;
        }
        die $@;
    }
    return $vm_free->id;
}

sub _update_description {
    my $self = shift;

    return if defined $self->description
        && defined $self->_data('description')
        && $self->description eq $self->_data('description');

    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains SET description=? "
        ." WHERE id=? ");
    $sth->execute($self->description,$self->id);
    $sth->finish;
    $self->{_data}->{description} = $self->{description};
}

sub _allow_manage_args {
    my $self = shift;

    confess "Disabled from read only connection"
        if $self->readonly;

    my %args = @_;

    confess "Missing user arg ".Dumper(\%args)
        if !$args{user} ;

    $self->_allowed($args{user});

}
sub _allow_manage {
    my $self = shift;

    return $self->_allow_manage_args(@_)
        if scalar(@_) % 2 == 0;

    my ($user) = @_;
    return $self->_allow_manage_args( user => $user);

}

sub _allow_remove($self, $user) {

    confess "ERROR: Undefined user" if !defined $user;

    return if !$self->is_known(); # already removed

    confess "Error: arg user is not Ravada::Auth object" if !ref($user);

    die "ERROR: remove not allowed for user ".$user->name
        unless $user->can_remove_machine($self);

    $self->_check_has_clones() if $self->is_known();
    if ( $self->is_known
        && $self->id_base
        && ($user->can_remove_clones() || $user->can_remove_clone_all())
    ) {
        my $base = $self->open(id => $self->id_base, id_vm => $self->_vm->id);
        return if ($user->can_remove_clone_all() || ($base->id_owner == $user->id));
    }

}

sub _allow_shutdown {
    my $self = shift;
    my %args;

    if (scalar @_ == 1 ) {
        $args{user} = shift;
    } else {
        %args = @_;
    }
    my $user = $args{user} || confess "ERROR: Missing user arg";

    if ( $self->id_base() && $user->can_shutdown_clone()) {
        my $base = Ravada::Domain->open($self->id_base)
            or confess "ERROR: Base domain id: ".$self->id_base." not found";
        return if $base->id_owner == $user->id;
    } elsif($user->can_shutdown_all) {
        return;
    }
    confess "User ".$user->name." [".$user->id."] not allowed to shutdown ".$self->name
        ." owned by ".($self->id_owner or '<UNDEF>')
            if !$user->can_shutdown($self->id);
}

sub _around_add_volume {
    my $orig = shift;
    my $self = shift;
    confess "ERROR in args ".Dumper(\@_)
        if scalar @_ % 2;
    my %args = @_;

    my $file = ($args{file} or $args{path});
    confess if $args{id_iso} && !$file;
    my $name = $args{name};
    $args{target} = $self->_new_target_dev() if !exists $args{target};

    if (!$name) {
        ($name) = $file =~ m{.*/(.*)} if !$name && $file;
        $name = $self->name if !$name;

        $name .= "-".$args{target}."-".Ravada::Utils::random_name(4);
        $args{name} = $name;
    }

    $args{size} = delete $args{capacity} if exists $args{capacity} && !exists $args{size};
    my $size = $args{size};
    if ( $file ) {
        $self->_check_volume_added($file);
    }
    $args{size} = Ravada::Utils::size_to_number($size) if defined $size;
    $args{allocation} = Ravada::Utils::size_to_number($args{allocation})
        if exists $args{allocation} && defined $args{allocation};

    my $free = $self->_vm->free_disk();
    my $free_out = int($free / 1024 / 1024 / 1024 ) * 1024 *1024 *1024;

    confess "Error creating volume, out of space $size . Disk free: "
            .Ravada::Utils::number_to_size($free_out)
            ."\n"
        if exists $args{size} && $args{size} >= $free;

    if ($name) {
        confess "Error: volume $name already exists"
            if grep {$_->info->{name} eq $name} $self->list_volumes_info;
    }
    confess "Error: target $args{target} already exists"
            if grep {$_->info->{target} eq $args{target} } $self->list_volumes_info;

    my $ok = $self->$orig(%args);
    confess "Error adding ".Dumper(\%args) if !$ok;

    return $ok;
}

sub _check_volume_added($self, $file) {
    return if $file =~ /\.iso$/i;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,id_domain FROM volumes "
        ." WHERE file=? or name=?"
    );
    $sth->execute($file,$file);
    my ($id, $id_domain) = $sth->fetchrow();
    $sth->finish;

    return if !$id;

    confess "Volume $file already in domain id $id_domain, this is ".$self->id;
}

sub _around_remove_volume {
    my $orig = shift;
    my $self = shift;
    my ($file) = @_;

    my $ok = $self->$orig(@_);

    return $ok if !$self->is_local;

    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM volumes "
        ." WHERE id_domain=? AND file=?"
    );
    $sth->execute($self->id, $file);
    return $ok;
}

sub _around_list_volumes_info($orig, $self, $attribute=undef, $value=undef) {
    confess "Error: value must be supplied for filter attribute"
    if defined $attribute && !defined $value;

    return $self->$orig($attribute, $value) if ref($self) =~ /^Ravada::Front/i;

    my @volumes = $self->$orig($attribute => $value);

    return @volumes;
}

sub _around_prepare_base($orig, $self, @args) {
    #sub _around_prepare_base($orig, $self, $user, $request = undef) {
    my ($user, $request, $with_cd);
    if(ref($args[0]) =~/^Ravada::/) {
        ($user, $request) = @args;
    } else {
        my %args = @args;
        $user = delete $args{user};
        $request = delete $args{request};
        $with_cd = delete $args{with_cd};
        confess "Error: uknown args". Dumper(\%args) if keys %args;
    }
    $self->_pre_prepare_base($user, $request);

    if (!$self->is_local) {
        my $vm_local = $self->_vm->new( host => 'localhost' );
        $self->_vm($vm_local);
    }
    $self->pre_prepare_base();
    my @base_img = $self->$orig($with_cd);

    die "Error: No information files returned from prepare_base"
        if !scalar (\@base_img);

    $self->_prepare_base_db(@base_img);

    $self->_post_prepare_base($user, $request);
}

sub pre_prepare_base($self) {}

=head2 prepare_base

Prepares the virtual machine as a base:

=over

=item * shuts it down

=item * creates read only volumes based on this base

=item * locks it so it won't get started

=item * stores the virtual machine template for the clones

=cut

sub prepare_base($self, $with_cd) {
    my @base_img;
    for my $volume ($self->list_volumes_info()) {
        my $base_file = $volume->base_filename;
        next if !$base_file || $base_file =~ /\.iso$/;
        confess "Error: file '$base_file' already exists in ".$self->_vm->name
            if $self->_vm->file_exists($base_file);
    }

    for my $volume ($self->list_volumes_info()) {
        next if !$volume->info->{target} && $volume->info->{device} eq 'cdrom';
        next if $volume->info->{device} eq 'cdrom' && !$with_cd;
        confess "Undefined info->target ".Dumper($volume)
            if !$volume->info->{target};

        my $base = $volume->prepare_base();
        push @base_img,([$base, $volume->info->{target}]);
    }
    $self->post_prepare_base();
    return @base_img;
}

=head2 post_prepare_base

Placeholder for optional method implemented in subclasses. This will
run after preparing the base files.

=cut

sub post_prepare_base($self) {}

sub _pre_prepare_base($self, $user, $request = undef ) {

    $self->_allowed($user);

    my $owner = Ravada::Auth::SQL->search_by_id($self->id_owner);
    confess "User ".$user->name." [".$user->id."] not allowed to prepare base ".$self->domain
        ." owned by ".($owner->name or '<UNDEF>')."\n"
            unless $user->is_admin || (
                $self->id_owner == $user->id && $user->can_create_base());


    # TODO: if disk is not base and disks have not been modified, do not generate them
    # again, just re-attach them 
#    $self->_check_disk_modified(
    confess "ERROR: domain ".$self->name." is already a base" if $self->is_base();
    $self->_check_has_clones();

    $self->is_base(0);
    if ($self->is_active) {
        $self->shutdown(user => $user);
        for ( 1 .. $TIMEOUT_SHUTDOWN ) {
            last if !$self->is_active;
            sleep 1;
        }
        if ($self->is_active ) {
            $request->status('working'
                    ,"Domain ".$self->name." still active, forcing hard shutdown")
                if $request;
            $self->force_shutdown($user);
            sleep 1;
        }
    }
    $self->_post_remove_base();
    if (!$self->is_local) {
        my $vm_local = Ravada::VM->open( type => $self->vm );
        $self->migrate($vm_local);
    }
    if ($self->id_base ) {
        $self->spinoff();
    }
    $self->_check_free_space_prepare_base();
}

sub _check_free_space_prepare_base($self) {
    my $pool_base = $self->_vm->default_storage_pool_name;
    $pool_base = $self->_vm->base_storage_pool()   if $self->_vm->base_storage_pool();

    for my $volume ($self->list_volumes_info(device => 'disk')) {;
        $self->_vm->_check_free_disk($volume->capacity * 2, $pool_base);
    }
};

sub _post_prepare_base {
    my $self = shift;

    my ($user) = @_;

    $self->is_base(1);

    if ($self->id_base && !$self->description()) {
        my $base = Ravada::Domain->open($self->id_base);
        $self->description($base->description)  if $base->description();
    }

    $self->_remove_id_base();
    $self->_set_base_vm_db($self->_vm->id,1);
    $self->autostart(0,$user);
};

=pod

=head2 spinoff

Makes volumes indpendent from base

=cut

sub spinoff {
    my $self = shift;

    $self->_do_force_shutdown() if $self->is_active;
    confess "Error: spinoff from remote nodes not available. Node: ".$self->_vm->name
        if !$self->is_local;

    for my $volume ($self->list_volumes_info ) {
        next if !$volume->file || $volume->file =~ /\.iso$/i;
        my $bf;
        eval { $bf = $volume->backing_file };
        die $@ if $@ && $@ !~ /No backing file/;
        next if !$bf;
        $volume->spinoff;
    }
}


sub _around_autostart($orig, $self, @arg) {
    my ($value, $user) = @arg;
    $self->_allowed($user) if defined $value;
    confess "ERROR: Autostart can't be activated on base ".$self->name
        if $value && $self->is_base;

    confess "ERROR: You can't set autostart on readonly domains"
        if defined $value && $self->readonly;
    my $autostart = 0;
    my @orig_args = ();
    push @orig_args, ( $value) if defined $value;

    # We only set the internal autostart when domain is not in nodes
    if ($self->_domain_in_nodes) {
        if (defined $value) {
            $autostart = $value;
        } else {
            $autostart = $self->_data('autostart');
        }
    } elsif ( $self->$orig(@orig_args) ) {
        $autostart = 1;
    }
    $self->_data(autostart => $autostart)   if defined $value;
    return $autostart;
}

sub _check_has_clones {
    my $self = shift;
    return if !$self->is_known();

    my @clones = $self->clones;
    confess "Domain ".$self->name." has ".scalar @clones." clones : ".Dumper(\@clones)
        if $#clones>=0;
}

sub _check_free_vm_memory {
    my $self = shift;

    my $vm_free_mem = $self->_vm->free_memory;

    my $domain_memory = $self->info(Ravada::Utils::user_daemon)->{memory};
    my $min_free_memory = ($self->_vm->min_free_memory or $MIN_FREE_MEMORY)+$domain_memory;

    return if $vm_free_mem > $min_free_memory;

    $self->_data(status => 'down');

    my $msg = "Error: No free memory in ".$self->_vm->name.". Only "._gb($vm_free_mem)." out of "
        ._gb($min_free_memory)." GB required.\n";

    die $msg;
}

sub _check_tmp_volumes($self) {
    confess "Error: only clones temporary volumes can be checked."
        if !$self->id_base;
    my $vm_local = $self->_vm->new( host => 'localhost' );
    for my $vol ( $self->list_volumes_info) {
        next unless $vol->file && $vol->file =~ /\.(TMP|SWAP)\./;
        next if $vm_local->file_exists($vol->file);
        $vol->delete();

        my $base = Ravada::Domain->open($self->id_base);
        my @volumes = $base->list_files_base_target;
        my ($file_base) = grep { $_->[1] eq $vol->info->{target} } @volumes;
        if (!$file_base) {
            warn "Error: I can't find base volume for target ".$vol->info->{target}
                .Dumper(\@volumes);
        }
        my $vol_base = Ravada::Volume->new( file => $file_base->[0]
            , is_base => 1
            , vm => $vm_local
        );
        $vol_base->clone(file => $vol->file);
    }
}

sub _check_cpu_usage($self, $request=undef){

    return if ref($self) =~ /Void/i;
    if ($self->_vm->active_limit){
        chomp(my $cpu_count = `grep -c -P '^processor\\s+:' /proc/cpuinfo`);
        die "Error: Too many active domains." if (scalar $self->_vm->vm->list_domains() >= $self->_vm->active_limit);
    }
    
    my @cpu;
    my $msg;
    for ( 1 .. 10 ) {
        open( my $stat ,'<','/proc/loadavg') or die "WTF: $!";
        @cpu = split /\s+/, <$stat>;
        close $stat;

        if ( $cpu[0] < $self->_vm->max_load ) {
            $request->error('') if $request;
            return;
        }
        $msg = "Error: CPU Too loaded. ".($cpu[0])." out of "
        	.$self->_vm->max_load." max specified.";
        $request->error($msg)   if $request;
        die "$msg\n" if $cpu[0] > $self->_vm->max_load +1;
        sleep 1;
    }
    die "$msg\n";
}

sub _gb($mem=0) {
    my $gb = $mem / 1024 / 1024 ;

    $gb =~ s/(\d+\.\d).*/$1/;
    return ($gb);

}

=pod

sub _check_disk_modified {
    my $self = shift;

    if ( !$self->is_base() ) {
        return;
    }

    my $last_stat_base = 0;
    for my $file_base ( $self->list_files_base ) {
        my @stat_base = stat($file_base);
        $last_stat_base = $stat_base[9] if$stat_base[9] > $last_stat_base;
#        warn $last_stat_base;
    }

    my $files_updated = 0;
    for my $file ( $self->disk_device ) {
        my @stat = stat($file) or next;
        $files_updated++ if $stat[9] > $last_stat_base;
#        warn "\ncheck\t$file ".$stat[9]."\n vs \tfile_base $last_stat_base $files_updated\n";
    }
    die "Base already created and no disk images updated"
        if !$files_updated;
}

=cut

sub _allowed {
    my $self = shift;

    my ($user) = @_;

    confess "Missing user"  if !defined $user;
    confess "ERROR: User '$user' not class user , it is ".(ref($user) or 'SCALAR')
        if !ref $user || ref($user) !~ /Ravada::Auth/;

    return if $user->is_admin;
    my $id_owner;
    eval { $id_owner = $self->id_owner };
    my $err = $@;

    confess "User ".$user->name." [".$user->id."] not allowed to access ".$self->name
        ." owned by ".($id_owner or '<UNDEF>')
            if (defined $id_owner && $id_owner != $user->id );

    confess $err if $err;

}

sub _around_display_info($orig,$self,$user ) {
    $self->_allowed($user);
    my $display = $self->$orig($user);

    if (!$self->readonly) {
        $self->_set_display_ip($display);
        $self->_data(display => encode_json($display)) if $self->is_active;
    }
    return $display;
}

sub _set_display_ip($self, $display) {

    my $new_ip = ( $self->_vm->nat_ip
            or $self->_vm->public_ip
            or Ravada::display_ip()
    );
    unlock_hash(%$display);
    $display->{listen_ip} = $display->{ip};

    if ( $new_ip ) {
        $display->{ip} = $new_ip;
        $display->{display} =~ s{(\w+)://(.*?):(.*)}{$1://$new_ip:$3};
    }

    lock_hash(%$display);
}

sub _around_get_info($orig, $self) {
    my $info = $self->$orig();
    if (ref($self) =~ /^Ravada::Domain/ && $self->is_known()) {
        $info->{ip} = $self->ip() if $self->is_active;
        $self->_data(info => encode_json($info));
    }
    return $info;
}

sub _around_set_memory($orig, $self, $value) {
    my $ret = $self->$orig($value);
    if ($self->is_known) {
        my $info;
        eval { $info = decode_json($self->_data('info')) if $self->_data('info')};
        warn $@ if $@ && $@ !~ /malformed JSON/i;
        $info->{memory} = $value;
        $self->_data(info => encode_json($info));
    }
    return $ret;
}

sub _around_set_max_mem($orig, $self, $value) {
    my $ret = $self->$orig($value);
    if ($self->is_known) {
        my $info;
        eval { $info = decode_json($self->_data('info')) if $self->_data('info')};
        warn $@ if $@ && $@ !~ /malformed JSON/i;
        $info->{max_mem} = $value;
        $self->_data(info => encode_json($info))
    }
    return $ret;
}

##################################################################################3

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

=head2 id
Returns the id of  the domain
    my $id = $domain->id();
=cut

sub id($self) {
    return $self->{_id} if exists $self->{_id};
    my $id = $_[0]->_data('id');
    $self->{_id} = $id;
    return $id;
}


##################################################################################

sub _execute_request($self, $field, $value) {
    my %req = (
        pools => 'manage_pools'
        ,pool_start => 'manage_pools'
        ,pool_clones => 'manage_pools'
    );
    my $exec = $req{$field} or return;

    Ravada::Request->_new_request(
        command => $exec
        ,args => { id_domain => $self->id , uid => Ravada::Utils::user_daemon->id }
    );
}

sub _data($self, $field, $value=undef, $table='domains') {

    _init_connector();

    my $data = "_data";
    my $field_id = 'id';
    if ($table ne 'domains' ) {
        $data = "_data_$table";
        $field_id = 'id_domain';
    }

    if (defined $value) {
        confess "Domain ".$self->name." is not in the DB"
            if !$self->is_known();

        confess "ERROR: Invalid field '$field'"
            if $field !~ /^[a-z]+[a-z0-9_]*$/;

        $self->_assert_update($table, $field => $value);
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE $table set $field=? WHERE $field_id=?"
        );
        $sth->execute($value, $self->id);
        $sth->finish;
        $self->{$data}->{$field} = $value;
        $self->_propagate_data($field,$value) if $PROPAGATE_FIELD{$field};
        $self->_execute_request($field,$value);
    }
    return $self->{$data}->{$field} if exists $self->{$data}->{$field};

    my @field_select;
    if ($table eq 'domains' ) {
        if (exists $self->{_data}->{id} ) {
            @field_select = ( id => $self->{_data}->{id});
        } else {
            confess "ERROR: Unknown domain" if ref($self) =~ /^Ravada::Front::Domain/;
            @field_select = ( name => $self->name );
        }
    } else {
        @field_select = ( id_domain => $self->id );
    }

    $self->{$data} = $self->_select_domain_db( _table => $table, @field_select );

    confess "No DB info for domain @field_select in $table ".$self->name 
        if ! exists $self->{$data};
    confess "No field $field in $data ".Dumper(\@field_select)."\n".Dumper($self->{$data})
        if !exists $self->{$data}->{$field};

    return $self->{$data}->{$field};
}

sub _data_extra($self, $field, $value=undef) {
    $self->_insert_db_extra()   if !$self->is_known_extra();
    return $self->_data($field, $value, "domains_".lc($self->type));
}

sub _assert_update($self, $table, $field, $value) {
    return if $table =~ /extra$/;
    if ($field eq 'is_base' && !$value && $self->clones ) {
        confess "Error: You can set $field=$value if there are clones";
    }
}

=head2 open

Open a domain

Argument: id
Arguments: id => $id , [ readonly => {0|1} ]

Returns: Domain object

=cut

sub open($class, @args) {
    my ($id) = @args;
    my $readonly = 0;
    my $id_vm;
    my $force;
    my $vm;
    if (scalar @args > 1) {
        my %args = @args;
        $id = delete $args{id} or confess "ERROR: Missing field id";
        $readonly = delete $args{readonly} if exists $args{readonly};
        $id_vm = delete $args{id_vm};
        $force = delete $args{_force};
        $vm = delete $args{vm};
        confess "ERROR: id_vm and vm don't match. ".($vm->name." id: ".$vm->id)
            if $id_vm && $vm && $vm->id != $id_vm;
        confess "ERROR: Unknown fields ".join(",", sort keys %args)
            if keys %args;
    }
    confess "Undefined id"  if !defined $id;
    my $self = {};

    if (ref($class)) {
        $self = $class;
    } else {
        bless $self,$class
    }

    my $row = $self->_select_domain_db ( id => $id );

    die "ERROR: Domain not found id=$id\n"
        if !keys %$row;

    if (!$vm && ( $id_vm || defined $row->{id_vm} ) ) {
        eval {
            $vm = Ravada::VM->open(id => ( $id_vm or $row->{id_vm} )
                , readonly => $readonly);
        };
        warn $@ if $@;
        if ($@ && $@ =~ /I can't find VM id=/) {
            $vm = Ravada::VM->open( type => $self->type );
        }
    }
    my $vm_local;
    if ( !$vm || !$vm->is_active ) {
        $vm_local = {};
        my $vm_class = "Ravada::VM::".$row->{vm};
        bless $vm_local, $vm_class;

        $vm = $vm_local->new( );
    }
    my $domain;
    eval { $domain = $vm->search_domain($row->{name}, $force) };
    if ( !$domain ) {
        return if $vm->is_local;

        $vm_local = {};
        my $vm_class = "Ravada::VM::".$row->{vm};
        bless $vm_local, $vm_class;

        $vm = $vm_local->new();
        $domain = $vm->search_domain($row->{name}, $force) or return;
        $domain->_data(id_vm => $vm->id);
    }
    $domain->_insert_db_extra() if $domain && !$domain->is_known_extra();
    return $domain;
}

=head2 check_status

Checks if a virtual machine known status is in sync.

=over

=item * Checks it is already started

=item * Performs shutdown cleaning procedures if down

=back

=cut

sub check_status($self) {
    $self->_search_already_started()    if !$self->is_base;
    $self->_check_clean_shutdown()      if $self->domain && !$self->is_active;
}

=head2 is_known

Returns if the domain is known in Ravada.

=cut

sub is_known {
    my $self = shift;
    return 1    if $self->_select_domain_db(name => $self->name);
    return 0;
}

=head2 is_known_extra

Returns if the domain has extra fields information known in Ravada.

=cut

sub is_known_extra {
    my $self = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM domains_".lc($self->type)
        ." WHERE id_domain=?");
    $sth->execute($self->id);
    my ($id) = $sth->fetchrow;
    return 1 if $id;
    return 0;
}

=head2 start_time

Returns the last time (epoch format in seconds) the
domain was started.

=cut

sub start_time {
    my $self = shift;
    return $self->_data('start_time');
}

sub _select_domain_db {
    my $self = shift;
    my %args = @_;

    _init_connector();

    if (!keys %args) {
        my $id;
        eval { $id = $self->id  };
        if ($id) {
            %args =( id => $id );
        } else {
            %args = ( name => $self->name );
        }
    }
    my $table = ( delete $args{_table} or 'domains');

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM $table WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    my $data = "_data";
    $data = "_data_$table" if $table ne 'domains';
    $self->{$data} = $row;

    return $row if $row->{id};
}

sub _post_select_domain_db {
    my $self = shift;
    $self->description($self->{_data}->{description})
        if defined $self->{_data}->{description}
};

sub _prepare_base_db {
    my $self = shift;
    my @file_img = @_;

    if (!$self->_select_domain_db) {
        confess "CRITICAL: The data should be already inserted";
#        $self->_insert_db( name => $self->name, id_owner => $self->id_owner );
    }
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO file_base_images "
        ." (id_domain , file_base_img, target )"
        ." VALUES(?,?,?)"
    );
    for my $file_img (@file_img) {
        my $target;
        ($file_img, $target) = @$file_img if ref $file_img;
        $sth->execute($self->id, $file_img, $target );
    }
    $sth->finish;

    $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains SET is_base=1 "
        ." WHERE id=?");
    $sth->execute($self->id);
    $sth->finish;

    $self->_select_domain_db();
}

sub _set_spice_password {
    my $self = shift;
    my $password = shift;

    my $sth = $$CONNECTOR->dbh->prepare(
       "UPDATE domains set spice_password=?"
       ." WHERE id=?"
    );
    $sth->execute($password, $self->id);
    $sth->finish;

    $self->{_data}->{spice_password} = $password;
}

=head2 spice_password

Returns the password defined for the spice viewers

=cut

sub spice_password {
    my $self = shift;
    return $self->_data('spice_password');
}

=head2 display_file

Returns a file with the display information. Defaults to spice.

=cut

sub display_file($self,$user) {
    return $self->_display_file_spice($user);
}

sub _around_display_file_tls($orig, $self, $user) {
    my $display_file = $self->$orig($user);
    if (!$self->readonly) {
        $self->_data(display_file => $display_file);
    }
    return $display_file;
}

=head2 display_file_tls

Returns a file with the display information in TLS connections. Defaults to spice.

=cut


sub display_file_tls($self, $user) {
    return $self->_display_file_spice($user,1);
}

=head2 display

Returns the display information.

=cut


sub display($self, $user) {
    my $display_info = $self->display_info($user);
    return $display_info->{display};
}

# taken from isard-vdi thanks to @tuxinthejungle Alberto Larraz
sub _display_file_spice($self,$user, $tls = 0) {

    #    my ($ip,$port) = $self->display($user) =~ m{spice://(\d+\.\d+\.\d+\.\d+):(\d+)};

    my $display = $self->display_info($user);

    confess "I can't find ip port in ".Dumper($display)
        if !$display->{ip} || !$display->{port};

    my $ret =
        "[virt-viewer]\n"
        ."type=spice\n"
        ."host=".$display->{ip}."\n";
    if ($tls) {
        confess "Error: No TLS port found"
            if !exists $display->{tls_port} || !$display->{tls_port};
        $ret .= "tls-port=".$display->{tls_port}."\n";
    } else {
        $ret .= "port=".$display->{port}."\n";
    }
    $ret .="password=%s\n"  if $self->spice_password();

    $ret .=
        "fullscreen=1\n"
        ."title=".$self->name." - Press SHIFT+F12 to exit\n"
        ."enable-smartcard=0\n"
        ."enable-usbredir=1\n"
        ."enable-usb-autoshare=1\n"
        ."delete-this-file=1\n";

    if ( $tls ) {
        $ret .= "tls-ciphers=DEFAULT\n"
        ."host-subject=".$self->_vm->tls_host_subject."\n"
        .="ca=".$self->_vm->tls_ca."\n"
    }

    $ret .="release-cursor=shift+f11\n"
        ."toggle-fullscreen=shift+f12\n"
        ."secure-attention=ctrl+alt+end\n";
    $ret .=";" if !$tls;
    $ret .="secure-channels=main;inputs;cursor;playback;record;display;usbredir;smartcard\n";

    return $ret;
}

=head2 info

Return information about the domain.

=cut

sub info($self, $user) {
    my $is_active = $self->is_active;
    my $info = {
        id => $self->id
        ,name => $self->name
        ,is_base => $self->is_base
        ,id_base => $self->id_base
        ,is_active => $is_active
        ,is_hibernated => $self->is_hibernated
        ,spice_password => $self->spice_password
        ,description => $self->description
        ,msg_timeout => ( $self->_msg_timeout or undef)
        ,has_clones => ( $self->has_clones or undef)
        ,needs_restart => ( $self->needs_restart or 0)
        ,type => $self->type
        ,pools => $self->pools
        ,pool_start => $self->pool_start
        ,pool_clones => $self->pool_clones
        ,is_pool => $self->is_pool
        ,run_timeout => $self->run_timeout
        ,autostart => $self->autostart
        ,volatile_clones => $self->volatile_clones
    };
    for (qw(comment screenshot id_owner shutdown_disconnected)) {
        $info->{$_} = $self->_data($_);
    }
    if ($is_active) {
        eval {
            $info->{display_url} = $self->display($user);
            $self->display_file($user)  if !$self->_data('display_file');

            my $display = $self->display_info($user);
            $self->display_file_tls($user)
                if exists $display->{tls_port}
                    && $display->{tls_port}
                    && !$self->_data('display_file');
            $info->{display} = $display;
        };
        die $@ if $@ && $@ !~ /not allowed/i;
    }
    if (!$info->{description} && $self->id_base) {
        my $base = Ravada::Front::Domain->open($self->id_base);
        $info->{description} = $base->description;
    }
    $info->{hardware} = $self->get_controllers();

    confess Dumper($info->{hardware}->{disk}->[0])
        if ref($info->{hardware}->{disk}->[0]) =~ /^Ravada::Vol/;

    my $internal_info = $self->get_info();
    for (keys(%$internal_info)) {
        die "Field $_ already in info" if exists $info->{$_};
        $info->{$_} = $internal_info->{$_};
    }
    for (qw(disk network)) {
        $info->{drivers}->{$_} = $self->drivers($_,undef,1);
    }
    $info->{bases} = $self->_bases_vm();
    $info->{clones} = $self->_clones_vm();
    $info->{ports} = [$self->list_ports()];
    my @cdrom = ();
    for my $disk (@{$info->{hardware}->{disk}}) {
        push @cdrom,($disk->{file}) if $disk->{file} && $disk->{file} =~ /\.iso$/;
    }
    $info->{cdrom} = \@cdrom;
    $info->{requests} = $self->list_requests();

    return $info;
}

sub _msg_timeout($self) {
    return if !$self->run_timeout;
    my $msg_timeout = '';

    for my $request ( $self->list_all_requests ) {
        if ( $request->command =~ 'shutdown' ) {
            my $t1 = Time::Piece->localtime($request->at_time);
            my $t2 = localtime();

            $msg_timeout = " in ".($t1 - $t2)->pretty;
        }
    }
    return $msg_timeout;
}

sub _insert_db {
    my $self = shift;
    my %field = @_;

    _init_connector();

    for (qw(name id_owner)) {
        confess "Field $_ is mandatory ".Dumper(\%field)
            if !exists $field{$_};
    }

    my ($vm) = ref($self) =~ /.*\:\:(\w+)$/;
    confess "Unknown domain from ".ref($self)   if !$vm;
    $field{vm} = $vm;
    $self->{_data}->{name} = $field{name}   if $field{name};

    my $query = "INSERT INTO domains "
            ."(" . join(",",sort keys %field )." )"
            ." VALUES (". join(",", map { '?' } keys %field )." ) "
    ;
    my $sth = $$CONNECTOR->dbh->prepare($query);
    eval { $sth->execute( map { $field{$_} } sort keys %field ) };
    if ($@) {
        #warn "$query\n".Dumper(\%field);
        confess $@;
    }
    $sth->finish;

    $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set internal_id=? "
        ." WHERE id=?"
    );
    $sth->execute($self->internal_id, $self->id);
    $sth->finish;

    $self->_insert_db_extra();
}

sub _insert_db_extra($self) {
    return if $self->is_known_extra();

    my $sth = $$CONNECTOR->dbh->prepare("INSERT INTO domains_".lc($self->type)
        ." ( id_domain ) VALUES (?) ");
    $sth->execute($self->id);
    $sth->finish;

}

=head2 pre_remove

Code to run before removing the domain. It can be implemented in each domain.
It is not expected to run by itself, the remove function calls it before proceeding.

    $domain->pre_remove();  # This isn't likely to be necessary
    $domain->remove();      # Automatically calls the domain pre_remove method

=cut

sub pre_remove { }

sub _pre_remove_domain($self, $user, @) {

    eval { $self->id };
    warn $@ if $@;

    $self->_allow_remove($user);
    $self->_check_active_node();

    $self->is_volatile()        if $self->is_known || $self->domain;
    if (($self->is_known && $self->is_known_extra)
        || $self->domain ) {
        eval { $self->{_volumes} = [$self->list_disks()] };
        warn "Warning: $@" if $@;
    }
    $self->pre_remove();
    $self->_remove_iptables()   if $self->is_known();
    eval { $self->shutdown_now($user)  if $self->is_active };
    warn "Warning: $@" if $@;

    my $owner;
    $owner= Ravada::Auth::SQL->search_by_id($self->id_owner)    if $self->is_known();
    $owner->remove() if $owner && $owner->is_temporary();
}

=head2 restore

Returns the clone to an initial state.

Depending of the type of volumes added to the virtual machines
all the information stored there is removed. Only data volumes
are kept untouched.

=over

=item * system : cleaned to the initial state

=item * tmp/swap : cleaned to the initial state

=item * data : nothing gets removed

=cut

sub restore($self,$user){
    die "Error: ".$self->name." is not a clone. Only clones can be restored."
        if !$self->id_base;

    $self->_pre_remove_domain($user);

    my $base = Ravada::Domain->open($self->id_base);
    my @volumes = $self->list_volumes_info();
    my %file = map { $_->info->{target} => $_->file } @volumes;

    for my $file_data ( $base->list_files_base_target ) {
        my ($file_base,$target) = @$file_data;
        my $vol_base = Ravada::Volume->new(
            file => $file_base
            ,is_base => 1
            ,domain => $self
        );
        next if $vol_base->file =~ /\.DATA\.\w+$/;
        my $file_clone = $file{$target} or die Dumper(\%file);
        unlink $file_clone;
        my $clone = $vol_base->clone(file => $file_clone);
    }
}

# check the node is active
# search the domain in another node if it is not
sub _check_active_node($self) {
    return $self->_vm if $self->_vm->is_active(1);

    for my $node ($self->_vm->list_nodes) {
        next if !$node->is_local;

        $self->_vm($node);
        my $domain_active = $node->search_domain_by_id($self->id);
        next if !$domain_active;
        $self->domain($domain_active->domain);
        last;
    }
    return $self->_vm;

}

sub _after_remove_domain {
    my $self = shift;
    my ($user, $cascade) = @_;

    $self->_remove_iptables( );
    $self->remove_expose();
    $self->_remove_domain_cascade($user)   if !$cascade;

    if ($self->is_known && $self->is_base) {
        #        $self->_do_remove_base($user);
        $self->_remove_files_base();
    }
    $self->_remove_all_volumes();
    return if !$self->{_data};
    return if $cascade;
    $self->_finish_requests_db();
    $self->_remove_base_db();
    $self->_remove_access_attributes_db();
    $self->_remove_access_grants_db();
    $self->_remove_ports_db();
    $self->_remove_instance_db();
    $self->_remove_volumes_db();
    $self->_remove_bases_vm_db();
    $self->_remove_domain_db();

}

sub _remove_all_volumes($self) {
    for my $vol (@{$self->{_volumes}}) {
        next if $vol =~ /iso$/;
        $self->remove_volume($vol);
    }
}

sub _remove_domain_cascade($self,$user, $cascade = 1) {

    return if !$self->_vm;
    my $domain_name = $self->name or confess "Unknown my self name $self ".Dumper($self->{_data});

    my @instances = $self->list_instances();
    return if !scalar(@instances);

    my $sth_delete = $$CONNECTOR->dbh->prepare("DELETE FROM domain_instances "
        ." WHERE id=? ");
    for my $instance ( @instances ) {
        next if $instance->{id_vm} == $self->_vm->id;
        my $vm;
        eval { $vm = Ravada::VM->open($instance->{id_vm}) };
        die $@ if $@ && $@ !~ /I can't find VM/i;
        next if !$vm || !$vm->is_active;
        my $domain;
        $@ = '';
        eval { $domain = $vm->search_domain($domain_name) } if $vm;
        warn $@ if $@;
        $domain->remove($user, $cascade) if $domain;
        $sth_delete->execute($instance->{id});
    }
}

sub _remove_ports_db($self) {
    return if !$self->{_data}->{id};
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domain_ports"
        ." WHERE id_domain=?");
    $sth->execute($self->id);
    $sth->finish;
}

sub _remove_access_attributes_db($self) {

    return if !$self->{_data}->{id};
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM access_ldap_attribute"
        ." WHERE id_domain=?");
    $sth->execute($self->id);
    $sth->finish;
}

sub _remove_access_grants_db($self) {

    return if !$self->{_data}->{id};
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domain_access"
        ." WHERE id_domain=?");
    $sth->execute($self->id);
    $sth->finish;
}


sub _remove_volumes_db($self) {
    return if !$self->{_data}->{id};
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM volumes"
        ." WHERE id_domain=?");
    $sth->execute($self->id);
    $sth->finish;
}

sub _remove_bases_vm_db($self) {
    return if !$self->{_data}->{id};
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM bases_vm"
        ." WHERE id_domain=?");
    $sth->execute($self->id);
    $sth->finish;
}

sub _remove_instance_db($self) {
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domain_instances "
        ." WHERE id_domain=? AND id_vm=?"
    );
    $sth->execute($self->id, $self->_vm->id);
}

sub _remove_domain_db {
    my $self = shift;

    $self->_select_domain_db or return;

    my $id = $self->{_data}->{id} or return;
    my $type = $self->type;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains "
        ." WHERE id=?");
    $sth->execute($id);
    $sth->finish;

    $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains_".lc($type)
        ." WHERE id_domain=?");
    $sth->execute($id);
    $sth->finish;

}

sub _finish_requests_db {
    my $self = shift;

    return if !$self->{_data}->{id};
    $self->_select_domain_db or return;

    my $id = $self->id;
    my $type = $self->type;
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE requests "
        ." SET status='done' "
        ." WHERE id_domain=? AND status = 'requested' ");
    $sth->execute($id);
    $sth->finish;
}

sub _remove_files_base {
    my $self = shift;

    for my $file ( $self->list_files_base ) {
        next if $file =~ /\.iso$/;
        unlink $file or die "$! $file" if -e $file;
    }
}


sub _remove_id_base {

    my $self = shift;

    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set id_base=NULL "
        ." WHERE id=?"
    );
    $sth->execute($self->id);
    $sth->finish;
}

=head2 is_base
Returns true or  false if the domain is a prepared base
=cut

sub is_base {
    my $self = shift;
    my $value = shift;

    $self->_select_domain_db or return 0;

    if (defined $value ) {
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE domains SET is_base=? "
            ." WHERE id=?");
        $sth->execute($value, $self->id );
        $sth->finish;

        if (!$value) {
            $sth =$$CONNECTOR->dbh->prepare("UPDATE bases_vm SET enabled=? WHERE id_domain=?");
            $sth->execute(0, $self->id);
        }
        return $value;
    }
    my $ret = $self->_data('is_base');
    $ret = 0 if $self->_data('is_base') =~ /n/i;

    return $ret;
};

=head2 is_locked
Shows if the domain has running or pending requests. It could be considered
too as the domain is busy doing something like starting, shutdown or prepare base.
Returns true if locked.
=cut

sub is_locked {
    my $self = shift;

    $self->_init_connector() if !defined $$CONNECTOR;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,at_time FROM requests "
        ." WHERE id_domain=? AND status <> 'done'"
        ."   AND command <> 'open_iptables' "
        ."   AND command <> 'set_time'"
    );
    $sth->execute($self->id);
    my ($id, $at_time) = $sth->fetchrow;
    $sth->finish;

    return 0 if $at_time && $at_time - time > 1;
    return ($id or 0);
}

=head2 id_owner
Returns the id of the user that created this domain
=cut

sub id_owner {
    my $self = shift;
    return $self->_data('id_owner',@_);
}

=head2 id_base
Returns the id from the base this domain is based on, if any.
=cut

sub id_base {
    my $self = shift;
    return $self->_data('id_base',@_);
}

=head2 vm
Returns a string with the name of the VM ( Virtual Machine ) this domain was created on
=cut


sub vm {
    my $self = shift;
    return $self->_data('vm');
}

=head2 clones
Returns a list of clones from this virtual machine
    my @clones = $domain->clones
=cut

sub clones($self, %filter) {

    _init_connector();

    my $query =
        "SELECT id, id_vm, name, id_owner, status, client_status, is_pool"
            ." FROM domains "
            ." WHERE id_base = ? AND (is_base=NULL OR is_base=0)";
    my @values = ($self->id);
    if (keys %filter) {
        $query .= "AND ( ".join(" AND ",map { "$_ = ?" } sort keys %filter)." )";
        push @values,map {$filter{$_} } sort keys %filter;
    }
    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute(@values);
    my @clones;
    while (my $row = $sth->fetchrow_hashref) {
        # TODO: open the domain, now it returns only the id
        lock_hash(%$row);
        push @clones , $row;
    }
    return @clones;
}

=head2 has_clones
Returns the number of clones from this virtual machine
    my $has_clones = $domain->has_clones
=cut

sub has_clones {
    my $self = shift;

    _init_connector();

    return scalar $self->clones;
}


=head2 list_files_base
Returns a list of the filenames of this base-type domain
=cut

sub list_files_base {
    my $self = shift;
    my $with_target = shift;

    return if !$self->is_known();

    my $id;
    eval { $id = $self->id };
    return if $@ && $@ =~ /No DB info/i;
    die $@ if $@;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT file_base_img, target "
        ." FROM file_base_images "
        ." WHERE id_domain=?");
    $sth->execute($self->id);

    my @files;
    while ( my ($img, $target) = $sth->fetchrow) {
        push @files,($img)          if !$with_target;
        push @files,[$img,$target]  if $with_target;
    }
    $sth->finish;
    return @files;
}

=head2 list_files_base_target

Returns a list of the filenames and targets of this base-type domain

=cut

sub list_files_base_target {
    return $_[0]->list_files_base("target");
}

=head2 can_screenshot
Returns wether this domain can take an screenshot.
=cut

sub can_screenshot {
    return 0;
}

sub _convert_png {
    my $self = shift;
    my ($file_in ,$file_out) = @_;

    my $in = Image::Magick->new();
    my $err = $in->Read($file_in);
    confess $err if $err;

    $in->Scale(width => 250, height => 188);
    $in->Write("png24:$file_out");

    my @blobs = $in->ImageToBlob(magick => 'png');
    return $blobs[0];
    chmod 0755,$file_out or die "$! chmod 0755 $file_out";
}

=head2 remove_base
Makes the domain a regular, non-base virtual machine and removes the base files.
=cut

sub remove_base($self, $user) {
    return $self->_do_remove_base($user);
}

sub _cascade_remove_base_in_nodes($self) {
    my $req_nodes;
    for my $vm ( $self->list_vms ) {
        next if $vm->is_local;
        my @after;
        push @after,(after_request => $req_nodes->id) if $req_nodes;
        $req_nodes = Ravada::Request->remove_base_vm(
            id_vm => $vm->id
            ,id_domain => $self->id
            ,uid => Ravada::Utils::user_daemon->id
            ,@after
        );
    }
    if ( $req_nodes ) {
        my $vm_local = $self->_vm->new( host => 'localhost' );
        Ravada::Request->remove_base_vm(
            id_vm => $vm_local->id
            ,id_domain => $self->id
            ,uid => Ravada::Utils::user_daemon->id
            ,after_request => $req_nodes->id
        );
        $self->is_base(0);
    }
    return $req_nodes;
}

sub _do_remove_base($self, $user) {
    return
        if $self->is_base && $self->is_local
        && $self->_cascade_remove_base_in_nodes ();

    $self->is_base(0) if $self->is_local;
    my $vm_local = $self->_vm->new( host => 'localhost' );
    for my $vol ($self->list_volumes_info) {
        next if !$vol->file || $vol->file =~ /\.iso$/;
        my $backing_file = $vol->backing_file;
        next if !$backing_file;
        #        confess "Error: no backing file for ".$vol->file if !$backing_file;
        if (!$self->is_local) {
            my ($dir) = $backing_file =~ m{(.*/)};
            if ( $self->_vm->shared_storage($vm_local, $dir) ) {
                next;
            }
            $self->_vm->remove_file($vol->file);
            $self->_vm->remove_file($backing_file);
            $self->_vm->refresh_storage_pools();
            return ;
        }
        $vol->block_commit();
        unlink $vol->file or die "$! ".$vol->file;
        my @stat = stat($backing_file);
        move($backing_file, $vol->file) or die "$! $backing_file -> ".$vol->file;
        my $mask = oct(7777);
        my $mode = $stat[2] & $mask;
        my $w = oct(200);
        $mode = $mode ^ $w;
        chmod($mode,$vol->file);
        chown($stat[4],$stat[5], $vol->file);
    }

    for my $file ($self->list_files_base) {
        next if $file =~ /\.iso$/i;
        next if ! -e $file;
        unlink $file or die "$! unlinking $file";
    }

    $self->storage_refresh()    if $self->storage();
}

sub _pre_remove_base {
    my ($domain) = @_;
    _allow_manage(@_);
    _check_has_clones(@_);
    
    if (!$domain->is_local) {
        my $vm_local = $domain->_vm->new( host => 'localhost' );
        confess "Error: I can't find local virtual manager ".$domain->type
            if !$vm_local;

        $domain->_vm($vm_local);
    }
}

sub _post_remove_base {
    my $self = shift;
    return if !$self->_vm->is_local;
    $self->_remove_base_db(@_);
    $self->_post_remove_base_domain();

}

sub _post_spinoff($self) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE domains set id_base=NULL WHERE id=?");
    $sth->execute($self->id);
}

sub _pre_shutdown_domain {}

sub _post_remove_base_domain {}

sub _remove_base_db {
    my $self = shift;

    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM file_base_images "
        ." WHERE id_domain=?");

    $sth->execute($self->{_data}->{id});
    $sth->finish;

}

=head2 clone

Clones a domain

=head3 arguments

=over

=item user => $user : The user that owns the clone

=item name => $name : Name of the new clone

=back

=cut

sub clone {
    my $self = shift;
    my %args = @_;

    my $name = delete $args{name}
        or confess "ERROR: Missing domain cloned name";

    my $user = delete $args{user}
        or confess "ERROR: Missing request user";

    confess "ERROR: Clones can't be created in readonly mode"
        if $self->_vm->readonly();

    my $add_to_pool = delete $args{add_to_pool};
    my $from_pool = delete $args{from_pool};
    my $remote_ip = delete $args{remote_ip};
    my $request = delete $args{request};
    my $memory = delete $args{memory};
    my $start = delete $args{start};
    my $is_pool = delete $args{is_pool};
    my $no_pool = delete $args{no_pool};
    my $with_cd = delete $args{with_cd};

    confess "ERROR: Unknown args ".join(",",sort keys %args)
        if keys %args;

    confess "Error: This base has no pools"
        if $add_to_pool && !$self->pools;

    $from_pool = 1 if !defined $from_pool && !$add_to_pool && $self->pools;

    confess "Error: you can't add to pool if you pick from pool"
        if $from_pool && $add_to_pool;

    return $self->_clone_from_pool(@_) if $from_pool;

    my %args2 = @_;
    delete $args2{from_pool};
    return $self->_copy_clone(%args2)   if $self->id_base();

    my $uid = $user->id;

    if ( !$self->is_base() ) {
        $request->status("working","Preparing base")    if $request;
        $self->prepare_base(user => $user, with_cd => $with_cd)
    }

    my @args_copy = ();
    push @args_copy, ( start => $start )        if $start;
    push @args_copy, ( memory => $memory )      if $memory;
    push @args_copy, ( request => $request )    if $request;
    push @args_copy, ( remote_ip => $remote_ip) if $remote_ip;
    push @args_copy, ( from_pool => $from_pool) if defined $from_pool;
    push @args_copy, ( add_to_pool => $add_to_pool) if defined $add_to_pool;

    my $vm = $self->_vm;
    if ($self->volatile_clones ) {
        $vm = $vm->balance_vm($self);
    } elsif( !$vm->is_local ) {
        for my $node ($self->_vm->list_nodes) {
            $vm = $node if $node->is_local;
        }
    }
    my $clone = $vm->create_domain(
        name => $name
        ,id_base => $self->id
        ,id_owner => $uid
        ,@args_copy
    );
    $clone->is_pool(1) if $add_to_pool;
    return $clone;
}

sub _clone_from_pool($self, %args) {

    my $user = delete $args{user};
    my $remote_ip = delete $args{remote_ip};
    my $start = delete $args{start};

    my $clone = $self->_search_pool_clone($user);
    if ($start || $clone->is_active) {
        $clone->start(user => $user, remote_ip => $remote_ip);
        $clone->_data('client_status', 'connecting ...');
        $clone->_data('client_status_time_checked',time);
        Ravada::Request->manage_pools( uid => Ravada::Utils::user_daemon->id);
    }
    return $clone;
}

sub _copy_clone($self, %args) {
    my $name = delete $args{name} or confess "ERROR: Missing name";
    my $user = delete $args{user} or confess "ERROR: Missing user";
    my $memory = delete $args{memory};
    my $request = delete $args{request};
    my $add_to_pool = delete $args{add_to_pool};

    confess "ERROR: Unknown arguments ".join(",",sort keys %args)
        if keys %args;

    my $base = Ravada::Domain->open($self->id_base);

    my @copy_arg;
    push @copy_arg, ( memory => $memory ) if $memory;

    $request->status("working","Copying domain ".$self->name
        ." to $name")   if $request;

    my $copy = $self->_vm->create_domain(
        name => $name
        ,id_base => $base->id
        ,id_owner => $user->id
        ,from_pool => 0
        ,@copy_arg
    );
    my @volumes = $self->list_volumes_info(device => 'disk');
    my @copy_volumes = $copy->list_volumes_info(device => 'disk');

    my %volumes = map { $_->info->{target} => $_->file } @volumes;
    my %copy_volumes = map { $_->info->{target} => $_->file } @copy_volumes;
    for my $target (keys %volumes) {
        copy($volumes{$target}, $copy_volumes{$target})
            or die "$! $volumes{$target}, $copy_volumes{$target}"
    }
    $copy->is_pool(1) if $add_to_pool;
    return $copy;
}

sub _post_pause {
    my $self = shift;
    my $user = shift;

    $self->_data(status => 'paused');
    $self->_remove_iptables();
}

sub _post_hibernate($self, $user) {
    $self->_data(status => 'hibernated');
    $self->_remove_iptables();
    $self->_close_exposed_port();
}

sub _pre_shutdown {
    my $self = shift;

    confess "ERROR: Missing arguments"  if scalar(@_) % 2;

    my %arg = @_;

    my $user = delete $arg{user};
    delete $arg{timeout};
    delete $arg{request};

    confess "Unknown args ".join(",",sort keys %arg)
        if keys %arg;

    $self->_allow_shutdown(@_);

    $self->_pre_shutdown_domain();

    if ($self->is_paused) {
        $self->resume(user => Ravada::Utils::user_daemon, set_time => 0);
    }
    $self->list_disks;
    $self->_remove_start_requests();

}

sub _remove_start_requests($self) {
    for my $req ($self->list_requests(1)) {
        $req->_delete if $req->command =~ /^set_time$/;
    }
}

sub _post_shutdown {
    my $self = shift;

    my %arg = @_;
    my $timeout = delete $arg{timeout};

    if ( $self->_vm->is_active ) {
        $self->_remove_iptables();
        $self->_close_exposed_port();
    }

    my $is_active = $self->is_active;

    $self->_data(status => 'shutdown')
        if $self->is_known && !$self->is_volatile && !$is_active;

    if ($self->is_known && $self->id_base) {
        my @disks = $self->list_disks();
        if (grep /\.SWAP\./,@disks) {
            for ( 1 ..  5 ) {
                last if !$is_active;
                sleep 1;
                $is_active = $self->is_active;
            }
            $self->clean_swap_volumes(@_) if !$is_active;
        }
    }

    if (defined $timeout && !$self->is_removed && $is_active) {
        if ($timeout<2) {
            sleep $timeout;
            $is_active = $self->is_active;
            $self->_data(status => 'shutdown')    if !$is_active;
            return $self->_do_force_shutdown() if !$self->is_removed && $is_active;
        }

        Ravada::Request->refresh_machine(
                         at => time+int($timeout/2)
                      , uid => Ravada::Utils::user_daemon->id
                , id_domain => $self->id
        );
        my $req = Ravada::Request->force_shutdown_domain(
            id_domain => $self->id
               ,id_vm => $self->_vm->id
                , uid => $arg{user}->id
                 , at => time+$timeout 
        );
    }
    if ($self->is_volatile) {
        $self->_remove_temporary_machine();
        return;
    }
    my $info = $self->_data('info');
    $info = decode_json($info) if $info;
    $info = {} if !$info;
    delete $info->{ip};
    $self->_data(info => encode_json($info));
    $self->_data(display_file => '');
    # only if not volatile
    my $request;
    $request = $arg{request} if exists $arg{request};
    $self->_rsync_volumes_back( $request )
        if !$self->is_local && !$is_active && !$self->is_volatile;

    $self->needs_restart(0) if $self->is_known()
                                && $self->needs_restart()
                                && !$is_active;
}

sub _around_is_active($orig, $self) {

    if (!$self->_vm) {
        return 1 if $self->_data('status') eq 'active';
        return 0;
    }
    if ($self->_vm) {
        eval {
            return 0 if $self->_vm->is_active && $self->is_removed;
        };
        if ( $@ ) {
            return 0 if ref($@) && $@->code == 38; # broken pipe
            return 0 if $@ =~ /can't connect|error connecting/i;
            die $@;
        }
    }
    my $is_active = 0;
    $is_active = $self->$orig();

    return $is_active if $self->readonly
        || !$self->is_known
        || (defined $self->_data('id_vm') && (defined $self->_vm) && $self->_vm->id != $self->_data('id_vm'));

    my $status = $self->_data('status');
    $status = 'shutdown' if $status eq 'active';

    $status = 'active'  if $is_active;
    $status = 'hibernated'  if !$is_active
        && $self->_vm->is_active && !$self->is_removed && $self->is_hibernated;
    $self->_data(status => $status);

    $self->needs_restart(0) if $self->needs_restart() && !$is_active;
    return $is_active;
}

sub _around_is_hibernated($orig, $self) {
    return if $self->_vm && !$self->_vm->is_active;

    return $self->$orig();
}

sub _around_shutdown_now {
    my $orig = shift;
    my $self = shift;
    my $user = shift;

    $self->_vm->connect;
    $self->list_disks;
    $self->_pre_shutdown(user => $user);
    if ($self->is_active) {
        $self->$orig($user);
    }
    $self->_post_shutdown(user => $user)    if $self->is_known();
}

sub _around_name($orig,$self) {
    return $self->{_name} if $self->{_name};

    $self->{_name} = $self->{_data}->{name} if $self->{_data};
    $self->{_name} = $self->$orig()         if !$self->{_name};

    return $self->{_name};
}

=head2 can_hybernate

Returns wether a domain supports hybernation

=cut

sub can_hybernate { 0 };

=head2 can_hibernate

Returns wether a domain supports hibernation

=cut

sub can_hibernate {
    my $self = shift;
    return $self->can_hybernate();
};

=head2 add_volume_swap

Adds a swap volume to the virtual machine

Arguments:

    size => $kb
    name => $name (optional)

=cut

sub add_volume_swap {
    my $self = shift;
    my %arg = @_;

    $self->add_volume(%arg, swap => 1);
}

=head2 expose

Expose a TCP port from the domain

Arguments:
 - number of the port
 - optional name

Returns: public ip and port

=cut

sub expose($self, @args) {
    my ($id_port, $internal_port, $name, $restricted);
    if (scalar @args == 1 ) {
        $internal_port=shift @args;
    } else {
        my %args = @args;
        $id_port = delete $args{id_port};
        $internal_port = delete $args{port};
        $internal_port = delete $args{internal_port} if exists $args{internal_port};
        delete $args{internal_ip};
        # remove old fields
        for (qw(public_ip active description)) {
            delete $args{$_};
        }

        confess "Error: Missing port" if !defined $internal_port && !$id_port;
        confess "Error: internal port not a number '".($internal_port or '<UNDEF>')."'"
            if defined $internal_port && $internal_port !~ /^\d+$/;

        $name = delete $args{name};
        $restricted = ( delete $args{restricted} or 0);

        confess "Error: Unknown args ".Dumper(\%args) if keys %args;
    }
    if ($id_port) {
        $self->_update_expose(@args);
    } else {
        $self->_add_expose($internal_port, $name, $restricted);
    }
}

=head2 exposed_port

Returns all the data from an exposed port.

Argument: number or name description of the port permission.

    my $port_data = $domain->exposed_port(80);

    my $port_data = $domain->exposed_port('web');

=cut


sub exposed_port($self, $search) {
    confess "Error: you must supply a port number or name of exposed port"
        if !defined $search || !length($search);

    for my $port ($self->list_ports) {
        if ( $search =~ /^\d+$/ ) {
            return $port if $port->{internal_port} eq $search;
        } else {
            return $port if $port->{name} eq $search;
        }
    }
    return;
}

sub _update_expose($self, %args) {
    my $id = delete $args{id_port};
    $args{internal_port} = delete $args{port}
        if exists $args{port} && !exists $args{internal_port};

    if ($self->is_active) {
        my $sth=$$CONNECTOR->dbh->prepare("SELECT internal_port FROM domain_ports where id=?");
        $sth->execute($id);
        my ($internal_port) = $sth->fetchrow;
        $self->_close_exposed_port($internal_port) if $self->is_active;
    }

    my $sql = "UPDATE domain_ports SET ".join(",", map { "$_=?" } sort keys %args)
        ." WHERE id=?"
    ;

    my @values = map { $args{$_} } sort keys %args;

    my $sth = $$CONNECTOR->dbh->prepare($sql);
    $sth->execute(@values, $id);

    if ($self->is_active) {
        my $sth=$$CONNECTOR->dbh->prepare(
            "SELECT internal_port,name,restricted FROM domain_ports where id=?");
        $sth->execute($id);
        my ($internal_port, $name, $restricted) = $sth->fetchrow;
        $self->_open_exposed_port($internal_port, $name, $restricted);
    }
}

sub _add_expose($self, $internal_port, $name, $restricted) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO domain_ports (id_domain"
        ."  ,public_port, internal_port"
        ."  ,name, restricted"
        .")"
        ." VALUES (?,?,?,?,?)"
    );


    my $public_port;
    for (;;) {
        eval {
            $public_port = $self->_vm->_new_free_port();
            $sth->execute($self->id
                , $public_port, $internal_port
                , ($name or undef)
                , $restricted
            );
            $sth->finish;
        };
        last if !$@;
        confess $@ if $@ && $@ !~ /Duplicate entry .*for key /;
    }

    $self->_open_exposed_port($internal_port, $name, $restricted)
        if $self->is_active && $self->ip;
    return $public_port;
}

sub _set_public_port($self, $id_port, $internal_port, $name, $restricted) {
    my $public_port = $self->_vm->_new_free_port();
    for (;;) {
        if ($id_port) {
            my $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_ports set public_port=?"
                ." WHERE id_domain=? AND internal_port=?"
            );
            eval {
                $sth->execute($public_port, $self->id, $internal_port);
            };
            die $@ if $@ && $@ !~ /uplicate entry/;
            return $public_port if !$@;
        } else {
            my $sth = $$CONNECTOR->dbh->prepare("INSERT INTO domain_ports "
                ."(id_domain, public_port, internal_port, name, restricted)"
                ." VALUES(?,?,?,?,?) "
            );
            eval {
                $sth->execute( $self->id
                    ,$public_port, $internal_port
                    ,( $name or undef )
                    ,$restricted
                );
            };
            die $@ if $@ && $@ !~ /uplicate entry/;
            return $public_port if !$@;
        }
        $public_port += int(rand(10))+1;
    }
}

sub _open_exposed_port($self, $internal_port, $name, $restricted) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,public_port FROM domain_ports"
        ." WHERE id_domain=? AND internal_port=?"
    );
    $sth->execute($self->id, $internal_port);
    my ($id_port, $public_port) = $sth->fetchrow();

    $public_port = $self->_set_public_port($id_port, $internal_port, $name, $restricted)
    if !$public_port;

    my $local_ip = $self->_vm->ip;
    my $internal_ip = $self->ip;
    confess "Error: I can't get the internal IP of ".$self->name
        if !$internal_ip || $internal_ip !~ /^(\d+\.\d+)/;

    $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_ports set internal_ip=?"
            ." WHERE id_domain=? AND internal_port=?"
    );
    $sth->execute($internal_ip, $self->id, $internal_port);

    if ( !$> ) {
        $self->_vm->iptables_unique(
            t => 'nat'
            ,A => 'PREROUTING'
            ,p => 'tcp'
            ,d => $local_ip
            ,dport => $public_port
            ,j => 'DNAT'
            ,'to-destination' => "$internal_ip:$internal_port"
        ) if !$>;

        $self->_open_iptables_state();
        $self->_open_exposed_port_client($internal_port, $restricted);
    }
}

sub _open_iptables_state($self) {
    my $local_net = $self->ip;
    $local_net =~ s{(.*)\.\d+}{$1.0/24};

    $self->_vm->iptables_unique(
        I => 'FORWARD'
        ,m => 'state'
        ,d => $local_net
        ,state => 'NEW,RELATED,ESTABLISHED'
        ,j => 'ACCEPT'
    );
}

sub _open_exposed_port_client($self, $internal_port, $restricted) {

    my $internal_ip = $self->ip;

    my $remote_ip = '0.0.0.0/0';
    $remote_ip = $self->remote_ip if $restricted;
    return if !$remote_ip;
    if ( $restricted ) {
        $self->_vm->iptables_unique(
            I => 'FORWARD'
            ,d => $internal_ip
            ,m => 'tcp'
            ,p => 'tcp'
            ,dport => $internal_port
            ,j => 'DROP'
        );
    }

    $self->_vm->iptables_unique(
        I => 'FORWARD'
        ,s => $remote_ip
        ,d => $internal_ip
        ,m => 'tcp'
        ,p => 'tcp'
        ,dport => $internal_port
        ,j => 'ACCEPT'
    );

}

=head2 open_exposed_ports

Performs an iptables open of all the exposed ports of the domain

=cut

sub open_exposed_ports($self) {
    my @ports = $self->list_ports();
    return if !@ports;

    if ( ! $self->ip ) {
        die "Error: No ip in domain. Retry.\n";
    }

    for my $expose ( @ports ) {
        $self->_open_exposed_port($expose->{internal_port}, $expose->{name}
            ,$expose->{restricted});
    }
}

sub _close_exposed_port($self,$internal_port_req=undef) {
    my $query = "SELECT public_port,internal_port, internal_ip "
        ." FROM domain_ports"
        ." WHERE id_domain=? ";
    $query .= " AND internal_port=?" if $internal_port_req;

    my $sth = $$CONNECTOR->dbh->prepare($query);

    if ($internal_port_req) {
        $sth->execute($self->id, $internal_port_req);
    } else {
        $sth->execute($self->id);
    }

    my %port;
    while ( my $row = $sth->fetchrow_hashref() ) {
        lock_hash(%$row);
        $port{$row->{public_port}} = $row;
    }
    lock_hash(%port);

    my $iptables = $self->_vm->iptables_list();

    $self->_close_exposed_port_nat($iptables, %port);
    $self->_close_exposed_port_client($iptables, %port);

    $sth->finish;
}

sub _close_exposed_port_client($self, $iptables, %port) {

    my %ip = map {
        my $ip = '0.0.0.0/0';
        $ip = $port{$_}->{internal_ip}."/32" if $port{$_}->{internal_ip};
        $port{$_}->{internal_port} => $ip;
    } keys %port;

    for my $line (@{$iptables->{'filter'}}) {
         my %args = @$line;
         next if $args{A} ne 'FORWARD';
         if (exists $args{j}
             && exists $args{dport} && $ip{$args{dport}}
             && exists $args{d} && $args{d} eq $ip{$args{dport}}
         ) {

                my @delete = (
                    D => 'FORWARD'
                    , p => 'tcp', m => 'tcp'
                    , d => $ip{$args{dport}}
                    , dport => $args{dport}
                    , j => $args{j}
                );
                push @delete , (s => $args{s}) if exists $args{s};
                $self->_vm->iptables(@delete);
         }
     }
}

sub _close_exposed_port_nat($self, $iptables, %port) {
    my $ip = $self->_vm->ip."/32";
    for my $line (@{$iptables->{'nat'}}) {
         my %args = @$line;
         next if $args{A} ne 'PREROUTING';
         if (exists $args{j} && $args{j} eq 'DNAT'
             && exists $args{d} && $args{d} eq $ip
             && exists $args{dport}
             && exists $args{'to-destination'}
         ) {
            my $internal_port = $port{$args{dport}}->{internal_port} or next;
            if ( $args{'to-destination'}=~/\:$internal_port$/ ) {
                my %delete = %args;
                delete $delete{A};
                delete $delete{dport};
                delete $delete{m};
                delete $delete{p};
                my $to_destination = delete $delete{'to-destination'};

                my @delete = (
                    t => 'nat'
                    ,D => 'PREROUTING'
                    ,m => 'tcp', p => 'tcp'
                    ,dport => $args{dport}
                );
                push @delete, %delete;
                push @delete,(
                    'to-destination',$to_destination
                );
                $self->_vm->iptables(@delete);
            }
         }
     }
}

=head2 remove_expose

Remove exposed port

Argument: virtual machine exposed port [ optional ]

If no port is passed all the exposed ports are removed.

=cut

sub remove_expose($self, $internal_port=undef) {
    $self->_close_exposed_port($internal_port);
    my $query = "DELETE FROM domain_ports WHERE id_domain=?";
    $query .= " AND internal_port=?" if defined $internal_port;

    my $sth = $$CONNECTOR->dbh->prepare($query);
    my @args = $self->id;
    push @args,($internal_port) if defined $internal_port;
    $sth->execute(@args);
}

=head2 list_ports

List of exposed TCP ports

=cut

sub list_ports($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT *"
        ." FROM domain_ports WHERE id_domain=?");
    $sth->execute($self->id);
    my @list;
    my %clone_port;
    while (my $data = $sth->fetchrow_hashref) {
        lock_hash(%$data);
        push @list,($data);
        $clone_port{$data->{internal_port}}++;
    }

    if ($self->id_base) {
        my $base = Ravada::Front::Domain->open($self->id_base);
        my @ports_base = $base->list_ports();
        for my $data (@ports_base) {
            next if exists $clone_port{$data->{internal_port}};
            unlock_hash(%$data);
            $data->{public_port} = $self->_vm->_new_free_port() if $self->_vm;
            lock_hash(%$data);
            push @list,($data);
        }
    }

    return @list;
}

sub _remove_iptables {
    my $self = shift;

    my %args = @_;

    my $user = delete $args{user};
    my $port = delete $args{port};
    my $id_vm = delete $args{id_vm};

    if($port && !$id_vm) {
        $id_vm = $self->_data('id_vm');
    }

    delete $args{request};

    confess "ERROR: Unknown args ".Dumper(\%args)    if keys %args;

    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM iptables "
        ." WHERE id=?"
    );
    my @iptables;
    push @iptables, ( $self->_active_iptables(id_domain => $self->id))  if $self->is_known();
    push @iptables, ( $self->_active_iptables(port => $port, id_vm => $id_vm) ) if $port;

    my %rule;
    for my $row (@iptables) {
        my ($id, $id_vm, $iptables) = @$row;
        next if !$id_vm;
        push @{$rule{$id_vm}},[ $id, $iptables ];
    }
    for my $id_vm (keys %rule) {
        my $vm = Ravada::VM->open($id_vm);
        for my $entry (@ {$rule{$id_vm}}) {
            my ($id, $iptables) = @$entry;
            $self->_delete_ip_rule($iptables, $vm) if !$>;
            $sth->execute($id);
        }
    }
}

sub _test_iptables_jump {
    my @cmd = ('iptables','-L','INPUT');
    my ($in, $out, $err);

    run3(\@cmd, \$in, \$out, \$err);

    my $count = 0;
    for my $line ( split /\n/,$out ) {
        $count++ if $line =~ /^RAVADA /;
    }
    return if !$count || $count == 1;
    warn "Expecting 0 or 1 RAVADA iptables jump, got: "    .($count or 0);
}


sub _remove_temporary_machine($self) {

    return if !$self->is_volatile;

    my $owner;
    $owner= Ravada::Auth::SQL->search_by_id($self->id_owner)    if $self->is_known();

        if ($self->is_removed) {
            $self->remove_disks();
            $self->_after_remove_domain();
        }
    $self->remove(Ravada::Utils::user_daemon);

    $owner->remove() if $owner && $owner->is_temporary();
}

sub _post_resume {
    my $self = shift;
    return $self->_post_start(@_);
}

sub _timeout_shutdown($self, $value) {
    $TIMEOUT_SHUTDOWN = $value if defined $value;
    return $TIMEOUT_SHUTDOWN;
}

sub _post_start {
    my $self = shift;
    my %arg;

    if (scalar @_ % 2) {
        $arg{user} = $_[0];
    } else {
        %arg = @_;
    }
    my $remote_ip = $arg{remote_ip};
    my $set_time = delete $arg{set_time};
    $set_time = 1 if !defined $set_time;

    $self->_data('status','active') if $self->is_active();
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set start_time=? "
        ." WHERE id=?"
    );
    $sth->execute(time, $self->id);
    $sth->finish;

    $self->_data('internal_id',$self->internal_id);

    $self->_add_iptable(@_);
    $self->_update_id_vm();
    Ravada::Request->open_exposed_ports(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain => $self->id
            ,retry => 20
    ) if $remote_ip && $self->list_ports();

    if ($self->run_timeout) {
        my $req = Ravada::Request->shutdown_domain(
            id_domain => $self->id
                , uid => $arg{user}->id
                 , at => time+$self->run_timeout
                 , timeout => $TIMEOUT_SHUTDOWN
        );

    }
    $self->get_info();

    # get the display so it is stored for front access
    if ($self->is_active && $arg{remote_ip}) {
        $self->_data('client_status', $arg{remote_ip});
        $self->_data('client_status_time_checked', time );
        $self->display($arg{user});
        $self->display_file($arg{user});
        $self->info($arg{user});
    }
    Ravada::Request->set_time(uid => Ravada::Utils::user_daemon->id
        , id_domain => $self->id
        , retry => $RETRY_SET_TIME
    ) if $set_time;
    Ravada::Request->enforce_limits(at => time + 60);
    Ravada::Request->manage_pools(
            uid => Ravada::Utils::user_daemon->id
    )   if $self->is_pool;


    $self->post_resume_aux(set_time => $set_time);
}

sub _update_id_vm($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set id_vm=? where id = ?"
    );
    $sth->execute($self->_vm->id, $self->id);
    $sth->finish;

    $self->{_data}->{id_vm} = $self->_vm->id;
}

=head2 post_resume_aux

Method after resume

=cut

sub post_resume_aux {}

sub _add_iptable {
    my $self = shift;
    return if scalar @_ % 2;
    my %args = @_;

    my $remote_ip = $args{remote_ip} or return;

    my $user = $args{user} or confess "ERROR: Missing user";
    my $uid = $user->id;

    return if !$self->is_active;
    my $display_info = $self->display_info($user);
    $self->display_file($user) if !$self->_data('display_file');

    my $local_ip = (delete $args{local_ip} or $display_info->{listen_ip});
    my $local_port = $display_info->{port};

    $self->_remove_iptables( port => $local_port );

    $self->_open_port($user, $remote_ip, $local_ip, $local_port);
    if ($remote_ip eq '127.0.0.1' ) {
        $self->_open_port($user, $self->_vm->ip, $local_ip, $local_port);
    }
    $self->_close_port($user, '0.0.0.0/0', $local_ip, $local_port);

}

sub _delete_ip_rule ($self, $iptables, $vm = $self->_vm) {

    return if !$vm->is_active;

    my ($s, $d, $filter, $chain, $jump, $extra) = @$iptables;
    lock_hash %$extra;

    $s = undef if $s =~ m{^0\.0\.0\.0};
    $s .= "/32" if defined $s && $s !~ m{/};
    $d .= "/32" if defined $d && $d !~ m{/};

    my $iptables_list = $vm->iptables_list();

    my $removed = 0;
    my $count = 0;
    for my $line (@{$iptables_list->{$filter}}) {
        my %args = @$line;
        next if $args{A} ne $chain;
        $count++;
        if((!defined $jump || ( exists $args{j} && $args{j} eq $jump ))
           && ( !defined $s || (exists $args{s} && $args{s} eq $s))
           && ( !defined $d || ( exists $args{d} && $args{d} eq $d))
           && ( $args{dport} eq $extra->{d_port}))
        {

           $vm->run_command("iptables", "-t", $filter, "-D", $chain, $count)
                if $vm->is_active;
           $removed++;
           $count--;
        }

    }
    return $removed;
}
sub _open_port($self, $user, $remote_ip, $local_ip, $local_port, $jump = 'ACCEPT') {
    confess "local port undefined " if !$local_port;

    $self->_vm->create_iptables_chain($IPTABLES_CHAIN);

    my @iptables_arg = ($remote_ip
                        ,$local_ip, 'filter', $IPTABLES_CHAIN, $jump,
                        ,{'protocol' => 'tcp', 's_port' => 0, 'd_port' => $local_port});

    $self->_vm->iptables(
                A => $IPTABLES_CHAIN
                ,m => 'tcp'
                ,p => 'tcp'
                ,s => $remote_ip
                ,d => $local_ip
                ,dport => $local_port
                ,j => $jump
    ) if !$>;

    $self->_log_iptable(iptables => \@iptables_arg, user => $user, remote_ip => $remote_ip);

}

sub _close_port($self, $user, $remote_ip, $local_ip, $local_port) {
    $self->_open_port($user, $remote_ip, $local_ip, $local_port,'DROP');
}

=head2 open_iptables

Open iptables for a remote client

=over

=item user

=item  remote_ip

=back

=cut

sub open_iptables {
    my $self = shift;

    my %args = @_;
    my $uid = delete $args{uid};
    my $user = delete $args{user};

    confess "ERROR: Supply either uid or user"  if !$uid && !$user;

    $user = Ravada::Auth::SQL->search_by_id($uid)   if $uid;
    confess "ERROR: User ".$user->name." not uid $uid"
        if $uid && $user->id != $uid;
    $args{user} = $user;
    delete $args{uid};

    $self->_data('client_status','connecting...');
    $self->_data('client_status_time_checked', time );
    $self->_remove_iptables();

    if ( !$self->is_active ) {
        eval {
            $self->start(
                user => $user
            ,remote_ip => $args{remote_ip}
            );
        };
        die $@ if $@ && $@ !~ /already running/i;
    } else {
        Ravada::Request->enforce_limits( at => time + 60);
        Ravada::Request->manage_pools(
            uid => Ravada::Utils::user_daemon->id
        )if $self->is_pool;
    }

    $self->_add_iptable(%args);

    $self->info($user);
}

sub _log_iptable {
    my $self = shift;
    if (scalar(@_) %2 ) {
        carp "Odd number ".Dumper(\@_);
        return;
    }
    my %args = @_;

    my $remote_ip = delete $args{remote_ip} or confess "ERROR: remote_ip required";
    my $iptables  = delete $args{iptables}  or confess "ERROR: iptables required";
    my $user = delete $args{user};
    my $uid  = delete $args{uid};

    confess "ERROR: Unexpected arguments ".Dumper(\%args) if keys %args;
    confess "ERROR: Choose wether uid or user "
        if $user && $uid;
    confess "ERROR: Supply user or uid" if !defined $user && !defined $uid;

    lock_hash(%args);

    $uid = $user->id if !$uid;


    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO iptables "
        ."(id_domain, id_user, remote_ip, time_req, iptables, id_vm)"
        ."VALUES(?, ?, ?, ?, ?, ?)"
    );
    $sth->execute($self->id, $uid, $remote_ip, Ravada::Utils::now()
        ,encode_json($iptables), $self->_vm->id);
    $sth->finish;

}

sub _active_iptables {
    my $self = shift;

    my %args = @_;

    my      $port = delete $args{port};
    my      $user = delete $args{user};
    my     $id_vm = delete $args{id_vm};
    my   $id_user = delete $args{id_user};
    my $id_domain = delete $args{id_domain};

    confess "ERROR: User id (".$user->id." is not $id_user "
        if $user && $id_user && $user->id ne $id_user;

    confess "ERROR: Unknown args ".Dumper(\%args)   if keys %args;

    $id_user = $user->id if $user;

    my @sql_fields;

    my $sql
        = "SELECT id, id_vm, iptables FROM iptables "
        ." WHERE time_deleted IS NULL";

    if ( $id_user ) {
        $sql .= "    AND id_user=? ";
        push @sql_fields,($id_user);
    }

    if ( $id_domain ) {
        $sql .= "    AND id_domain=? ";
        push @sql_fields,($id_domain);
    }
    if ($port && !$id_vm) {
        $id_vm = $self->_vm->id;
    }
    if ( $id_vm) {
        $sql .= "    AND id_vm=? ";
        push @sql_fields,($id_vm);
    }
    $sql .= " ORDER BY time_req DESC ";
    my $sth = $$CONNECTOR->dbh->prepare($sql);
    $sth->execute(@sql_fields);

    my @iptables;
    while (my ($id, $id_vm, $iptables) = $sth->fetchrow) {
        my $iptables_data = decode_json($iptables);
        next if $port && $iptables_data->[5]->{d_port} ne $port;
        push @iptables, [ $id, $id_vm, $iptables_data ];
    }
    return @iptables;
}

sub _check_duplicate_domain_name {
    my $self = shift;
# TODO
#   check name not in current domain in db
#   check name not in other VM domain
    $self->id();
}

sub _rename_domain_db {
    my $self = shift;
    my %args = @_;

    my $new_name = $args{name} or confess "Missing new name";

    $self->_data(name => $new_name);
}

=head2 is_public

Sets or get the domain public

    $domain->is_public(1);

    if ($domain->is_public()) {
        ...
    }

=cut

sub is_public {
    my $self = shift;
    my $value = shift;

    _init_connector();
    if (defined $value) {
        my $sth = $$CONNECTOR->dbh->prepare("UPDATE domains set is_public=?"
                ." WHERE id=?");
        $sth->execute($value, $self->id);
        $sth->finish;
        $self->{_data}->{is_public} = $value;
    }
    return $self->_data('is_public');
}

=head2 is_volatile

Returns if the domain is volatile, so it will be removed on shutdown

=cut

sub is_volatile($self, $value=undef) {
    return $self->{_is_volatile} if exists $self->{_is_volatile}    && !defined $value;

    my $is_volatile = 0;
    if ($self->is_known) {
        $is_volatile = $self->_data('is_volatile', $value);
    } elsif ($self->domain) {
        $is_volatile = $self->is_persistent();
    }
    $self->{_is_volatile} = $is_volatile;
    return $is_volatile;
}

=head2 is_persistent

Returns true if the virtual machine is persistent. So it is not removed after
shut down.

=cut

sub is_persistent($self) {
    return !$self->{_is_volatile} if exists $self->{_is_volatile};
    return 0;
}

=head2 run_timeout

Sets or get the domain run timeout. When it expires it is shut down.

    $domain->run_timeout(60 * 60); # 60 minutes

=cut

sub run_timeout {
    my $self = shift;

    return $self->_data('run_timeout',@_);
}

#sub _set_data($self, $field, $value=undef) {
#    if (defined $value) {
#        warn "\t".$self->id." ".$self->name." $field = $value\n";
#        my $sth = $$CONNECTOR->dbh->prepare("UPDATE domains set $field=?"
#                ." WHERE id=?");
#        $sth->execute($value, $self->id);
#        $sth->finish;
#        $self->{_data}->{$field} = $value;
#
#        $self->_propagate_data($field,$value) if $PROPAGATE_FIELD{$field};
#    }
#    return $self->_data($field);
#}
sub _set_data($self, $field, $value) {
    return $self->_data($field, $value);
}

sub _propagate_data($self, $field, $value) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE domains set $field=?"
                ." WHERE id_base=?");
    $sth->execute($value, $self->id);
    $sth->finish;
}

=head2 clean_swap_volumes

Check if the domain has swap volumes defined, and clean them

    $domain->clean_swap_volumes();

=cut

sub clean_swap_volumes {
    my $self = shift;
    for my $vol ( $self->list_volumes_info) {
        confess if !$vol->domain;
        if ($vol->file && $vol->file =~ /\.SWAP\.\w+$/) {
            next if !$self->_vm->file_exists($vol->file);
            my $backing_file;
            eval { $backing_file = $vol->backing_file };
            confess $@ if $@ && $@ !~ /No backing file/i;
            next if !$backing_file;
            next if !$self->_vm->file_exists($backing_file);
            $vol->restore() if !$@;
        }
    }
}


sub _pre_rename {
    my $self = shift;

    confess "Error: odd number of arguments" if scalar(@_) % 2;

    my %args = @_;
    my $name = $args{name};
    my $user = $args{user};

    $self->_check_duplicate_domain_name(@_);

    $self->shutdown(user => $user)  if $self->is_active;
}

sub _post_rename {
    my $self = shift;
    my %args = @_;

    my $new_name = $args{new_name};

    $self->_rename_domain_db(@_);

    $self->{_name} = $new_name;
}

sub _post_dettach($self, @) {
     my $sth = $$CONNECTOR->dbh->prepare(
         "UPDATE domains set id_base=? "
         ." WHERE id=?"
     );
     $sth->execute(undef, $self->id);
     $sth->finish;
     delete $self->{_data};
}

 sub _post_screenshot {
     my $self = shift;
     my ($filename) = @_;

     return if !defined $filename;

     my $sth = $$CONNECTOR->dbh->prepare(
         "UPDATE domains set file_screenshot=? "
         ." WHERE id=?"
     );
     $sth->execute($filename, $self->id);
     $sth->finish;
 }

=head2 get_controller

Calls the method to get the specified controller info

Attributes:
    name -> name of the controller type

=cut

sub get_controller {
	my $self = shift;
	my $name = shift;

    my $sub = $self->get_controller_by_name($name);
#    my $sub = $GET_CONTROLLER_SUB{$name};
    
    die "I can't get controller $name for domain ".$self->name
        if !$sub;

    return $sub->($self);
}

=head2 get_controllers

Returns a hashref of the hardware controllers for this virtual machine

=cut


sub get_controllers($self) {
    my $info;
    my %controllers = $self->list_controllers();
    for my $name ( sort keys %controllers ) {
        $info->{$name} = [$self->get_controller($name)];
    }
    return $info;
}

=head2 drivers

List the drivers available for a domain. It may filter for a given type.

    my @drivers = $domain->drivers();
    my @video_drivers = $domain->drivers('video');

=cut

sub drivers($self, $name=undef, $type=undef, $list=0) {
    $type = $self->type         if $self && !$type;
    $type = $self->_vm->type    if $self && !$type;

    _init_connector();

    my $query = "SELECT id from domain_drivers_types ";

    my @sql_args = ();

    my @where;
    if ($name) {
        push @where,("name=?");
        push @sql_args,($name);
    }
    if ($type) {
        my $type2 = $type;
        if ($type =~ /qemu/) {
            $type2 = 'KVM';
        } elsif ($type =~ /KVM/) {
            $type2 = 'qemu';
        }
        push @where, ("( vm=? OR vm=?)");
        push @sql_args, ($type,$type2);
    }
    $query .= "WHERE ".join(" AND ",@where) if @where;
    my $sth = $$CONNECTOR->dbh->prepare($query);

    $sth->execute(@sql_args);

    my @drivers;
    while ( my ($id) = $sth->fetchrow) {
        my $cur_driver = Ravada::Domain::Driver->new(id => $id, domain => $self);
        if ($list) {
            my @options;
            for my $option ( $cur_driver->get_options ) {
                push @options,($option->{name});
            }
            push @drivers, \@options;
        } else {
            push @drivers,($cur_driver);
        }
    }
    return $drivers[0] if !wantarray && $name && scalar@drivers< 2;
    return @drivers;
}

=head2 set_driver_id

Sets the driver of a domain given it id. The id must be one from
the table domain_drivers_options

    $domain->set_driver_id($id_driver);

=cut

sub set_driver_id {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT d.name,o.value "
        ." FROM domain_drivers_types d, domain_drivers_options o"
        ." WHERE d.id=o.id_driver_type "
        ."    AND o.id=?"
    );
    $sth->execute($id);

    my ($type, $value) = $sth->fetchrow;
    confess "Unknown driver option $id" if !$type || !$value;

    $self->set_driver($type => $value);
    $sth->finish;
}

sub _listen_ip($self, $remote_ip=undef) {
    return $self->_vm->listen_ip($remote_ip);
}

sub remote_ip($self) {

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT remote_ip, iptables FROM iptables "
        ." WHERE "
        ."    id_domain=?"
        ."    AND time_deleted IS NULL"
        ." ORDER BY time_req DESC "
    );
    $sth->execute($self->id);
    my @ip;
    while ( my ($remote_ip, $iptables_json ) = $sth->fetchrow() ) {
        my $iptables = decode_json($iptables_json);
        next if $iptables->[4] ne 'ACCEPT';
        push @ip,($remote_ip);
    }
    $sth->finish;
    return @ip if wantarray;

    for my $ip (@ip) {
        return $ip if $ip eq '127.0.0.1';
    }
    return $ip[0];

}

=head2 last_vm

Returns the last virtual machine manager on which this domain was
launched.

    my $vm = $domain->last_vm();

=cut

sub last_vm {
    my $self = shift;

    my $id_vm = $self->_data('id_vm');

    return if !$id_vm;

    return Ravada::VM->open($id_vm);
}

=head2 list_requests

Returns a list of pending requests from the domain. It won't show those requests
scheduled for later.

=cut

sub list_requests {
    my $self = shift;
    my $all = shift;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM requests WHERE id_domain = ? AND status <> 'done'"
    );
    $sth->execute($self->id);
    my @list;
    while ( my $req_data =  $sth->fetchrow_hashref ) {
        next if !$all && $req_data->{at_time} && $req_data->{at_time} - time > 1;
        push @list,($req_data);
    }
    $sth->finish;
    return scalar @list if !wantarray;
    return map { Ravada::Request->open($_->{id}) } @list;
}

=head2 list_all_requests

Returns a list of pending requests from the domain including those scheduled for later

=cut

sub list_all_requests {
    return list_requests(@_,'all');
}

=head2 get_driver

Returns the driver from a domain

Argument: name of the device [ optional ]
Returns all the drivers if not passwed

    my $driver = $domain->get_driver('video');

=cut

=head2 get_driver_id

Gets the value of a driver

Argument: name

    my $driver = $domain->get_driver('video');

=cut

sub get_driver_id($self, $name) {
    my $value = $self->get_driver($name);
    return if !defined $value;

    my $driver_type = $self->drivers($name) or confess "ERROR: Unknown drivers"
        ." of type '$name'";

    for my $option ($driver_type->get_options) {
        return $option->{id} if $option->{value} eq $value;
    }
    return;
}

sub _dbh {
    my $self = shift;
    _init_connector() if !$CONNECTOR || !$$CONNECTOR;
    return $$CONNECTOR->dbh;
}

=head2 set_option

Sets a domain option:

=over

=item * description

=item * run_timeout

=back


    $domain->set_option(description => 'Virtual Machine for ...');

=cut

sub set_option($self, $option, $value) {
    my %valid_option = map { $_ => 1 } qw(autostart description run_timeout volatile_clones id_owner);
    die "ERROR: Invalid option '$option'"
        if !$valid_option{$option};

    return $self->_data($option, $value);
}

=head2 type

Returns the virtual machine type as a string.

=cut

sub type {
    my $self = shift;
    if (!exists $self->{_data} || !exists $self->{_data}->{vm}) {
        my ($type) = ref($self) =~ /.*::([a-zA-Z][a-zA-Z0-9]*)/;
        confess "Unknown type from ".ref($self) if !$type;
        return $type;
    }
    confess "Unknown vm ".Dumper($self->{_data})
        if !$self->_data('vm');
    return $self->_data('vm');
}

=head2 rsync

Synchronizes the volume data to a remote node.

Arguments: ( node => $node, request => $request, files => \@files )

=over

=item * node => Ravada::VM

=item * request => Ravada::Request ( optional )

=item * files => listref of files ( optional )

=back

When files is not specified it syncs the volumes and base volumes if any

=cut

sub rsync($self, @args) {

    my %args;
    if (scalar(@args) == 1 ) {
        $args{node} = $args[0];
    } else {
        %args = @args;
    }
    my    $node = ( delete $args{node} or $self->_vm );
    my   $files = delete $args{files};
    my $request = delete $args{request};

    confess "ERROR: Unkown args ".Dumper(\%args)    if keys %args;

    if (!$files ) {
        my @files_base;
        if ($self->is_base) {
            push @files_base,($self->list_files_base);
        }
        $files = [ $self->list_volumes( device => 'disk'), @files_base ];
    }

    $request->status("working") if $request;
    if ($node->is_local ) {
        confess "Node ".$node->name." and current vm ".$self->_vm->name
                ." are both local "
                    if $self->_vm->is_local;
        $self->_vm->_connect_ssh()
            or confess "No Connection to ".$self->_vm->host;
    } else {
        $node->_connect_ssh()
            or confess "No Connection to ".$self->_vm->host;
    }
    my $vm_local = $self->_vm->new( host => 'localhost' );
    my $rsync = File::Rsync->new(update => 1, sparse => 1);
    for my $file ( @$files ) {
        my ($path) = $file =~ m{(.*)/};
        my ($out, $err) = $node->run_command("/bin/mkdir","-p",$path);
        die $err if $err;
        my $src = $file;
        my $dst = 'root@'.$node->host.":".$file;
        if ($node->is_local) {
            next if $self->_vm->shared_storage($node, $path);
            $src = 'root@'.$self->_vm->host.":".$file;
            $dst = $file;
        } else {
            next if $vm_local->shared_storage($node, $path);
        }
        $request->status("syncing","Tranferring $file to ".$node->host)
            if $request;
        $rsync->exec(src => $src, dest => $dst);
    }
    if ($rsync->err) {
        $request->status("done",join(" ",@{$rsync->err}))   if $request;
        confess "error syncing to ".$node->host."\n"
            .Dumper($files)."\n"
            .join(' ',@{$rsync->err});
    }
    $node->refresh_storage_pools();
}

sub _rsync_volumes_back($self, $request=undef) {
    my $rsync = File::Rsync->new(update => 1);
    my $vm_local = $self->_vm->new( host => 'localhost' );
    for my $file ( $self->list_volumes() ) {
        my ($dir) = $file =~ m{(.*)/.*};
        next if $vm_local->shared_storage($self->_vm,$dir);
        $rsync->exec(src => 'root@'.$self->_vm->host.":".$file ,dest => $file );
        if ( $rsync->err ) {
            $request->status("done",join(" ",@{$rsync->err}))   if $request;
            last;
        }
    }
    $self->_vm->refresh_storage_pools();
}

sub _pre_migrate($self, $node, $request = undef) {

    confess "Error: node not active" if !$node->is_active(1);

    $self->_check_equal_storage_pools($node) if $self->_vm->is_active;

    $self->_internal_autostart(0);
    return if !$self->id_base;

    $self->check_status();
    confess "ERROR: Active domains can't be migrated"   if $self->is_active;

    my $base = Ravada::Domain->open($self->id_base);
    confess "ERROR: base ".$base->name." not prepared in node ".$node->name
        if !$base->base_in_vm($node->id);
    confess "ERROR: base id ".$self->id_base." not found."  if !$base;

    for my $file ( $base->list_files_base ) {
        next if $node->file_exists($file);
        warn "Warning: file not found $file in ".$node->name;
        Ravada::Request->set_base_vm(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain => $base->id
            ,id_vm => $node->id
        );
        return;
    }

    $self->_set_base_vm_db($node->id,0) unless $node->is_local;
    $node->_add_instance_db($self->id);
}

sub _post_migrate($self, $node, $request = undef) {
    $self->_set_base_vm_db($node->id,1) if $self->is_base;
    $self->_vm($node);
    $self->_update_id_vm();

    # TODO: update db instead set this value
    $self->{_migrated} = 1;

}

sub _id_base_in_vm($self, $id_vm) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM bases_vm "
        ." WHERE id_domain=? AND id_vm=?"
    );
    $sth->execute($self->id, $id_vm);
    return $sth->fetchrow;
}

sub _set_base_vm_db($self, $id_vm, $value) {
    my $is_base;
    $is_base = $self->base_in_vm($id_vm) if $self->is_base;

    return if defined $is_base && $value == $is_base;

    my $id_is_base = $self->_id_base_in_vm($id_vm);
    if (!defined $id_is_base) {
        my $sth = $$CONNECTOR->dbh->prepare(
            "INSERT INTO bases_vm (id_domain, id_vm, enabled) "
            ." VALUES(?, ?, ?)"
        );
        $sth->execute($self->id, $id_vm, $value);
        $sth->finish;
    } else {
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE bases_vm SET enabled=?"
            ." WHERE id_domain=? AND id_vm=?"
        );
        $sth->execute($value, $self->id, $id_vm);
        $sth->finish;
    }
}

=head2 set_base_vm

    Prepares or removes a base in a virtual manager.

    $domain->set_base_vm(
        id_vm => $id_vm         # you can pass the id_vm
          ,vm => $vm            #    or the vm
        ,user => $user
       ,value => $value  # if it is 0, it removes the base
     ,request => $req
    );

=cut

sub set_base_vm($self, %args) {

    my $id_vm = delete $args{id_vm};
    my $value = delete $args{value};
    my $user  = delete $args{user};
    my $vm    = delete $args{vm};
    my $node  = delete $args{node};
    my $request = delete $args{request};

    confess "ERROR: Unknown arguments, valid are id_vm, value, user, node and vm "
        .Dumper(\%args) if keys %args;

    confess "ERROR: Supply either id_vm or vm argument"
        if (!$id_vm && !$vm && !$node) || ($id_vm && $vm) || ($id_vm && $node)
            || ($vm && $node);

    confess "ERROR: user required"  if !$user;

    $request->status("working") if $request;
    $vm = $node if $node;
    $vm = Ravada::VM->open($id_vm)  if !$vm;

    $value = 1 if !defined $value;

    if ($vm->is_local) {
        $self->_set_vm($vm,1); # force set vm on domain
        if (!$value) {
            $request->status("working","Removing base")     if $request;
            $self->_set_base_vm_db($vm->id, $value);
            $self->remove_base($user);
        } else {
            $self->prepare_base($user) if !$self->is_base();
            $request->status("working","Preparing base")    if $request;
        }
    } elsif ($value) {
        $request->status("working", "Syncing base volumes to ".$vm->host)
            if $request;
        eval {
            $self->migrate($vm, $request);
        };
        my $err = $@;
        if ( $err ) {
            $self->_set_base_vm_db($vm->id, 0);
            die $err;
        }
        $self->_set_clones_autostart(0);
    } else {
        $self->_set_vm($vm,1); # force set vm on domain
        $self->_do_remove_base($user);
    }

    if (!$vm->is_local) {
        my $vm_local = $self->_vm->new( host => 'localhost' );
        $self->_set_vm($vm_local, 1);
    }
    $vm->_add_instance_db($self->id);
    return $self->_set_base_vm_db($vm->id, $value);
}

sub _set_clones_autostart($self, $value) {
    for my $clone_data ($self->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->_internal_autostart(0);
    }
}

=head2 migrate_base

Migrates a base to a virtual manager node.

Alias for set_base_vm.

=cut

sub migrate_base($self, %args) {
    return $self->set_base_vm(%args);
}

=head2 remove_base_vm

Removes a base in a Virtual Machine Manager node.

  $domain->remove_base_vm($vm, $user);

=cut

sub remove_base_vm($self, %args) {
    my $user = delete $args{user};
    my $vm = delete $args{vm};
    $vm = delete $args{node} if !$vm;
    confess "ERROR: Unknown arguments ".join(',',sort keys %args).", valid are user and vm."
        if keys %args;

    return $self->set_base_vm(vm => $vm, user => $user, value => 0);
}

=head2 file_screenshot

Returns the file name where the domain screenshot has been stored

=cut

sub file_screenshot($self) {
    return $self->_data('file_screenshot');
}

sub _pre_clone($self,%args) {
    my $name = delete $args{name};
    my $user = delete $args{user};
    my $memory = delete $args{memory};
    delete $args{request};
    delete $args{remote_ip};

    confess "ERROR: Missing clone name "    if !$name;
    confess "ERROR: Invalid name '$name'"   if $name !~ /^[a-z0-9_-]+$/i;

    confess "ERROR: Missing user owner of new domain"   if !$user;

    for (qw(is_pool start add_to_pool from_pool with_cd)) {
        delete $args{$_};
    }
    confess "ERROR: Unknown arguments ".join(",",sort keys %args)   if keys %args;
}

=head2 list_vms

Returns a list for virtual machine managers where this domain is base

=cut

sub list_vms($self) {
    confess "Domain is not base" if !$self->is_base;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id_vm FROM bases_vm WHERE id_domain=? AND enabled = 1");
    $sth->execute($self->id);
    my @vms;
    while (my $id_vm = $sth->fetchrow) {
        my $vm;
        eval { $vm = Ravada::VM->open($id_vm) };
        warn "id_domain: ".$self->id."\n".$@ if $@;
        push @vms,($vm) if $vm && !$vm->is_locked();
    }
    my $vm_local = $self->_vm->new( host => 'localhost' );
    if ( !grep { $_->name eq $vm_local->name } @vms) {
        push @vms,($vm_local);
        $self->set_base_vm(vm => $vm_local, user => Ravada::Utils::user_daemon);
    }
    return @vms;
}

=head2 base_in_vm

Returns if this domain has a base prepared in this virtual manager

    if ($domain->base_in_vm($id_vm)) { ...

=cut

sub base_in_vm($self,$id_vm) {

    my $id = $self;
    $id = $self->id if ref($self);

    confess "ERROR: id_vm must be a number, it is '$id_vm'"
        if $id_vm !~ /^\d+$/;

    confess "ERROR: Domain ".$self->name." is not a base"
        if ref($self) && !$self->is_base;

    confess "Undefined id_vm " if !defined $id_vm;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT enabled FROM bases_vm "
        ." WHERE id_domain = ? AND id_vm = ?"
    );
    $sth->execute($id, $id_vm);
    my ( $enabled ) = $sth->fetchrow;
    $sth->finish;
#    return 1 if !defined $enabled
#        && $id_vm == $self->_vm->id && $self->_vm->host eq 'localhost';
    return $enabled;
}

sub _bases_vm($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id, hostname FROM vms WHERE vm_type=?"
    );
    $sth->execute($self->type);
    my %base;
    while (my ($id_vm, $hostname) = $sth->fetchrow) {
        $base{$id_vm} = 0;
        $base{$id_vm} = 1 if $self->is_base && $hostname =~ /localhost|127/;
    }
    $sth->finish;

    for my $id_vm ( sort keys %base ) {
        $sth = $$CONNECTOR->dbh->prepare(
            "SELECT enabled FROM bases_vm WHERE id_domain=? AND id_vm=?"
        );
        $sth->execute($self->id, $id_vm);
        while (my ($enabled) = $sth->fetchrow) {
            $base{$id_vm} = $enabled;
        }
    }
    return \%base;
}

sub _clones_vm($self) {
    return {} if !$self->is_base;
    my @clones = $self->clones;

    my %clones;

    for my $clone (@clones) {
        push @{$clones{$clone->{id_vm}}}, (  $clone->{id} );
    }
    return \%clones;
}

=head2 is_local

Returns wether this domain is in the local host

=cut

sub is_local($self) {
    return $self->_vm->is_local();
}

=head2 pools

Enables or disables pools of clones for this virtual machine

=cut

sub pools($self,$value=undef) {
    return $self->_data('pools',$value);
}

=head2 pool_clones

Number of clones of this virtual machine that belong to the pool

=cut

sub pool_clones($self,$value=undef) {
    return $self->_data('pool_clones',$value);
}

=head2 pool_start

Number of clones of this virtual machine that are pre-started

=cut

sub pool_start($self,$value=undef) {
    return $self->_data('pool_start',$value);
}

=head2 is_pool

Return if the virtual machine belongs to a pool of clones

=cut

sub is_pool($self, $value=undef) {
    return $self->_data(is_pool => $value);
}


sub _search_pool_clone($self, $user) {
    confess "Error: ".$self->name." is not a base"
        if !$self->is_base;

    confess "Error: ".$self->name." is not pooled"
        if !$self->pools;

    my ($clone_down, $clone_free_up, $clone_free_down);
    my ($clones_in_pool, $clones_used) = (0,0);
    for my $current ( $self->clones) {
        if ( $current->{id_owner} == $user->id
                && $current->{status} =~ /^(active|hibernated)$/) {
            my $clone = Ravada::Domain->open($current->{id});
            $clone->_data( comment => $user->name );
            return $clone;
        }
        if ( $current->{id_owner} == $user->id ) {
            $clone_down = $current;
        } elsif ($current->{is_pool}) {
            $clones_in_pool++;
            my $clone = Ravada::Domain->open($current->{id});
            if(!$clone->client_status || $clone->client_status eq 'disconnected') {
                if ( $clone->status =~ /^(active|hibernated)$/ ) {
                    $clone_free_up = $current;
                } else {
                    $clone_free_down = $current;
                }
            } else {
                $clones_used++;
            }
        }
    }


    my $clone_data = ($clone_down or $clone_free_up or $clone_free_down);
    die "Error: no free clones in pool for ".$self->name
        .". Usage: $clones_used used from $clones_in_pool virtual machines created.\n"
        if !$clone_data;

    my $clone = Ravada::Domain->open($clone_data->{id});
    $clone->id_owner($user->id);
    $clone->_data( comment => $user->name );
    return $clone;
}

=head2 internal_id

Returns the internal id of this domain as found in its Virtual Manager connection

=cut

sub internal_id {
    my $self = shift;
    return $self->id;
}

=head2 volatile_clones

Enables or disables a domain volatile clones feature. Volatile clones are
removed when shut down

=cut

sub volatile_clones($self, $value=undef) {
    return $self->_data('volatile_clones', $value);
}

=head2 status

Sets or gets the status of a virtual machine

  $machine->status('active');

Valid values are:

=over

=item * active

=item * down

=item * hibernated

=back

=cut

sub status($self, $value=undef) {
    confess "ERROR: the status can't be updated on read only mode."
        if $self->readonly;
    my %valid_value = map { $_ => 1 } qw(active shutdown starting);
    confess "ERROR: invalid value '$value'" if $value && !$valid_value{$value};
    return $self->_data('status', $value);
}

=head2 client_status

Returns the status of the viewer connection. The virtual machine must be
active, and the remote ip must be known.

Possible results:

=over

=item * connecting : set at the start of the virtual machine

=item * IP : known remote ip from the current connection

=item * disconnected : the remote client has been closed

=back

This method is used from higher level commands, for example, you can shut down
or hibernate all the disconnected virtual machines like this:

  # rvd_back --hibernate --disconnected
  # rvd_back --shutdown --disconnected

You could also set this command on a cron entry to run nightly, hourly or whenever
you find suitable.

=cut


sub client_status($self, $force=0) {

    return $self->_data('client_status')    if $self->readonly;

    my $time_checked = time - $self->_data('client_status_time_checked');
    if ( $time_checked < $TIME_CACHE_NETSTAT && !$force ) {
        return $self->_data('client_status');
    }
    my $status = '';
    if ( !$self->is_active || !$self->remote_ip ) {
        $status = '';
    } else {
        $status = $self->_client_connection_status( $force );
    }
    $self->_data('client_status', $status);
    $self->_data('client_status_time_checked', time );

    return $status;
}

sub _run_netstat($self, $force=undef) {
    if (!$force && $self->_vm->{_netstat}
        && ( time - $self->_vm->{_netstat_time} < $TIME_CACHE_NETSTAT+1 ) ) {
        return $self->_vm->{_netstat};
    }
    my @cmd = ("/bin/ss", "-tn","-o","state","established");
    my ( $out, $err) = $self->_vm->run_command(@cmd);
    $self->_vm->{_netstat} = $out;
    $self->_vm->{_netstat_time} = time;

    return $out;
}

sub _client_connection_status($self, $force=undef) {
    my $display = $self->display(Ravada::Utils::user_daemon());
    my ($ip, $port) = $display =~ m{\w+://(.*):(\d+)};
    die "No ip in $display" if !$ip;

    my $netstat_out = $self->_run_netstat($force);
    my @out = split(/\n/,$netstat_out);
    for my $line (@out) {
        my @netstat_info = split(/\s+/,$line);
        if ( $netstat_info[2] eq $ip.":".$port ) {
            return 'connected';
        }
    }
    return 'disconnected';
}

=head2 needs_restart

Returns true or false if the virtual machine needs to be restarted so some
hardware change can be applied.

=cut

sub needs_restart($self, $value=undef) {
    return $self->_data('needs_restart',$value);
}

sub _pre_change_hardware($self, @) {
    if (!$self->_vm->is_local) {
        my $vm_local = $self->_vm->new( host => 'localhost' );
        $self->_set_vm($vm_local, 1);
    }
}

sub _post_change_hardware($self, $hardware, $index, $data=undef) {
    if ($hardware eq 'disk' && ( defined $index || $data ) && $self->is_known() ) {
        my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM volumes WHERE id_domain=?");
        $sth->execute($self->id);
        my @volumes = $self->list_volumes_info();
    }
    $self->info(Ravada::Utils::user_daemon) if $self->is_known();

    $self->_remove_domain_cascade(Ravada::Utils::user_daemon,1)
    if $self->is_known() && !$self->is_base;

    $self->needs_restart(1) if $self->is_known && $self->_data('status') eq 'active';
}

=head2 Access restrictions

These methods implement access restrictions to clone a domain

=cut

=head2 allow_ldap_access

If specified, only the LDAP users with that attribute value can clone these
virtual machines.

    $base->allow_ldap_attribute( attribute => 'value' );

Example:

    $base->allow_ldap_attribute( tipology => 'student' );

=cut

sub allow_ldap_access($self, $attribute, $value, $allowed=1, $last=0 ) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT max(n_order) FROM access_ldap_attribute "
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);
    my ($n_order) = ($sth->fetchrow or 0);
    $sth->finish;

    $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO access_ldap_attribute "
        ."(id_domain, attribute, value, allowed, n_order, last) "
        ."VALUES(?,?,?,?,?,?)");
    $sth->execute($self->id, $attribute, $value, $allowed, $n_order+1, $last);
}

=head2 default_access

Sets the default access value

=cut

sub default_access($self, $type, $allowed) {
    my @list = $self->list_access($type);
    my ($default) = grep { $_->{value} eq '*' } @list;
    if ($default) {
        my $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_access "
            ." SET allowed = ? "
            ." WHERE type=? AND id_domain=? AND value='*'"
        );
        $sth->execute($allowed, $type, $self->id);
    } else {
        $self->grant_access(attribute => '_DEFAULT_'
            ,value => '*'
            ,allowed => 0
            ,type => $type
        );
    }
}

=head2 grant_access

Grant access to a virtual machine

Arguments is a named list

=over

=item * attribute

=item * value

=item * type

=item * allowed ( true / false ) defaults to true

=item * last : if this grant matches it stops looking

=cut

sub grant_access($self, %args) {
    my $attribute = delete $args{attribute} or confess "Error: Missing attribute";
    my $value     = delete $args{value}     or confess "Error: Missing value";
    my $type      = delete $args{type}      or confess "Error: Missing type";
    my $allowed   = delete $args{allowed};
    $allowed = 1 if !defined $allowed;
    my $last      = ( delete $args{last} or 0 );

    confess "Error: unknown args ".Dumper(\%args) if keys %args;

    return $self->allow_ldap_access($attribute, $value, $allowed,$last)
        if $type eq 'ldap';

    my $sth ;
    if ($value eq '*') {
        $sth=$$CONNECTOR->dbh->prepare("DELETE FROM domain_access "
            ." WHERE id_domain=? AND type=? AND value='*' ");
        $sth->execute($self->id,$type);
    }

    $sth = $$CONNECTOR->dbh->prepare(
        "SELECT max(n_order) FROM domain_access"
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);
    my ($n_order) = ($sth->fetchrow or 0);
    $sth->finish;

    $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO domain_access"
        ."(id_domain, type, attribute, value, allowed, n_order, last) "
        ."VALUES(?,?,?,?,?,?,?)");
    $sth->execute($self->id, $type, $attribute, $value, $allowed, $n_order+1, $last);

    $self->_fix_default_access($type) unless $value eq '*';
}

sub _fix_default_access($self, $type) {
    my @list = $self->list_access($type);
    my $id_default;
    my $max=0;
    for ( @list ) {
        $max = $_->{n_order} if $_->{n_order} > $max;
        if ( $_->{value} eq '*' ) {
            $id_default = $_->{id};
        }
    }
    if ( $id_default ) {
        my $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_access "
            ."SET n_order = ? WHERE id=? "
        );
        $sth->execute($max+2, $id_default);
        return;
    }
    $self->default_access($type,0);
}

sub _mangle_client_attributes($attribute) {
    for my $name (keys %$attribute) {
        next if ref($attribute->{$name});
        if ($name =~ /Accept-\w+/) {

            my @values = map {my $item = $_ ; $item =~ s/^(.*?)[;].*/$1/; $item}
            split /,/,$attribute->{$name};

            $attribute->{$name} = \@values;
        } else {
            $attribute->{$name} = [$attribute->{$name}]
            if !ref($attribute->{$name});
        }
    }
}

sub _mangle_access_attributes($args) {
    for my $type (sort keys %$args) {
        _mangle_client_attributes($args->{$type}) if $type eq 'client';
    }
}

=head2 access_allowed

Returns if a client is granted access to a virtual machine

Arguments: expects a named vars list of client attributes retrieved from
the web connection.

=cut

sub access_allowed($self, %args) {
    _mangle_access_attributes(\%args);
    lock_hash(%args);
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT type, attribute, value, allowed, last FROM domain_access "
        ." WHERE id_domain=? "
        ." ORDER BY type,n_order"
    );
    $sth->execute($self->id);
    my $default_allowed = undef;
    while ( my ($type, $attribute, $value, $allowed, $last) = $sth->fetchrow) {
        if ($value eq '*') {
            $default_allowed = $allowed if !defined $default_allowed;
            next;
        }

        next unless exists $args{$type} && exists $args{$type}->{$attribute};
        my $req_value = $args{$type}->{$attribute};

        my $found;
        for (@$req_value) {
            $found =1 if $value eq $_;
        }
        if ($found) {
            return $allowed if $last || !$allowed;
            $default_allowed = $allowed;
        }

    }
    return $default_allowed;
}

=head2 list_access

Returns a list of access grants

Argument: optionally pass the type of grant.

=cut

sub list_access($self, $type=undef) {
    return $self->list_ldap_access()
    if defined $type && $type eq 'ldap';

    my $sql =
        "SELECT * from domain_access"
        ." WHERE id_domain = ? ";

    $sql .= " AND type= ".$$CONNECTOR->dbh->quote($type)
        if defined $type;

    my $sth = $$CONNECTOR->dbh->prepare(
        "$sql ORDER BY n_order"
    );
    $sth->execute($self->id);
    my @list;
    while (my $row = $sth->fetchrow_hashref) {
        push @list,($row) if keys %$row;
    }
    return @list;
}

=head2 delete_access

Deletes a list of access grants from the database

=cut

sub delete_access($self, @id_access) {
    for my $id_access (@id_access) {
        $id_access = $id_access->{id} if ref($id_access);

        my $sth = $$CONNECTOR->dbh->prepare(
            "SELECT * FROM domain_access"
            ." WHERE id=? ");
        $sth->execute($id_access);
        my $row = $sth->fetchrow_hashref();
        confess "Error: domain access id $id_access not found"
        if !keys %$row;

        confess "Error: domain access id $id_access not from domain "
        .$self->id
        ." it belongs to domain ".$row->{id_domain}
        if $row->{id_domain} != $self->id;

        $sth = $$CONNECTOR->dbh->prepare(
            "DELETE FROM domain_access"
            ." WHERE id_domain=? AND id=? ");
        $sth->execute($self->id, $id_access);
    }
}

=head2 delete_ldap_access

Deletes a granted ldap access setting

Argument: id of the access from the table access_ldap_attribute

=cut

#TODO: check something has been deleted
sub delete_ldap_access($self, $id_access) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM access_ldap_attribute "
        ."WHERE id_domain=? AND id=? ");
    $sth->execute($self->id, $id_access);
}

=head2 list_ldap_access

List granted ldap access settings

=cut

sub list_ldap_access($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * from access_ldap_attribute"
        ." WHERE id_domain = ? "
        ." ORDER BY n_order"
    );
    $sth->execute($self->id);
    my @list;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{last} = 1 if !$row->{allowed} && !$row->{last};
        push @list,($row) if keys %$row;
    }
    return @list;
}


=head2 deny_ldap_access

If specified, only the LDAP users with that attribute value can clone these
virtual machines.

    $base->deny_ldap_attribute( attribute => 'value' );

Example:

    $base->deny_ldap_attribute( tipology => 'student' );

=cut

sub deny_ldap_access($self, $attribute, $value) {
    $self->allow_ldap_access($attribute, $value, 0);
}

sub _set_access_order($self, $id_access, $n_order) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_access"
        ." SET n_order=? WHERE id=? AND id_domain=?");
    $sth->execute($n_order, $id_access, $self->id);
}

sub _set_ldap_access_order($self, $id_access, $n_order) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE access_ldap_attribute"
        ." SET n_order=? WHERE id=? AND id_domain=?");
    $sth->execute($n_order, $id_access, $self->id);
}

=head2 move_ldap_access

Moves an access access grant up or down

Arguments:

=over

=item * id_ldap_access

=item * position: +1/-1

=back

=cut

sub move_ldap_access($self, $id_access, $position) {
    confess "Error: You can only move position +1 or -1"
        if ($position != -1 && $position != 1);

    my @list = $self->list_ldap_access();

    my $index;
    for my $n (0 .. $#list) {
        if (defined $list[$n] && $list[$n]->{id} == $id_access ) {
            $index = $n;
            last;
        }
    }
    confess "Error: access id: $id_access not found for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $index;

    my ($n_order)   = $list[$index]->{n_order};
    die "Error: position $index has no n_order for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $n_order;

    my $index2 = $index + $position;
    die "Error: position $index2 has no id for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $list[$index2] || !defined$list[$index2]->{id};

    my ($id_access2, $n_order2) = ($list[$index2]->{id}, $list[$index2]->{n_order});

    die "Error: position ".$index2." not found for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $id_access2;

    die "Error: n_orders are the same for index $index and ".($index+$position)
            ."in \n".Dumper(\@list)
            if $n_order == $n_order2;

    $self->_set_ldap_access_order($id_access, $n_order2);
    $self->_set_ldap_access_order($id_access2, $n_order);
}

=head2 move_access

Moves an access access grant up or down

Arguments:

=over

=item * id_access

=item * position: +1/-1

=back

=cut

sub move_access($self, $id_access, $position) {
    confess "Error: You can only move position +1 or -1"
        if ($position != -1 && $position != 1);

    my $sth = $$CONNECTOR->dbh->prepare("SELECT type FROM domain_access "
        ." WHERE id=?");
    $sth->execute($id_access);
    my ($type) = $sth->fetchrow();
    confess "Error: I can't find accedd id=$id_access" if !defined $type;

    my @list = $self->list_access($type);

    my $index;
    for my $n (0 .. $#list) {
        if (defined $list[$n] && $list[$n]->{id} == $id_access ) {
            $index = $n;
            last;
        }
    }
    confess "Error: access id: $id_access not found for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $index;

    my ($n_order)   = $list[$index]->{n_order};
    die "Error: position $index has no n_order for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $n_order;

    my $index2 = $index + $position;
    die "Error: position $index2 has no id for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $list[$index2] || !defined$list[$index2]->{id};

    my ($id_access2, $n_order2) = ($list[$index2]->{id}, $list[$index2]->{n_order});

    die "Error: position ".$index2." not found for domain ".$self->id
            ."\n".Dumper(\@list)
        if !defined $id_access2;

    die "Error: n_orders are the same for index $index and ".($index+$position)
            ."in \n".Dumper(\@list)
            if $n_order == $n_order2;

    $self->_set_access_order($id_access, $n_order2);
    $self->_set_access_order($id_access2, $n_order);
}

=head2 set_ldap_access

Changes access grant allowed and last states

Arguments:

=over

=item * id_access

=item * allowed

=item * last

=back

=cut

sub set_ldap_access($self, $id_access, $allowed, $last) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE access_ldap_attribute "
        ." SET allowed=?, last=?"
        ." WHERE id=?");
    $sth->execute($allowed, $last, $id_access);
}

=head2 set_access

Changes access grant allowed and last states

=over

=item * id_access

=item * allowed

=item * last

=back

=cut

sub set_access($self, $id_access, $allowed, $last) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_access"
        ." SET allowed=?, last=?"
        ." WHERE id=?");
    $sth->execute($allowed, $last, $id_access);
}

=head2 rebase

Rebases the virtual machine to another one

If it is a base it rebases all the clones.

=cut

sub rebase($self, $user, $new_base) {

    my @reqs;

    _create_base_as_old($self, $user, $new_base) if !$new_base->is_base;

    if ( !$self->is_base ) {
        return $self->_rebase_volumes($new_base);
    }
    $self->pool_clones(0);
    $self->pool_start(0);
    # if I am a base, we rebase all the clones
    for my $clone_info ( $self->clones ) {
        next if $clone_info->{id} == $new_base->id;
        Ravada::Request->shutdown_domain(
            uid => $user->id
            , id_domain => $clone_info->{id}
        );

        my @args;
        push @args, ( after_request => $reqs[-1]->id ) if $reqs[-1];
        push @reqs,Ravada::Request->rebase (
                   uid => $user->id
              ,id_base => $new_base->id
            ,id_domain => $clone_info->{id}
                ,@args
                ,retry => 5
        );
    }
    return @reqs;
}

sub _create_base_as_old($self, $user, $new_base) {
    $new_base->dettach($user);
    $new_base->prepare_base($user);

    my $old_base = $self;
    $old_base = Ravada::Domain->open($self->id_base) if $self->id_base;

    my @reqs;
    for my $vm ($old_base->list_vms) {
        next if $vm->is_local;
        my @after;
        @after = (after_request => $reqs[0]->id ) if @reqs;
        push @reqs, Ravada::Request->set_base_vm(
            uid => $user->id
            ,id_vm => $vm->id
            ,id_domain => $new_base->id
            ,@after
        );
    }

    $new_base->is_public($old_base->is_public);
    return @reqs;
}

sub _rebase_volumes($self, $new_base) {
    my %old;
    for my $vol ( $self->list_volumes_info ) {
        $old{$vol->info->{target}} = $vol;
    }
    _check_rebase_vols($self, $new_base, \%old);

   # clone all volumes from new base but keep DATA volumes
    for my $file_data ( $new_base->list_files_base_target ) {
        my ($file_base,$target) = @$file_data;

        my $vol = $old{$target};

        #rebase DATA volumes
        if ( $vol && $vol->file && $vol->file =~ /\.(DATA)\.\w+$/ ) {
            $vol->rebase($file_base);
            next;
        }
        #keep CDs
        next if $vol
            && ( $vol->info->{device} eq 'cdrom'
                || ( $vol->file && $vol->file =~ /\.iso$/)
            );

        my $vol_base = Ravada::Volume->new(
            file => $file_base
            ,is_base => 1
            ,vm => $self->_vm
        );
        my $vol_clone;
        if ($vol) {
            if ($vol->info->{device} eq 'disk' && $vol->file) {
                $self->remove_volume($vol->file);
                $vol_clone = $vol_base->clone(file => $vol->file);
            } else {
                confess "I don't know how to rebase ".Dumper($vol->info);
            }
        } else {
            $vol_clone = $vol_base->clone(name => $self->name."-$target");
            $self->add_volume(
                file => $vol_clone->file
                ,target => $target
            );
        }
    }

    $self->id_base($new_base->id);
}

sub _check_rebase_vols($self, $new_base, $old) {

    my %new = map {
        my ($ext) = $_->[0] =~ /\.(\w+)$/;
        my ($type) = $_->[0] =~ /\.([A-Z]+)\.\w+$/;
        $type = 'SYS' if !defined $type;

        $_->[1] => "$type.$ext"
    } grep { $_->[0] }
    $new_base->list_files_base_target;

    my %old = map {
        my $file = ($old->{$_}->file or '');
        my ($ext) = $file =~ /\.(\w+)$/;
        my ($type) = $file =~ /\.([A-Z]+)\.\w+$/;

        $_ => ($type or 'SYS').".".($ext or "")
    } grep { $old->{$_}->file } keys %$old;

    for my $target (keys %new, keys %old) {
        next if exists $old{$target} && exists $new{$target}
            && $old{$target} eq $new{$target};
        die "Error: volume outline different in new base ".Dumper(\%new)
        .". Expecting ".Dumper(\%old);
    }
}

=head2 list_instances

Returns a list of instances of the virtual machine in all the physical nodes

=cut

sub list_instances($self) {
    return () if !$self->is_known();
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_instances "
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);

    my @instances;
    while (my $row = $sth->fetchrow_hashref) {
        lock_hash(%$row);
        push @instances, ( $row );
    }
    return @instances;
}

sub _base_in_nodes($self) {
    my $base = Ravada::Front::Domain->open($self->id_base);
    confess "Error: no id_base ".($self->id_base or '<NULL>')
        .Dumper($self) if !$base;
    return $base->list_instances > 1;
}

sub _domain_in_nodes($self) {
    return $self->_base_in_nodes() if $self->id_base;
    return $self->list_instances > 1;
}

1;
