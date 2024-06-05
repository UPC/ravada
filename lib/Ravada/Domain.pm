package Ravada::Domain;

use warnings;
use strict;

=head1 NAME

Ravada::Domain - Domains ( Virtual Machines ) library for Ravada

=cut

use utf8;

use Carp qw(carp confess croak cluck);
use Data::Dumper;
use DateTime;
use DateTime::Format::DateParse;
use File::Copy qw(copy move);
use File::Rsync;
use Fcntl ':mode';
use Hash::Util qw(lock_hash unlock_hash);
use Image::Magick;
use JSON::XS;
use Moose::Role;
use NetAddr::IP;
use IPC::Run3 qw(run3);
use Storable qw(dclone);
use Time::Piece;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Booking;
use Ravada::Domain::Driver;
use Ravada::Auth::SQL;
use Ravada::Utils;

our $TIMEOUT_SHUTDOWN = 120;
our $TIMEOUT_REBOOT = 120;
our $CONNECTOR;

our $MIN_FREE_MEMORY = 1024*1024;
our $IPTABLES_CHAIN = 'RAVADA';

our %PROPAGATE_FIELD = map { $_ => 1} qw( run_timeout shutdown_disconnected);

our $TIME_CACHE_NETSTAT = 60; # seconds to cache netstat data output
our $RETRY_SET_TIME=10;

our $DEBUG_RSYNC = 0;

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
requires 'reboot';
requires 'reboot_now';
requires 'force_reboot';
requires '_do_force_reboot';

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

has 'timeout_reboot' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => $TIMEOUT_REBOOT
);

has 'readonly' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => 0
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

before 'reboot' => \&_allow_shutdown;
after 'reboot' => \&_post_reboot;

around 'reboot_now' => \&_around_reboot_now;
around 'force_reboot' => \&_around_reboot_now;

before 'remove_base' => \&_pre_remove_base;
after 'remove_base' => \&_post_remove_base;
after 'spinoff' => \&_post_spinoff;

around 'rename' => \&_around_rename;

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

around 'set_controller' => \&_around_add_hardware;
around 'remove_controller' => \&_around_remove_hardware;
around 'change_hardware' => \&_around_change_hardware;

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
        || ($self->_data('status') eq 'shutdown' && !$self->_data('post_shutdown'))
        || $self->_active_iptables(id_domain => $self->id)) {
            $self->_post_shutdown();
    }

    if ($self->_data('status') eq 'hibernated' && !$self->_data('post_hibernated')) {
        $self->_post_hibernate();
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
    return $self->_vm->_check_equal_storage_pools($vm2);
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

    $self->_post_hibernate() if $self->is_hibernated && !$self->_data('post_hibernated');
    $self->_dettach_host_devices() if !$self->is_active;

    $self->_start_preconditions(@arg);

    $self->_pre_start_internal();

    $self->_data( 'post_shutdown' => 0);
    $self->_data( 'post_hibernated' => 0);

    my %arg;
    if (!(scalar(@arg) % 2) ) {
        %arg = @arg;
    } else {
        $arg{user} = $arg[0];
    }

    my $request = delete $arg{request};
    my $listen_ip = delete $arg{listen_ip};
    my $remote_ip = $arg{remote_ip};
    my $enable_host_devices;
    $enable_host_devices = $request->defined_arg('enable_host_devices') if $request;
    $enable_host_devices = 1 if !defined $enable_host_devices;

    for (1 .. 5) {
        eval { $self->_start_checks(@arg, enable_host_devices => $enable_host_devices) };
        my $error = $@;
        if ($error) {
            if ( $error =~/base file not found/ && !$self->_vm->is_local) {
                $self->_request_set_base();
                next;
            } elsif ($error =~ /No free memory/) {
                warn $error;
                die $error if $self->is_local || $self->is_volatile;
                my $vm_local = $self->_vm->new( host => 'localhost' );
                $self->migrate($vm_local, $request);
                next;
            }
        }
        warn $error if $error;
        die $error if $error;
        if (!defined $listen_ip) {
            my $display_ip;
            if ($remote_ip) {
                if ( Ravada::setting(undef,"/backend/display_password") ) {
                    # We'll see if we set it from the network, defaults to 0 meanwhile
                    my $set_password = 0;
                    my $network = Ravada::Route->new(address => $remote_ip);
                    $set_password = 1 if $network->requires_password();
                    $arg{set_password} = $set_password;
                }
                $display_ip = $self->_listen_ip($remote_ip);
            } else {
                $display_ip = $self->_listen_ip();
            }
            $arg{listen_ip} = $display_ip;
        }
        if ($enable_host_devices) {
            $self->_attach_host_devices(@arg);
        } else {
            $self->_dettach_host_devices();
        }
        $$CONNECTOR->disconnect;
        $self->status('starting') if $self->is_known();
        eval { $self->$orig(%arg) };
        $error = $@;
        last if !$error;

        die "Error: starting ".$self->name." on ".$self->_vm->name." $error"
        if $error =~ /there is no device|Did not find .*device/;

        die $error if $error =~ /No DRM render nodes/;

        warn "WARNING: $error ".$self->_vm->name." ".$self->_vm->enabled if $error;

        ;# pool has asynchronous jobs running.
        next if $error && ref($error) && $error->code == 1
        && $error !~ /internal error.*unexpected address/
        && $error !~ /process exited while connecting to monitor/
        && $error !~ /Could not run .*swtpm/i
        && $error !~ /virtiofs/
        && $error !~ /child process/i
        ;

        if ($error && $self->id_base && !$self->is_local && $self->_vm->enabled) {
            $self->_request_set_base();
            next;
        }
        die $error;
    }
    $self->_post_start(%arg);

}

sub _request_set_base($self, $id_vm=$self->_vm->id) {
    my $base = Ravada::Domain->open($self->id_base);
    $base->_set_base_vm_db($self->_vm->id,0);
    Ravada::Request->set_base_vm(
        uid => Ravada::Utils::user_daemon->id
        ,id_domain => $base->id
        ,id_vm => $id_vm
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
    my $user;
    if (scalar @_ %2 ) {
        my @args = @_;
        shift @args;
        my %args = @args;
        $user = delete $args{user};
        my $remote_ip = delete $args{remote_ip};
        $request = delete $args{request} if exists $args{request};
        $id_vm = delete $args{id_vm};

        confess "ERROR: Unknown argument ".join("," , sort keys %args)
            ."\n\tknown: remote_ip, user"   if keys %args;
    } else {
        ($user) = $_[1];
    }
    $self->_allowed_start($user);

    my $enable_host_devices;
    $enable_host_devices = $request->defined_arg('enable_host_devices') if $request;
    $enable_host_devices = 1 if !defined $enable_host_devices;

    if ( Ravada->setting('/backend/bookings')
            && !$self->allowed_booking( $user, $enable_host_devices ) ) {
        my $tz = Ravada::Booking::TZ();
        my @bookings = Ravada::Booking::bookings(
             date => DateTime->now(time_zone => $tz)->ymd
            ,time => DateTime->now(time_zone => $tz)->hms);

        confess "Error: resource booked for ".join(" , ",(map { $_->_data('title') } @bookings));
    }
    #_check_used_memory(@_);
    $self->status('starting');
}

=head2 allowed_booking

Returns true if an user is allowed in a booking for this virtual machine
or its base. Returns false otherwise.

   $machine->allowed_booking($user);

=cut


sub allowed_booking($self, $user, $enable_hd=1) {
    my $id_base = $self->id;
    if (!$self->is_base) {
        $id_base = $self->_data('id_base') or return 1;
    }
    return Ravada::Booking::user_allowed($user, $id_base, $enable_hd);
}

sub _start_checks($self, @args) {
    return if $self->_search_already_started('fast');
    my $vm_local = $self->_vm->new( host => 'localhost' );
    my $vm = $vm_local;

    my ($id_vm, $request, $enable_host_devices);
    if (!(scalar(@args) % 2)) {
        my %args = @args;

        # We may be asked to start the machine in a specific id_vmanager
        $id_vm = delete $args{id_vm};
        $request = delete $args{request} if exists $args{request};
        $enable_host_devices = delete $args{enable_host_devices};
    }
    # If not specific id_manager we go to the last id_vmanager unless it was localhost
    # If the last VManager was localhost it will try to balance here.
    $id_vm = $self->_data('id_vm')
    if !$id_vm && defined $self->_data('id_vm')
    && $self->_data('id_vm') != $vm_local->id;

    # check the requested id_vm is suitable
    if ($id_vm) {
        $vm = Ravada::VM->open($id_vm);
        if ( !$vm->enabled || !$vm->ping ) {
            $vm = $vm_local;
            $id_vm = undef;
        } elsif ($enable_host_devices && !$self->_available_hds($vm)) {
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
            $self->_balance_vm($request, $enable_host_devices)
            if !$self->is_volatile;
        }
        if ( !$self->is_volatile && !$self->_vm->is_local() ) {
            if (!base_in_vm($self->id_base, $self->_vm->id)) {
                my $args = {
                    uid => Ravada::Utils::user_daemon->id
                    ,id_domain => $self->id_base
                    ,id_vm => $self->_vm->id
                };

                my $req;
                $req = Ravada::Request->set_base_vm(%$args)
                unless Ravada::Request::_duplicated_request(undef
                    ,'set_base_vm', encode_json($args));
            }

            $self->rsync(request => $request);
        }
    }
    $self->_check_free_vm_memory();
    #TODO: remove them and make it more general now we have nodes
    #$self->_check_cpu_usage($request);
}

sub _search_already_started($self, $fast = 0) {
    my $sql = "SELECT id FROM vms where vm_type=? AND enabled=1";
    $sql .= " AND is_active=1" if $fast;
    my $sth = $$CONNECTOR->dbh->prepare($sql);
    $sth->execute($self->_vm->type);
    my %started;
    while (my ($id) = $sth->fetchrow) {
        my $vm;
        eval { $vm = Ravada::VM->open($id) };
        next if !$vm || !$vm->enabled;

        my $vm_active;
        eval {
            $vm_active = $vm->is_active;
        };
        my $error = $@;
        if ($error) {
            warn $error;
            $vm->enabled(0) if !$vm->is_local && !$vm->ping;
            next;
        }
        next if !$vm_active;

        my $domain;
        eval { $domain = $vm->search_domain($self->name) };
        if ( $@ ) {
            warn $@;
            next;
        }
        next if !$domain;
        $vm->_add_instance_db($domain->id);
        if ( $domain->is_active || $domain->is_hibernated ) {
            $self->_set_vm($vm,'force');
            $started{$vm->id}++;

            my $status = 'shutdown';
            $status = 'active'  if $domain->is_active;
            $status = 'hibernated' if $domain->is_hibernated;
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

sub _available_hds($self, $vm) {

    my @host_devices = $self->list_host_devices();
    return 1 if !@host_devices;

    my $available=1;
    for my $hd (@host_devices) {
        if  (! $hd->list_available_devices($vm->id) ) {
            $available=0;
            last;
        }
    }
    return $available;
}

sub _filter_vm_available_hd($self, @vms) {

    my @host_devices = $self->list_host_devices();

    return @vms if !@host_devices;

    my @vms_ret;

    for my $vm ( @vms ) {
        my $available = 1;
        for my $hd (@host_devices) {
            if  (! $hd->list_available_devices($vm->id) ) {
                $available=0;
                last;
            }
        }
        push @vms_ret,($vm) if $available;
    }

    die "No host devices available in any node.\n" if !@vms_ret;

    return @vms_ret;
}

sub _balance_vm($self, $request=undef, $host_devices=undef) {
    return if $self->{_migrated};

    my $base;
    $base = Ravada::Domain->open($self->id_base) if $self->id_base;

    my $vm_free;
    for (my $count=0;$count<10;$count++) {
        $vm_free = $self->_vm->balance_vm($self->_data('id_owner'),$base
                                            , $self->id, $host_devices);
        return if !$vm_free;
        next if !$vm_free->vm || !$vm_free->is_active;

        last if $vm_free->id == $self->_vm->id;
        eval { $self->migrate($vm_free, $request) };
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
    return if !$vm_free || !$vm_free->vm || !$vm_free->is_active;
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
        my $base = $self->open($self->id_base);

        die "ERROR: remove not allowed for user ".$user->name
        unless ($user->can_remove_clone_all() || ($base->id_owner == $user->id));
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

        $name .= "-".$args{target}."-".Ravada::Utils::random_name(4)
        if $name !~ /\.iso$/;

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

    my $storage = $args{storage};

    my $free = $self->_vm->free_disk($storage);
    my $free_out = int($free / 1024 / 1024 / 1024 ) * 1024 *1024 *1024;

    die "Error creating volume, out of space $size . Disk free: "
            .Ravada::Utils::number_to_size($free_out)
            ."\n"
        if exists $args{size} && $args{size} && $args{size} >= $free;

    if ($name) {
        confess "Error: volume $name already exists"
            if grep {$_->info->{name} eq $name} $self->list_volumes_info;
    }
    confess "Error: target $args{target} already exists in domain ".$self->name
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

=head2 pre_prepare_base

Run this before preparing the base. By default does nothing and may
be implemented in the object.

This is executed automatically so it shouldn't been called.

=cut

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
        next if !$volume->file;
        my $base_file = $volume->base_filename;
        next if !$base_file || $base_file =~ /\.iso$/;
        confess "Error: file '$base_file' already exists in ".$self->_vm->name
            if $self->_vm->file_exists($base_file);
    }

    for my $volume ($self->list_volumes_info()) {
        next if !$volume->info->{target} && $volume->info->{device} eq 'cdrom';
        next if $volume->info->{device} eq 'cdrom' && (!$with_cd || !$volume->file);
        confess "Undefined info->target ".Dumper($volume)
            if !$volume->info->{target};

        next if !defined $volume->file || !length($volume->file);
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
    die "Error: domain ".$self->name." is volatile and it can't be prepared as a base.\n"
    if $self->is_volatile();

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
    $self->_dettach_host_devices() if !$self->is_active;

    #    $self->_post_remove_base();
    if (!$self->is_local) {
        my $vm_local = Ravada::VM->open( type => $self->vm );
        $self->migrate($vm_local, $request);
    }
    $self->_check_free_space_prepare_base();
}

sub _check_free_space_prepare_base($self) {
    my $pool_base = $self->_vm->default_storage_pool_name;
    $pool_base = $self->_vm->base_storage_pool()   if $self->_vm->base_storage_pool();

    for my $volume ($self->list_volumes(device => 'disk')) {;
        next if !$volume;
        die "Error: volume $volume is missing.\n" if !$self->_vm->file_exists($volume);
    }
    for my $volume ($self->list_volumes_info(device => 'disk')) {;
        next if !$volume->file;
        die "Error: volume ".$volume->file." is missing.\n" if !$self->_vm->file_exists($volume->file);
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

    $self->_set_base_vm_db($self->_vm->id,1);
    $self->autostart(0,$user);

    $self->_vm->refresh_storage_pools();
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
    $self->_set_volumes_backing_store() if $self->type eq 'KVM';
}


sub _around_autostart($orig, $self, @arg) {
    my ($value, $user) = @arg;
    $self->_allowed($user) if defined $value;
    confess "ERROR: Autostart can't be activated on base ".$self->name
        if $value && $self->is_base;

    confess "Error: autostart can't be set on volatile domains" if $self->is_volatile && defined $value;

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

    return if !Ravada::Front::setting(undef,"/backend/limits/startup_ram");
    return if !$self->is_known();

    my $vm_free_mem = $self->_vm->free_memory;

    my $domain_memory = $self->info(Ravada::Utils::user_daemon)->{memory};
    my $min_free_memory = ($self->_vm->min_free_memory or $MIN_FREE_MEMORY)+$domain_memory;

    return if $vm_free_mem > $min_free_memory;

    $self->_data(status => 'shutdown');

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
    $self->_access_denied_error($user);
}

sub _access_denied_error($self,$user) {
    my ($id_owner,$owner_name);
    eval {
        $id_owner = $self->id_owner;

        my $owner= Ravada::Auth::SQL->search_by_id($id_owner);
        $owner_name = $owner->name if $owner;
    };
    my $err = $@;

    confess "User ".$user->name." [".$user->id."] not allowed to access ".$self->name
        ." owned by ".($owner_name or '<UNDEF>')." [".($id_owner or '<UNDEF>')."]"
            unless (defined $id_owner && $id_owner == $user->id )
                || $user->can_start_machine($self);

    confess $err if $err;

}

sub _allowed_start($self, $user) {
    return if $user->is_admin || $user->can_view_all;

    $self->_access_denied_error($user);
}

sub _around_display_info($orig,$self,$user ) {
    $self->_allowed_start($user);
    my @display_current_all = Ravada::Front::Domain::_get_controller_display($self);
    my @display_current = grep {$_->{is_builtin}} @display_current_all;
    my @display = $self->$orig($user);
    if (!$self->readonly && scalar (@display) != scalar(@display_current)) {
        my $sth = $$CONNECTOR->dbh->prepare(
            "DELETE FROM domain_displays WHERE id_domain=? AND is_builtin=1");
        $sth->execute($self->id);
    }

    for my $display (@display) {

        if (!$self->readonly && keys %$display) {
            $self->_set_display_ip($display);

            my $is_active = $self->is_active;
            if ($is_active) {

                unlock_hash(%$display);
                $display->{is_active} = 0;
                $display->{is_active} = 1 if $display->{is_builtin} && $is_active;
                if ($is_active && !$self->_is_display_builtin($display->{driver})) {
                    my $port = $self->exposed_port(id => $display->{id_domain_port});
                    $display->{is_active} = ( $port->{is_active} or 0);
                }
                $display->{id_vm} = $self->_vm->id if $display->{port};
                lock_hash(%$display);
            }
            $self->_store_display($display);
        }
    }
    my $n_order = 0;
    for (@display) {
        unlock_hash(%$_);
        $_->{n_order} = $n_order++ if !exists $_->{n_order};
        $n_order = $_->{n_order};
    }
    @display = sort { $a->{n_order} <=> $b->{n_order} } @display;
    return @display if wantarray;
    return $display[0];
}

sub _store_display($self, $display, $display_old=undef) {

    my %display_new = %$display;

    $self->_set_display_ip(\%display_new) if !exists $display->{ip} || !$display->{ip};
    if (!exists $display_new{ip} || !$display_new{ip}) {
        unlock_hash(%display_new);
        $display_new{ip} = $self->_vm->ip;
        $display_new{listen_ip} = $display_new{ip};
    }

    if ( !$display_old ) {
        confess "Error: missing display driver ".Dumper($display)
        if !exists $display->{driver};

        $display_old = $self->_get_display($display->{driver})
    }

    my $ip = ( $display_new{ip} or $display_old->{ip} );
    my $driver = ( $display_new{driver} or $display_old->{driver} );
    if (exists $display_new{port} && $display_new{port}
        && (!exists $display_new{id_vm} || !$display_new{id_vm}) ) {

        unlock_hash(%display_new);
        $display_new{id_vm} = $self->_vm->id;
        lock_hash(%display_new);
    }

    confess "Error: tls displays should be secondary"
    if $driver =~ /-tls/ && exists $display_new{is_secondary} && !$display_new{is_secondary};
   #warn "updating ".Dumper($display_old,\%display_new);
    if ($display_old) {
        $self->_update_display(\%display_new, $display_old);
    } else {
        $self->_insert_display(\%display_new);
    }
}

sub _get_display($self, $driver) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_displays "
        ." WHERE id_domain=? "
        ."   AND driver=?"
    );
    $sth->execute($self->id,$driver);
    my $row = $sth->fetchrow_hashref;
    return if !exists $row->{id};

    if ($row->{extra} && length($row->{extra})) {
        my $extra = decode_json($row->{extra});
        for my $key (keys %$extra) {
            $row->{$key} = $extra->{$key};
        };
    }
    delete $row->{extra};

    return $row;
}

sub _get_display_by_index($self, $index) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_displays "
        ." WHERE id_domain=? "
        ."   ORDER BY n_order,id"
    );
    $sth->execute($self->id);
    my $count = 0;
    while ( my $row = $sth->fetchrow_hashref ) {
        return $row if $count++ == $index;
    }
    confess "Error: display $index not found. Only ".($count-1)." found.";
}


sub _max_n_order_display($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT MAX(n_order) "
        ." FROM domain_displays "
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);
    my ($n_order) = $sth->fetchrow();
    return ($n_order or 0);
}

sub _normalize_display($self, $display, $json=1) {
    my %valid_field = map { $_ => 1 }
    qw(id id_domain port ip display listen_ip driver password is_builtin is_secondary
    is_active n_order extra id_domain_port id_vm );

    my $extra = {};
    unlock_hash(%$display);

    $display->{id_vm}=$self->_vm->id
    if exists $display->{port} && $display->{port} && !$display->{id_vm};

    $extra = decode_json($display->{extra}) if $display->{extra} && !ref($display->{extra});
    $display->{id_domain} = $self->id;

    for my $field ( keys %$display ) {
        next if $valid_field{$field};
        $extra->{$field} = delete $display->{$field};
    }

    $display->{extra} = $extra;
    $display->{extra} = encode_json($extra) if $json;

    $display->{password} = undef if !exists $display->{password};

    lock_hash(%$display);
}

sub _insert_display( $self, $display ) {
    $self->_normalize_display($display);

    unlock_hash(%$display);
    $display->{n_order} = $self->_max_n_order_display()+1
    if !exists $display->{n_order};

    $display->{is_builtin} = $self->_is_display_builtin($display->{driver})
    if !defined $display->{is_builtin};

    confess Dumper($display) if $display->{driver} =~ /-tls/ && !$display->{is_secondary};

    lock_hash(%$display);
    $self->_clean_display_order($display->{n_order}) if $display->{n_order};

    my $sql = ' INSERT INTO domain_displays '
    ."( ".join(",",sort keys %$display)." ) "
    ." VALUES ( ".join(",",map { '?' } keys %$display)." ) ";

    my $sth = $$CONNECTOR->dbh->prepare($sql);
    unlock_hash %$display;
    my $used_port = {};
    for ( 1 .. 10 ) {
        eval {
            $sth->execute(map { $display->{$_} } sort keys %$display);
        };
        last unless $@
            && ( $@ =~ /Duplicate entry .* for key.*'(.*)'/
                || $@ =~ /UNIQUE constraint failed:\s+(.*)/
            );
        ;
        my $field = $1;
        if ($field =~ /n_order/ && $display->{n_order}) {
            $self->_clean_display_order($display->{n_order});
        } elsif ($field =~ /port/) {
            if ($display->{is_builtin}) {
                $self->_fix_duplicate_display_port($display->{port});
            } else {
                $used_port->{$display->{port}}++;
                $display->{port} = $self->_vm->_new_free_port($used_port);
            }
        } elsif ($field =~ /id_domain_driver/) {
            warn "Warning: Already added ".Dumper($display);
            return;
        } else {
            confess "Error: I don't know how to deal with duplicated $field on ".$self->name
            .Dumper($display);
        }
    }
    confess $@ if $@;
}

sub _clean_display_order($self, $n_order) {
    my $sth_max = $$CONNECTOR->dbh->prepare(
        "SELECT max(n_order) FROM domain_displays WHERE id_domain=?"
    );
    $sth_max->execute($self->id);
    my ($max_n_order) = $sth_max->fetchrow();
    $max_n_order = 0 if !defined $max_n_order;
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_displays set n_order=? WHERE n_order=? AND id_domain=?"
    );
    for ( 1 .. 10 ) {
        $max_n_order++;
        eval { $sth->execute($max_n_order,$n_order, $self->id) };
        last if !$@;
    }
}

sub _update_display( $self, $new_display_orig, $old_display ) {
    my $id = $old_display->{id} or confess "Error: old display without id";

    my %new_display = %$new_display_orig;
    $self->_normalize_display(\%new_display);
    $self->_normalize_display($old_display);

    unlock_hash(%new_display);

    for my $key ( keys %$old_display ) {
        delete $new_display{$key}
        if exists $new_display{$key}
        && exists $old_display->{$key}
        && defined $new_display{$key}
        && defined $old_display->{$key}
        && $new_display{$key} eq $old_display->{$key};
    }
    delete $new_display{port} if exists $new_display{port} && defined $new_display{port}
    && $new_display{port} eq 'auto';

    return if !keys %new_display;

    confess if $old_display->{driver} =~ /-tls/
    && exists $new_display{is_secondary}
    && !$new_display{is_secondary};

    my $sql = "UPDATE domain_displays SET "
    .join(" , ", map { "$_ = ? " } sort keys %new_display)
    ." WHERE id = ? ";

    $self->_clean_display_order($new_display{n_order}) if $new_display{n_order};

    my $sth = $$CONNECTOR->dbh->prepare($sql);
    my $used_port = {};
    for ( 1 .. 10 ) {
        my @values = map { $new_display{$_} } sort keys %new_display ;
        eval { $sth->execute(@values, $id) };
        warn $@.Dumper(\%new_display) if $@;
        last if !$@;
        if ($old_display->{is_builtin} || $new_display{is_builtin} ) {
            $self->_fix_duplicate_display_port($new_display{port});
        } else {
            $used_port->{$new_display{port}}++;
            $new_display{port} = $self->_vm->_new_free_port($used_port);
        }
    }
    confess $@.Dumper($id,\%new_display) if $@;

}

sub _fix_duplicate_display_port($self, $port) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id, id_domain, is_active, is_builtin FROM domain_displays where port=? "
        ." AND id_vm = ?");
    $sth->execute($port, $self->_vm->id);
    my ($id_domain_display, $id_domain, $is_active, $is_builtin) = $sth->fetchrow;
    return if !$id_domain_display;

    if($is_builtin ) {
        my $domain_conflict = Ravada::Domain->open($id_domain);
        if ($domain_conflict && $domain_conflict->is_active) {
            Ravada::Request->refresh_machine(
                id_domain=> $domain_conflict->id
                ,uid => Ravada::Utils::user_daemon->id
                ,_force => 1
            );
            my $req = Ravada::Request->shutdown_domain(
                id_domain => $self->id
                ,uid => Ravada::Utils::user_daemon->id
            );
            my $req2 = Ravada::Request->refresh_machine(
                id_domain=> $self->id
                ,after_request => $req->id
                ,uid => Ravada::Utils::user_daemon->id
                ,_force => 1
            );
            my @after = ( after_request => $req->id );
            @after = ( after_request => $req2->id ) if $req2;
            Ravada::Request->start_domain(
                id_domain => $self->id,
                ,uid => Ravada::Utils::user_daemon->id
                ,@after
            );
            die "Error: ".$self->name." [ ".$self->id
            ." ]  port $port already used in domain $id_domain. Retry.\n";
        }
    }

    my $sth_update = $$CONNECTOR->dbh->prepare("UPDATE domain_displays set port=NULL "
        ." WHERE id=?"
    );
    $sth_update->execute($id_domain_display);

    $sth_update = $$CONNECTOR->dbh->prepare("UPDATE domain_ports set public_port=NULL "
        ." WHERE id_domain=? AND public_port=? AND id_vm=?"
    );
    $sth_update->execute($id_domain, $port, $self->_vm->id);

    Ravada::Request->open_exposed_ports(
        uid => Ravada::Utils::user_daemon->id
        ,id_domain => $id_domain
        ,retry => 20
        ,_force => 1
    ) if $is_active;
}

sub _set_display_ip($self, $display) {

    my $new_ip = ( $self->_vm->nat_ip
            or $self->_vm->display_ip
            or $self->_vm->public_ip
    );
    unlock_hash(%$display);
    $display->{listen_ip} = $display->{ip};

    if ( $new_ip ) {
        $display->{ip} = $new_ip;
    }

    lock_hash(%$display);
}

sub _around_get_info($orig, $self) {
    my $info = $self->$orig();
    if (ref($self) =~ /^Ravada::Domain/ && $self->is_known()) {
        if ( $self->is_active
        && (!exists $info->{ip} || !defined $info->{ip} || !$info->{ip})) {
            unlock_hash(%$info);
            $info->{ip} = $self->ip();
            lock_hash(%$info);
        }
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
    my $id = $self->_data('id');
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
        ,args => { id_domain => $self->id , uid => Ravada::Utils::user_daemon->id , _force => 1 }
    );
}

sub _log_active_domains($self) {
    my $sth = $self->_dbh->prepare(
        "SELECT count(*) FROM domains "
        ." WHERE status='active'"
    );
    $sth->execute();
    my ($active) = $sth->fetchrow;
    my $sth2 = $self->_dbh->prepare(
        "INSERT INTO log_active_domains "
        ." ( active) "
        ." values(?)"
    );
    $sth2->execute(scalar($active));

}

sub _data($self, $field, $value=undef, $table='domains') {

    _init_connector();

    my $data = "_data";
    my $field_id = 'id';
    if ($table ne 'domains' ) {
        $data = "_data_$table";
        $field_id = 'id_domain';
    }

    if ( $field eq 'info' && $table eq 'domains' && $value) {
        my $h = decode_json($value);
        confess $self->name." shouldn't have ->{harware} ".Dumper($h) if exists $h->{hardware};
    }

    if (defined $value &&
        ( !exists $self->{$data}->{$field}
            || !defined $self->{$data}->{$field}
            || $self->{$data}->{$field} ne $value )
        ) {
        confess "Domain ".$self->name." is not in the DB"
            if !$self->is_known();

        confess "ERROR: Invalid field '$field'"
            if $field !~ /^[a-z]+[a-z0-9_]*$/;

        return if $field eq 'status'
        && $self->{$data}->{$field} eq 'active'
        && $value eq 'starting';

        $self->_assert_update($table, $field => $value);
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE $table set $field=? WHERE $field_id=?"
        );
        $sth->execute($value, $self->id);
        $sth->finish;

        if ($data eq '_data' && $field eq 'status'
            && $value ne $self->{$data}->{$field}
        ) {
            $self->_data('date_status_change'=>Ravada::Utils::now());

            $self->_log_active_domains();
        }
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
    if (defined $value) {
        my $old = $self->_data_extra($field);
        return if defined $old && $old eq $value;
    }
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

    my $vm_changed;
    if (!$vm && ( $id_vm || defined $row->{id_vm} ) ) {
        $id_vm = $row->{id_vm} if !defined $id_vm;
        $self->_check_proper_id_vm($id, \$id_vm);
        eval {
            $vm = Ravada::VM->open(id => $id_vm, readonly => $readonly);
        };
        warn "Error connecting to $id_vm ".$@ if $@;
        if (!$vm) {
            Ravada::VM::_clean_cache();
        }
        eval {
            $vm = Ravada::VM->open(id => $id_vm, readonly => $readonly);
        };
        warn "Error connecting to $id_vm [retried]".$@ if $@;
        return if !$vm;
    }
    my $vm_local;
    if ( !$vm || !$vm->is_active ) {
        $vm_local = {};
        my $vm_class = "Ravada::VM::".$row->{vm};
        bless $vm_local, $vm_class;

        $vm = $vm_local->new( );
        $vm_changed = $vm;
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
        $vm_changed = $vm;
    }
    $domain->_insert_db_extra() if $domain && !$domain->is_known_extra();
    $domain->_data('id_vm' => $vm_changed->id) if $vm_changed;
    return $domain;
}

sub _check_proper_id_vm($self, $id, $id_vm) {
    my @instances = ({ id_vm => $$id_vm } , $self->list_instances($id) );
    for my $instance ( @instances ) {
        my $vm;
        eval {
            $vm = Ravada::VM->open($instance->{id_vm});
        };
        warn $@ if $@ && $@ !~ /I can't find VM/;
        next if !$vm;

        return if $$id_vm == $instance->{id_vm};

        $$id_vm = $instance->{id_vm};
        my $sth = $$CONNECTOR->dbh->prepare("UPDATE domains set id_vm=?"
            ." WHERE id=?"
        );
        $sth->execute($$id_vm, $id);
        return;
    }
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

    $row->{alias} = Encode::decode_utf8($row->{alias})
    if exists $row->{alias} && defined $row->{alias};

    return $row if $row->{id};
    return;
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

sub display_file($self, $display) {
    return $self->_display_file_spice($display);
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
    my @display_info = $self->display_info($user);

    my ($display_info) = grep { $_->{driver} !~ /-tls$/ } @display_info;

    return '' if !$display_info->{driver} || !$display_info->{ip}
    || !$display_info->{port};

    my $display = $display_info->{driver}."://$display_info->{ip}:$display_info->{port}";
    return $display;
}

# taken from isard-vdi thanks to @tuxinthejungle Alberto Larraz
sub _display_file_spice($self,$display, $tls = 0) {

    if (ref($display) =~ /^Ravada::Auth/) {
        my $driver = 'spice';
        $driver .= "-tls" if $tls;
        my @displays = $self->_get_controller_display();
        ($display) = grep { $_->{driver} eq $driver } @displays;
        confess "Error: no $driver found ".Dumper(\@displays) if !$display;
    }

    confess "I can't find ip port in ".Dumper($display)
        if !$display->{ip} || !$display->{port};

    my $ret =
        "[virt-viewer]\n"
        ."type=spice\n"
        ."host=".$display->{ip}."\n";
    if ($tls) {
        confess "Error: display $display->{driver} no TLS "
        unless $display->{driver} =~ /tls/;

        my $tls_port = $display->{port};

        confess "Error: No TLS port found ".Dumper($display)
            if !$tls_port;
        $ret .= "tls-port=$tls_port\n";
    } else {
        $ret .= "port=".$display->{port}."\n";
    }
    $ret .="password=%s\n"  if $self->spice_password();

    $ret .=
        "fullscreen=1\n"
        ."title=".$self->alias." - Press SHIFT+F12 to exit\n"
        ."enable-smartcard=0\n"
        ."enable-usbredir=1\n"
        ."enable-usb-autoshare=1\n"
        ."delete-this-file=1\n";

    if ( $tls ) {
        $ret .= "tls-ciphers=DEFAULT\n"
        ."host-subject=".$self->_tls('subject')."\n"
        .="ca=".$self->_tls('ca')."\n"
    }

    $ret .="release-cursor=shift+f11\n"
        ."toggle-fullscreen=shift+f12\n"
        ."secure-attention=ctrl+alt+end\n";
    $ret .=";" if !$tls;
    $ret .="secure-channels=main;inputs;cursor;playback;record;display;usbredir;smartcard\n";

    return $ret;
}

sub _tls($self, $field) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT tls FROM vms WHERE id=?");
    $sth->execute($self->_data('id_vm'));
    my ($tls_json) = $sth->fetchrow();
    my $tls = {};
    eval {
        $tls = decode_json($tls_json) if length($tls);
    };
    warn $@ if $@;
    return ( $tls->{$field} or '');
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
        ,is_public => $self->is_public
        ,show_clones => $self->show_clones
        ,id_base => $self->id_base
        ,is_public => $self->is_public
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
        ,id_vm => $self->_data('id_vm')
        ,auto_compact => $self->auto_compact
        ,date_changed => $self->_data('date_changed')
    };

    $info->{alias} = ( $self->_data('alias') or $info->{name} );
    for (qw(comment screenshot id_owner shutdown_disconnected is_compacted has_backups balance_policy)) {
        $info->{$_} = $self->_data($_);
    }
    if ($self->is_known() ) {
        eval {
            my @display = $self->display_info($user);
            $info->{display} = $display[0];
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
        die "Field $_ already in info ".Dumper($self->name,$internal_info)
        if exists $info->{$_};

        $info->{$_} = $internal_info->{$_};
    }
    #    for (qw(disk network display)) {
    #    $info->{drivers}->{$_} = $self->drivers($_,undef,1);
    #}
    $info->{drivers} = $self->_load_drivers();

    $info->{bases} = $self->_bases_vm();
    $info->{clones} = $self->_clones_vm();
    $info->{ports} = [$self->list_ports()];
    my @cdrom = ();
    for my $disk (@{$info->{hardware}->{disk}}) {
        push @cdrom,($disk->{file}) if $disk->{file} && $disk->{file} =~ /\.iso$/;
    }
    $info->{cdrom} = \@cdrom;
    $info->{requests} = $self->list_requests();
    $info->{host_devices} = [ $self->list_host_devices_attached() ];
    $info->{date_status_change} = $self->_date_status_change();

    Ravada::Front::_init_available_actions($user, $info);

    lock_hash(%$info);
    return $info;
}

sub _date_status_change($self) {
    my $date = $self->_data('date_status_change');
    if (!$date) {
        return {
            date => ''
            ,date_txt => ''
            ,duration => ''
        }
    }
    my $date_txt = $date;
    my $dt = DateTime::Format::DateParse->parse_datetime($date);
    if ($dt->day == DateTime->now()->day) {
        $date_txt =~ s/.*?(\d\d*:\d\d):\d\d$/$1/;
    }
    my $dur= DateTime->now() - $dt;
    my @units = ('years','months','weeks','days','hours','minutes');
    my @units_one = ('year','month','week','day','hour','minute');
    my @dur = $dur->in_units(@units);
    my $duration = ['now',''];
    for my $n (0 .. scalar(@units)-1) {
        my $value = $dur[$n];
        next if $value == 0;
        $duration = [$value,$units[$n]];
        $duration->[1]=$units_one[$n] if $value == 1;
        last;
    }
    return {
        date => $date
        ,date_txt => $date_txt
        ,duration => $duration
    };
}

sub _load_drivers($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domain_drivers_types "
        ." WHERE vm=?");
    $sth->execute($self->vm);
    my $drivers;
    while (my ( $hardware ) = $sth->fetchrow ) {
        $drivers->{$hardware} = $self->drivers($hardware,undef,1);
    }
    return $drivers;
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

    return if $self->{_is_removed} || !$self->is_known();

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
    if (!$self->{is_removed}
        &&( ($self->is_known && $self->is_known_extra)
        || $self->domain ) ) {
        eval { $self->{_volumes} = [$self->list_disks()] };
        warn "Warning: $@" if $@;
    }
    $self->pre_remove();
    if ($self->is_known) {
        $self->_remove_iptables();
        $self->_unlock_host_devices();
    }
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
    return 0 if !$self->_vm;
    return $self->_vm if $self->_vm && $self->_vm->is_active(1);

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

sub _after_remove_domain($self, $user, $cascade=undef) {

    $self->_remove_iptables( );
    $self->remove_expose();
    $self->_remove_domain_cascade($user)   if !$cascade;

    if ($self->is_known && $self->is_base) {
        #        $self->_do_remove_base($user);
        $self->_remove_files_base();
    }
    for my $backup ( $self->list_backups ) {
        $self->remove_backup($backup);
    }
    $self->_remove_all_volumes();
    return if !$self->{_data};
    return if $cascade;
    return if !$self->{_data}->{id};
    my $id = $self->{_data}->{id};

    my $type = $self->type;

    _remove_domain_data_db($id, $type);

    $self->{_is_removed}=time;
}

sub _remove_all_volumes($self) {
    my $vm_local = $self->_vm;
    $vm_local = $self->_vm->new( host => 'localhost' ) if !$self->is_local;
    for my $vol (@{$self->{_volumes}}) {
        next if $vol =~ /iso$/;
        if (!$self->is_local) {
            my ($dir) = $vol =~ m{(.*)/};
            next if $vm_local->shared_storage($self->_vm, $dir);
        }
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
        die $@ if $@ && $@ !~ /I can't find VM ||libvirt error code: 38,/i;
        my $domain;
        $@ = '';
        eval { $domain = $vm->search_domain($domain_name) } if $vm;
        warn $@ if $@;
        eval {
            $domain->remove($user, $cascade) if $domain;
        };
        warn $@ if $@;
        $sth_delete->execute($instance->{id});
    }
}

sub _remove_domain_data_db($id, $type=undef) {
    _finish_requests_db($id);
    for my $table (
        'access_ldap_attribute','domain_access'
        ,'host_devices_domain'
        ,'domain_displays' , 'domain_ports', 'volumes', 'domains_void', 'domains_kvm', 'domain_instances', 'bases_vm', 'domain_access', 'base_xml', 'file_base_images', 'iptables', 'domains_network') {
        my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM $table WHERE id_domain=?");
        $sth->execute($id);
    }
    _remove_domain_custom_db($id, $type);
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth->execute($id);
}

sub _redefine_instances($self) {
    my $domain_name = $self->name or confess "Unknown my self name $self ".Dumper($self->{_data});
    my @instances = $self->list_instances();
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
        $domain->copy_config($self) if $domain;
    }
}

sub _remove_domain_custom_db($id, $type=undef) {
    if (!defined $type) {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT vm FROM domains WHERE id=?");
        $sth->execute($id);
        my ($type) = $sth->fetchrow;
    }
    return if !defined $type;

    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains_".lc($type)
        ." WHERE id_domain=?"
    );
    $sth->execute($id);
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

sub _finish_requests_db($id) {
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
        ."   AND command <> 'open_exposed_ports'"
        ."   AND command <> 'open_iptables' "
        ."   AND command <> 'set_time'"
        ."   AND command <> 'rsync_back'"
        ."   AND command <> 'refresh_machine'"
        ."   AND command <> 'refresh_machine_ports'"
        ."   AND command <> 'screenshot'"
        ."   AND command <> 'add_hardware'"
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
        "SELECT id, id_vm, name,alias, id_owner, status, client_status, is_pool, is_base"
            ." ,is_volatile "
            ." FROM domains "
            ." WHERE id_base = ? ";
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
        $row->{alias} = Encode::decode_utf8($row->{alias});
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
            ,_force => 1
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
            ,_force => 1
        );
        $self->is_base(0);
    }
    return $req_nodes;
}

sub _do_remove_base($self, $user) {
    return
        if $self->is_base && $self->is_local
        && $self->_cascade_remove_base_in_nodes();

    $self->is_base(0) if $self->is_local;
    my $vm_local = $self->_vm->new( host => 'localhost' );
    for my $vol ($self->list_volumes_info) {
        next if !$vol->file || $vol->file =~ /\.iso$/;
        next if !$self->_vm->file_exists($vol->file);

        my ($dir) = $vol->file =~ m{(.*)/};

        next if !$self->is_local && $self->_vm->shared_storage($vm_local, $dir);
        my $backing_file = $vol->backing_file;
        next if !$backing_file;
        #        confess "Error: no backing file for ".$vol->file if !$backing_file;
        if (!$self->is_local) {
            my ($dir) = $backing_file =~ m{(.*/)};
            next if $self->_vm->shared_storage($vm_local, $dir);
            $self->_vm->remove_file($vol->file);
            $self->_vm->remove_file($backing_file);
            $self->_vm->refresh_storage_pools();
            next;
        }
        $vol->block_commit();
        unlink $vol->file or die "$! ".$vol->file;
        my @stat = stat($backing_file) or confess "Error: missing $backing_file";
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
        next if ! $self->_vm->file_exists($file);
        my ($dir) = $file =~ m{(.*/)};
        next if !$self->_vm->is_local && $self->_vm->shared_storage($vm_local, $dir);

        $self->_vm->remove_file($file);
    }

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
    $self->list_volumes_info();
}

sub _pre_shutdown_domain {}

sub _pre_reboot_domain {}

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
    my $no_pool = delete $args{no_pool};
    my $with_cd = delete $args{with_cd};
    my $volatile = delete $args{volatile};
    my $id_owner = delete $args{id_owner};
    my $alias = delete $args{alias};
    my $options = delete $args{options};
    my $storage = delete $args{storage};

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
    return $self->_copy_clone(%args2)   if !$self->is_base && $self->id_base();

    my $uid = $id_owner || $user->id;

    if ( !$self->is_base() ) {
        $request->status("working","Preparing base")    if $request;
        $self->prepare_base(user => $user, with_cd => $with_cd)
    }

    my @args_copy = ();
    push @args_copy, ( alias => $alias )        if $alias;
    push @args_copy, ( start => $start )        if $start;
    push @args_copy, ( memory => $memory )      if $memory;
    push @args_copy, ( request => $request )    if $request;
    push @args_copy, ( remote_ip => $remote_ip) if $remote_ip;
    push @args_copy, ( from_pool => $from_pool) if defined $from_pool;
    push @args_copy, ( add_to_pool => $add_to_pool) if defined $add_to_pool;
    push @args_copy, ( storage => $storage)     if $storage;
    push @args_copy, ( options => $options)     if $options;

    if ( $self->volatile_clones && !defined $volatile ) {
        $volatile = 1;
    }

    push @args_copy, ( volatile => $volatile )  if defined $volatile;

    my $vm = $self->_vm;
    if ($volatile) {
        $vm = $vm->balance_vm($uid, $self);
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
    my $volatile = delete $args{volatile};
    my $id_owner = delete $args{id_owner};
    $id_owner = $user->id if (! $id_owner);
    my $alias = delete $args{alias};
    my $options = delete $args{options};
    my $start = delete $args{start};

    confess "ERROR: Unknown arguments ".join(",",sort keys %args)
        if keys %args;

    my $base = Ravada::Domain->open($self->id_base);

    my @copy_arg;
    push @copy_arg, ( alias => $alias )   if $alias;
    push @copy_arg, ( memory => $memory ) if $memory;
    push @copy_arg, ( volatile => $volatile ) if $volatile;
    push @copy_arg, ( options => $options ) if $options;
    push @copy_arg, ( start => $start ) if $start;

    $request->status("working","Copying domain ".$self->name
        ." to $name")   if $request;

    my $copy = $self->_vm->create_domain(
        name => $name
        ,id_base => $base->id
        ,id_owner => $id_owner
        ,from_pool => 0
        ,@copy_arg
    );

    _copy_volumes($self, $copy);
    _copy_ports($self, $copy);
    _copy_host_devices($self, $copy);
    $copy->is_pool(1) if $add_to_pool;
    return $copy;
}

sub _copy_volumes($self, $copy) {
    my @volumes = $self->list_volumes_info(device => 'disk');
    my @copy_volumes = $copy->list_volumes_info(device => 'disk');

    my %volumes = map { $_->info->{target} => $_->file } @volumes;
    my %copy_volumes = map { $_->info->{target} => $_->file } @copy_volumes;
    for my $target (keys %volumes) {
        copy($volumes{$target}, $copy_volumes{$target})
            or die "$! $volumes{$target}, $copy_volumes{$target}"
    }
}

sub _copy_ports($base, $copy) {
    my %port_already;
    for my $port ( $copy->list_ports ) {
        $port_already{$port->{internal_port}}++;
    }

    for my $port ( $base->list_ports ) {
        my %port = %$port;
        next if $port_already{$port->{internal_port}};
        delete @port{'id','id_domain','public_port','is_secondary','is_active'};
        $copy->expose(%port);
    }

}

sub _copy_host_devices($base, $copy) {
    for my $host_device ( $base->list_host_devices() ) {
        $copy->add_host_device($host_device);
    }
}


sub _post_pause {
    my $self = shift;
    my $user = shift;

    $self->_data(status => 'paused');
    $self->_remove_iptables();
}

sub _post_hibernate($self, $user=undef) {
    $self->_data(status => 'hibernated');
    $self->_data(post_hibernated => 1);
    $self->_remove_iptables();
    $self->_close_exposed_port();
    $self->_set_ports_down();
    $self->_set_displays_down();
}

sub _pre_shutdown {
    my $self = shift;

    confess "ERROR: Missing arguments"  if scalar(@_) % 2;

    my %arg = @_;

    my $user = delete $arg{user};
    delete $arg{timeout};
    my $request = delete $arg{request};

    if ($request && $request->defined_arg('check')) {
        my $check = $request->defined_arg('check');
        if ($check eq 'disconnected') {
            die "Virtual machine reconnected"
            if $self->client_status ne 'disconnected';
        } elsif ($check) {
            confess "Error: unknown shutdown check '$check'";
        }
    }

    confess "Unknown args ".join(",",sort keys %arg)
        if keys %arg;

    $self->_allow_shutdown(@_);

    $self->_pre_shutdown_domain();

    if ($self->is_paused || $self->is_hibernated) {
        $self->resume(user => Ravada::Utils::user_daemon, set_time => 0);
        $self->_data('status' => 'active');
    }
    $self->list_disks;
    $self->_remove_start_requests();

    my $ip = $self->ip;
    $self->_delete_ip_rule ([undef,$ip,'nat' ]) if $ip;

}

sub _remove_start_requests($self) {
    for my $req ($self->list_requests(1)) {
        $req->_delete if $req->command =~ /^set_time|refresh_machine_ports|open_exposed_ports$/;
    }
}

# it may be superceeded in child class
sub _post_shutdown_internal {}

# it may be superceeded in child class
sub _pre_start_internal {}

sub _post_shutdown {
    my $self = shift;

    $self->_post_shutdown_internal();

    my %arg = @_;
    my $timeout = delete $arg{timeout};
    if (!defined $timeout) {
        $timeout = ( $self->_data('shutdown_timeout') or $TIMEOUT_SHUTDOWN);
    }

    if ( $self->_vm->is_active ) {
        $self->_remove_iptables();
        $self->_close_exposed_port();
    }
    $self->_set_ports_down();
    $self->_set_displays_down();

    my $is_active = $self->is_active;

    if ( $self->is_known && !$self->is_volatile && !$is_active ) {
        $self->_dettach_host_devices();
        if ($self->is_hibernated) {
            $self->_data(status => 'hibernated');
        } else {
            $self->_data(status => 'shutdown');
        }
        $self->_data(post_shutdown => 1);
    }

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

    if (defined $timeout && $timeout && !$self->is_removed && $is_active) {
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
                , uid => Ravada::Utils::user_daemon->id
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
    $self->_set_displays_active(0, $info);
    delete $info->{ip};
    $self->_data(info => encode_json($info));
    # only if not volatile
    my $request;
    $request = $arg{request} if exists $arg{request};
    if ( !$self->is_local && !$self->is_volatile && $self->has_non_shared_storage()) {
        my $req = Ravada::Request->rsync_back(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain => $self->id
            ,id_node => $self->_vm->id
            ,at => time + Ravada::setting(undef,"/backend/delay_migrate_back")
        );
    }

    $self->_schedule_compact();
    $self->needs_restart(0) if $self->is_known()
                                && $self->needs_restart()
                                && !$is_active;
}

sub _schedule_compact($self) {

    return if !Ravada::Front::setting(undef,"/backend/auto_compact");
    return if !$self->auto_compact;

    my ($req_compact) = grep {$_->command eq 'compact' } $self->list_requests(1);
    return if $req_compact;

    my $time_compact = Ravada::Front::setting(undef,"/backend/auto_compact/time");
    my ($hours_c,$min_c) = split /:/, $time_compact;
    my @now = localtime(time);
    my $hours = $hours_c - $now[2];
    my $min = $min_c - $now[1];

    my $at = time+$hours*3600 + $min*60;

    Ravada::Request->compact(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain => $self->id
            ,at => time+$hours*3600 + $min*60
            ,keep_backup => 0
    );
}

sub _set_displays_builtin_active($self, $is_active=1) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_displays set is_active=?"
        ." WHERE id_domain=? AND is_builtin=?"
    );
    $sth->execute($is_active, $self->id,1);

}

sub _set_displays_active($self, $is_active, $info=undef) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_displays set is_active=?"
        ." WHERE id_domain=?"
    );
    $sth->execute($is_active, $self->id);

    if ( $info && exists $info->{hardware} && exists $info->{hardware}->{display} ){
        for my $display (@{$info->{hardware}->{display}}) {
            $display->{is_active} = $is_active;
        }
    }
}

sub _post_reboot {
    my $self = shift;
    $self->_data(status => 'rebooted');
    $self->_remove_iptables();
    $self->_close_exposed_port();
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
    eval {
    $is_active = $self->$orig();
    };
    warn $@ if $@;

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

sub _around_reboot_now {
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

sub alias($self){ return ($self->_data('alias') or $self->_data('name')) }

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
        for (qw(public_ip active description is_active id_vm)) {
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
       return $self->_add_expose($internal_port, $name, $restricted);
    }
}

=head2 exposed_port

Returns all the data from an exposed port.

Argument: number or name description of the port permission.

    my $port_data = $domain->exposed_port(80);

    my $port_data = $domain->exposed_port('web');

=cut


sub exposed_port($self, $search, $value=undef) {
    confess "Error: you must supply a port number or name of exposed port"
        if !defined $search || !length($search);

    for my $port ($self->list_ports) {
        if ( defined $value ) {
            return $port if exists $port->{$search} && defined $port->{$search}
            && $port->{$search} eq $value;
            next;
        }
        if ( $search =~ /^\d+$/ ) {
            return $port if $port->{internal_port} eq $search;
        } else {
            return $port if defined $port->{name} && $port->{name} eq $search;
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
    $args{id_vm} = $self->_vm->id if $args{public_port} && !$args{id_vm};

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

sub _exists_port_expose($self, $name) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM domain_ports "
        ." WHERE id_domain=? AND name=?"
    );
    $sth->execute($self->id,$name);
    my ($id) = $sth->fetchrow;
    return $id;
}

sub _add_expose($self, $internal_port, $name, $restricted) {
    confess "Error: duplicated expose name '$name'"
    if $self->_exists_port_expose($name);

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO domain_ports (id_domain"
        ."  ,public_port, internal_port"
        ."  ,name, restricted"
        ."  ,id_vm "
        .")"
        ." VALUES (?,?,?,?,?,?)"
    );


    my $public_port;
    for ( 1 .. 100 ) {
        eval {
            $public_port = $self->_vm->_new_free_port() if !$self->is_base;
        };
        die $@ if $@ && $@ !~ /no free ports/i;
        eval {
            $sth->execute($self->id
                , $public_port, $internal_port
                , ($name or undef)
                , $restricted
                , $self->_vm->id
            );
            $sth->finish;
        };
        last if !$@;

        warn "Warning: public_port = $public_port , internal_port=$internal_port\n$@"
        if $@;

        next if ( $@ =~ /Duplicate entry .*for key.*public/ # mysql
            || $@ =~ /UNIQUE constraint failed.*public/   # sqlite
        );
        confess $@;
    }

    $self->_open_exposed_port($internal_port, $name, $restricted)
        if $self->is_active && $self->ip;
    return $public_port;
}

sub _set_public_port($self, $id_port, $internal_port, $name, $restricted) {
    my $public_port;
    eval {
        $public_port = undef;
        $public_port = $self->_vm->_new_free_port();
    };
    my $error = $@;
    for (;;) {
        if ($id_port) {
            my $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_ports set public_port=?"
                ." , id_vm=?"
                ." WHERE id_domain=? AND internal_port=?"
            );
            eval {
                $sth->execute($public_port, $self->_vm->id, $self->id, $internal_port);
            };
            die $@ if $@ && $@ !~ /uplicate entry/;
            return $public_port if !$@;
        } else {
            my $sth = $$CONNECTOR->dbh->prepare("INSERT INTO domain_ports "
                ."(id_domain, public_port, internal_port, name, restricted, id_vm)"
                ." VALUES(?,?,?,?,?,?) "
            );
            eval {
                $sth->execute( $self->id
                    ,$public_port, $internal_port
                    ,( $name or undef )
                    ,$restricted
                    ,$self->_vm->id
                );
            };
            die $@ if $@ && $@ !~ /uplicate entry/;
            return $public_port if !$@;
        }
        $public_port += int(rand(10))+1;
    }
    if ($error) {
        my $user = Ravada::Auth::SQL->search_by_id($self->_data('id_owner'));
        $user->send_message($error);
        warn $error;
        die $error;
    }
}

sub _used_ports_iptables($self, $port, $skip_port) {
    my $used_port = {};
    $self->_vm->_list_used_ports_iptables($used_port);
    return 0 if !$used_port->{$port} || $used_port->{$port} eq $skip_port;
    return 1;
}

sub _used_port_displays($self, $port, $skip_id_port) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_displays dd,domains d"
        ." WHERE dd.id_domain=d.id "
        ."   AND dd.id_domain_port <> ?"
    );
    $sth->execute($skip_id_port);
    while ( my $row = $sth->fetchrow_hashref ) {
        return 1 if defined $row->{port} &&  $row->{port} == $port;
    }
    for my $display ( $self->display_info(Ravada::Utils::user_daemon()) ) {
        next if !$display->{is_builtin};
        return 1 if exists $display->{port}
                && $display->{port} && $display->{port} == $port;
    }
    return 0;
}

sub _open_exposed_port($self, $internal_port, $name, $restricted, $remote_ip=undef) {
    my $debug_ports = Ravada::setting(undef,'/backend/debug_ports');
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,public_port FROM domain_ports"
        ." WHERE id_domain=? AND internal_port=?"
    );
    $sth->execute($self->id, $internal_port);
    my ($id_port, $public_port) = $sth->fetchrow();

    my $internal_ip;
    for ( 1 .. 5 ) {
        $internal_ip = $self->ip;
        last if $internal_ip;
        sleep 1;
    }
    die "Error: I can't get the internal IP of ".$self->name." ".($internal_ip or '<UNDEF>').". Retry."
        if !$internal_ip || $internal_ip !~ /^(\d+\.\d+)/;

    die "Error: No NAT ip in domain ".$self->name." found. Retry.\n"
    if !$self->_vm->_is_ip_nat($internal_ip);

    if ($public_port
        && ( $self->_used_ports_iptables($public_port, "$internal_ip:$internal_port")
            || $self->_used_port_displays($public_port,$id_port))
        ) {
        warn $self->name." cleared duplicate $public_port\n"
        if $debug_ports;
        $public_port = undef;
    }

    $public_port = $self->_set_public_port($id_port, $internal_port, $name, $restricted)
    if !$public_port;

    my $local_ip = $self->_vm->ip;
    $sth = $$CONNECTOR->dbh->prepare("UPDATE domain_ports set internal_ip=?"
            ." WHERE id_domain=? AND internal_port=?"
    );
    $sth->execute($internal_ip, $self->id, $internal_port);
    $self->_update_display_port_exposed($name, $local_ip, $public_port, $internal_port);

    if ( !$> && $public_port ) {
        $self->_delete_iptables_nat($public_port, $internal_ip
            , $internal_port, $debug_ports);
        $self->_delete_iptables_forward($internal_ip, $internal_port);

        warn $self->name." open $public_port ->"
        ." $internal_ip:$internal_port\n"
        if $debug_ports;

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
        $self->_open_exposed_port_client($internal_port, $restricted, $remote_ip);
    }
}

sub _delete_iptables_forward($self,$internal_ip, $internal_port) {
    my ($out, $err) = $self->_vm->run_command("iptables-save");
    my @open1 = (grep /-A FORWARD.* -d $internal_ip\/32 .*--dport $internal_port -j ACCEPT/, split/\n/,$out );
    for my $line (@open1) {
        $line =~ s/^-A/-D/;
        my ($out,$err) = $self->_vm->run_command("iptables",split(/ /,$line),"-w");
        warn $out if$out;
        warn $err if $err;
    }

}

sub _delete_iptables_nat($self, $public_port, $internal_ip, $internal_port
                            , $debug_ports) {
    my ($out, $err) = $self->_vm->run_command("iptables-save","-t","nat");
    my @open1 = (grep /--dport $public_port/, split/\n/,$out );
    my @open2 = (grep /--to-destination $internal_ip:$internal_port/, split/\n/,$out );
    my %removed;
    for my $line ( @open1, @open2 ) {
        next if $removed{$line}++;
        warn $self->name." clean $line\n" if $debug_ports;
        $line =~ s/^-A/-t nat -D/;
        my ($out,$err) = $self->_vm->run_command("iptables",split(/ /,$line),"-w");
        warn $out if$out;
        warn $err if $err;
    }
}

sub _update_display_port_exposed($self, $name, $local_ip, $public_port, $internal_port) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_displays "
        ." SET ip=?,listen_ip=?,port=?,is_active=?,id_vm=? "
        ." WHERE driver=? AND id_domain=?"
    );
    my $is_builtin;
    for (1 .. 10) {
        eval {
            $sth->execute($local_ip, $local_ip, $public_port,1, $self->_vm->id
                ,$name, $self->id);
        };
        warn "Warning: $@".Dumper([$name, $public_port]) if $@;
        last if !$@ || ( $@ !~ /(Duplicate entry .* for key|UNIQUE constraint).*port/);
        next if $self->_check_duplicate_display_port_down($public_port);
        $is_builtin = $self->_is_display_builtin($name) if !defined $is_builtin;
        if ($is_builtin) {
            warn "Duplicated port $public_port in domain_displays";
            $self->_fix_duplicate_display_port($public_port);
        } else {
            $sth->execute($local_ip, $local_ip, undef,1,$self->_vm->id, $name, $self->id);
            if ($internal_port) {
                my $sth2 = $$CONNECTOR->dbh->prepare(
                    "UPDATE domain_ports set public_port=NULL "
                    ." WHERE id_domain=? AND internal_port=?"
                );
                $sth2->execute($self->id, $internal_port);
            }
            my $msg = "Error: duplicated port $public_port $@. Retry.\n";
            warn $msg;
            die $msg;
        }
    }
    confess $self->name." [".$self->id."] $name $public_port $@" if $@;
}

sub _check_duplicate_display_port_down($self, $port) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,id_domain,driver FROM domain_displays "
        ." WHERE port=? AND id_vm=?"
    );
    $sth->execute($port, $self->_vm->id);
    my ( $id, $id_domain, $driver ) = $sth->fetchrow;
    return if !$id;

    my $domain = Ravada::Domain->open($id_domain);
    return if $domain->is_active();

    my $sth_down = $$CONNECTOR->dbh->prepare("UPDATE domain_displays SET port=NULL,is_active=0"
        ." WHERE id=?");
    $sth_down->execute($id);

    warn "clearing port $driver $port [$id], domain ".$domain->name;
}

sub _open_iptables_state($self) {
    my $local_net = $self->ip;
    return if !$local_net;
    $local_net =~ s{(.*)\.\d+}{$1.0/24};

    $self->_vm->iptables_unique(
        I => 'FORWARD'
        ,m => 'state'
        ,d => $local_net
        ,state => 'NEW,RELATED,ESTABLISHED'
        ,j => 'ACCEPT'
    );
}

sub _open_exposed_port_client($self, $internal_port, $restricted, $remote_ip=undef) {

    my $internal_ip = $self->ip;
    return if !$internal_ip;

    if (!defined $remote_ip) {
        $remote_ip = '0.0.0.0/0';
        $remote_ip = $self->remote_ip if $restricted;
    } else {
        $remote_ip = '0.0.0.0/0' if !$restricted;
    }
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

sub open_exposed_ports($self, $remote_ip=undef) {
    my @ports = $self->list_ports();
    return if !@ports;
    return if !$self->is_active;

    if (!$self->has_nat_interfaces) {
        $self->_set_ports_direct();
        return;
    }

    my $ip = $self->ip;
    if ( ! $ip ) {
        die "Error: No ip in domain ".$self->name.". Retry.\n";
    }

    if (!$self->_vm->_is_ip_nat($ip)) {
        die "Error: No NAT ip in domain ".$self->name." found. Retry.\n";
    }

    $self->display_info(Ravada::Utils::user_daemon);
    for my $expose ( @ports ) {
        $self->_open_exposed_port($expose->{internal_port}, $expose->{name}
            ,$expose->{restricted}, $remote_ip);
    }
}

sub _set_ports_direct($self) {
    my $sth_update = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_ports set public_port=NULL "
        ." WHERE id_domain=?"
    );
    $sth_update->execute($self->id);

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
        $port{$row->{public_port}} = $row if $row->{public_port};
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
             && exists $port{$args{dport}}
             && exists $args{'to-destination'}
         ) {
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
        $clone_port{$data->{internal_port}}++
        if $data->{internal_port};
    }

    if ($self->is_known() && !$self->is_base && $self->id_base) {
        my $base = Ravada::Front::Domain->open($self->id_base);
        my @ports_base = $base->list_ports();
        for my $data (@ports_base) {
            next if exists $clone_port{$data->{internal_port}};
            if ($self->_vm) {
                unlock_hash(%$data);
                eval {
                    $data->{public_port} = '';
                    $data->{public_port} = $self->_vm->_new_free_port();
                };
                my $error = $@;
                if ($error) {
                    my $user = Ravada::Auth::SQL->search_by_id($self->_data('id_owner'));
                    $user->send_message(substr($error,0,80));
                }
                lock_hash(%$data);
            }
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

    push @iptables, ( $self->_active_iptables(id_domain => $self->id))
    if !$port && $self->is_known();

    push @iptables, ( $self->_active_iptables(port => $port, id_vm => $id_vm) ) if $port;

    my %rule;
    for my $row (@iptables) {
        my ($id, $id_vm, $iptables) = @$row;
        next if !$id_vm;
        push @{$rule{$id_vm}},[ $id, $iptables ];
    }
    for my $id_vm (keys %rule) {
        my $vm;
        eval { $vm = Ravada::VM->open($id_vm) };
        next if !$vm || $@ =~ /can't find VM/i;
        die $@ if $@;
        for my $entry (@ {$rule{$id_vm}}) {
            my ($id, $iptables) = @$entry;
            $self->_delete_ip_rule($iptables, $vm) if !$>;
            $sth->execute($id);
        }
    }

    $self->_clean_iptables($port) if $port;
}

sub _clean_iptables($self, $port) {
    my ($out, $err) = $self->_vm->run_command("iptables-save");
    my @open1 = (grep /--dport $port/, split/\n/,$out );

    my $debug_ports = Ravada::setting(undef,'/backend/debug_ports');
    for my $line ( @open1 ) {
        next if $line !~ /^-A RAVADA/;
        warn $self->name." clean $line\n" if $debug_ports;
        $line =~ s/^-A/-D/;
        my ($out,$err) = $self->_vm->run_command("iptables",split(/ /,$line),"-w");
        warn $out if$out;
        warn $err if $err;
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
            eval { $self->remove_disks(); };
            die $@ if $@ && $@ !~ /domain not available/;
            $owner = Ravada::Utils::user_daemon() if !$owner;
            $self->_after_remove_domain($owner);
        }
    $self->remove(Ravada::Utils::user_daemon);

    $owner->remove() if $owner && $owner->is_temporary();
}

sub _post_resume {
    my $self = shift;
    return $self->_post_start(@_);
}

sub _timeout_shutdown($self, $value=undef) {
    $TIMEOUT_SHUTDOWN = $value if defined $value;
    return $TIMEOUT_SHUTDOWN;
}

sub _timeout_reboot($self, $value) {
    $TIMEOUT_REBOOT = $value if defined $value;
    return $TIMEOUT_REBOOT;
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

    my $is_active = $self->is_active;
    if ( $is_active ) {
        $self->_data('status','active');
        $self->_set_displays_builtin_active();
    }
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set start_time=?,is_compacted=? "
        ." WHERE id=?"
    );
    $sth->execute(time, 0, $self->id);
    $sth->finish;

    $self->_data('internal_id',$self->internal_id);

    $self->_add_iptable(@_) if $self->_has_builtin_display();
    $self->_update_id_vm();
    Ravada::Request->open_exposed_ports(
            uid => $arg{user}->id
            ,id_domain => $self->id
            ,retry => 20
            ,remote_ip => $remote_ip
    ) if $is_active && $remote_ip && $self->list_ports();

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
    if ($is_active && $arg{remote_ip}) {
        $self->_data('client_status', $arg{remote_ip});
        $self->_data('client_status_time_checked', time );
        if ($self->_has_builtin_display()) {
            $self->display($arg{user});
        }
    }
    $self->info($arg{user}) if $is_active;
    Ravada::Request->set_time(uid => Ravada::Utils::user_daemon->id
        , id_domain => $self->id
        , retry => $RETRY_SET_TIME
    ) if $set_time;
    Ravada::Request->enforce_limits(at => time + 60);
    if ( $self->is_pool ) {
        $self->_data('comment' => $arg{user}->name);
        Ravada::Request->manage_pools(
            uid => Ravada::Utils::user_daemon->id
        )
    }

    $self->_check_port_conflicts();

    $self->post_resume_aux(set_time => $set_time);
}

sub _check_port_conflicts($self) {
    my @displays = $self->_get_controller_display();
    my $sth = $self->_dbh->prepare("SELECT id,id_domain,internal_port FROM domain_ports"
        ." WHERE public_port=? AND is_active=1 AND id_domain <> ?"
    );
    for my $display ( @displays ) {
        for my $port ($display->{port}) {
            $sth->execute($port, $self->id);
            while ( my ($id, $id_domain, $internal_port) = $sth->fetchrow ) {
                # Updating the graphics port is not possible rightnow libvirt 5.0
                # my $new_port = $self->_vm->new_free_port();
                # $self->_update_device_graphics($display->{driver},{port => $new_port});

                my $req_close= Ravada::Request->close_exposed_ports(
                           uid => Ravada::Utils::user_daemon->id
                         ,port => $internal_port
                    ,id_domain => $id_domain
                        ,clean => 1
                );
                my $req = Ravada::Request->open_exposed_ports(
                           uid => Ravada::Utils::user_daemon->id
                    ,id_domain => $id_domain
                ,after_request => $req_close->id
                ,retry => 20
                ,_force => 1
                );
            }
        }
    }
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
    my $local_ip = delete $args{local_ip};

    my $user = $args{user} or confess "ERROR: Missing user";
    my $uid = $user->id;

    return if !$self->is_active;
    my %port_dupe;
    for my $display_info ( $self->display_info($user)) {
        next if !$display_info->{is_builtin};

        my $local_ip = ($local_ip or $display_info->{listen_ip} or $display_info->{info}->{ip});
        my @port = ( $display_info->{port});

        for my $local_port ( @port ) {
            #confess Dumper($display_info) if $self->name eq 'tst_vm_v20_volatile_clones_12' &&( !defined $local_port || !$local_port || $local_port <1) ;
            next if !defined $local_port || !$local_port || $local_port <1 ;

            die $self->name." port $local_port duplicated in displays $display_info->{driver} "
            ." and $port_dupe{$local_port} "
            if $port_dupe{$local_port};

            $port_dupe{$local_port} = $display_info->{driver};

            $self->_remove_iptables( port => $local_port );

            $self->_open_port($user, $remote_ip, $local_ip, $local_port);
            if ($remote_ip eq '127.0.0.1' ) {
                $self->_open_port($user, $self->_vm->ip, $local_ip, $local_port);
            }
            $self->_close_port($user, '0.0.0.0/0', $local_ip, $local_port);
        }
    }

}

sub _delete_ip_rule ($self, $iptables, $vm = $self->_vm) {

    confess if !ref($vm);
    return if !$vm->is_active;

    my ($s, $d, $filter, $chain, $jump, $extra) = @$iptables;
    lock_hash %$extra;

    $filter = 'filter' if !$filter;

    if ($s) {
        $s = undef if $s =~ m{^0\.0\.0\.0};
        $s .= "/32" if defined $s && $s !~ m{/};
    }
    $d .= "/32" if defined $d && $d !~ m{/};

    my $iptables_list = $vm->iptables_list();

    my $removed = 0;
    for my $line (@{$iptables_list->{$filter}}) {
        my %args = @$line;
        next if defined $chain && $args{A} ne $chain;
        next if $args{A} =~ /LIBVIRT_/;
        if((!defined $jump || ( exists $args{j} && $args{j} eq $jump ))
           && ( !defined $s || (exists $args{s} && $args{s} eq $s))
           && ( !defined $d || ( exists $args{d} && $args{d} eq $d))
           && (exists $extra->{d_port} && $args{dport} eq $extra->{d_port}))
        {

           my $curr_chain = delete $args{A};
           if ($vm->is_active) {
                my @cmd = ("iptables", "-t", $filter, "-D", $curr_chain);
                my $m = delete $args{m};
                my $p = delete $args{p};
                push @cmd,("-m" => $m) if $m;
                push @cmd,("-p" => $m) if $p;
                for my $key ( sort keys  %args) {
                    my $dash = '-';
                    $dash = '--' if length($key)>1;
                    push @cmd, ("$dash$key" => $args{$key});
                }
                my ($out, $err) = $vm->run_command(@cmd);
                warn $err if $err;
           }
           $removed++;
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

    $self->_vm->iptables_unique(
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

sub show_clones($self,$value=undef) {
    return $self->_data('show_clones',$value);
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
        $is_volatile = ! $self->is_persistent();
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
    return if $self->is_active();
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


sub _around_rename($orig, $self, %args) {
    my $name = delete $args{name};
    my $user = delete $args{user};

    $self->id();

    return if $name eq $self->_data('name')
            && $name eq $self->_data('alias');

    $self->_vm->_check_duplicate_name($name, 1)
    if $name ne $self->_data('name');

    if ($name eq $self->_data('name') && $name ne $self->_data('alias')) {
        $self->_data('alias' => $name);
        return;
    }

    $self->shutdown(user => $user)  if $self->is_active;

    my $alias = $name;
    if ($name !~ /^[a-zA-Z0-9_-]+$/) {
        $alias = $self->_vm->_set_alias_unique($alias or $name);
        $name = $self->_vm->_set_ascii_name($name);
    }

    confess if !defined $name || !length($name);

    $self->$orig(name => $name);

    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set name=?,alias=? WHERE id=?"
    );
    $sth->execute($name, $alias, $self->id);

    $self->{_name} = $name;
    $self->{_data}->{name} = $name;
    $self->{_data}->{alias} = $alias;

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

    my $machine = 'unknown';
    $machine = $self->_os_type_machine()
    if defined $self && $self->type eq 'KVM';

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
                next if $machine =~ /^pc-q35/
                    && $name eq 'disk'
                    && $option->{name} =~ /^IDE$/i;
                push @options,lc($option->{name});
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
    my %ip;
    my $first_ip;
    while ( my ($remote_ip, $iptables_json ) = $sth->fetchrow() ) {
        my $iptables = decode_json($iptables_json);
        next if $iptables->[4] ne 'ACCEPT';
        $ip{$remote_ip}++;
        $first_ip = $remote_ip if !defined $first_ip;
    }
    $sth->finish;
    return keys %ip if wantarray;

    for my $ip (keys %ip) {
        return $ip if $ip eq '127.0.0.1';
    }
    return $first_ip;

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
        return $type if $type ne 'Domain';
    }
    return 'Unknown' if !exists $self->{_data}->{vm};
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
        $files = [ $self->list_volumes(), @files_base ];
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
    my $rsync = File::Rsync->new(update => 1, sparse => 1, archive => 1);
    my $time_rsync = time;
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
        next if _check_stat($file, $vm_local, $node);
        my $msg = $self->_msg_log_rsync($file, $node, "rsync", $request);

        $request->status("syncing")         if $request;
        $request->error("Syncing $file")    if $request;
        $request->error($msg)               if $request && $DEBUG_RSYNC;
        warn "$msg\n" if $DEBUG_RSYNC;

        my $t0 = time;
        $rsync->exec(src => $src, dest => $dst);
        $msg = "Domain::rsync ".(time - $t0)." seconds $file";
        warn $msg if $DEBUG_RSYNC;
        $request->error($msg) if $request;
        if ($rsync->err) {
            $request->status("done")                    if $request;
            $request->error(join(" ",@{$rsync->err}))   if $request;
            confess "error syncing from $src to $dst \n"
            .join(' ',@{$rsync->err});
        }
    }
    $request->error("rsync done ".(time - $time_rsync)." seconds")  if $request;
    $node->refresh_storage_pools();
    $request->error("")                                             if $request;
}

sub _check_stat($file, $vm1, $vm2) {
    return if !$vm2->file_exists($file);
    my @cmd = ("stat","-c",'"%A %s %y"',$file);

    my ($out1, $err1) = $vm1->run_command(@cmd);
    my ($out2, $err2) = $vm2->run_command(@cmd);
    $out1 =~ s/^"(.*)"$/$1/;
    $out2 =~ s/^"(.*)"$/$1/;
    warn "$file\n$out1\n$out2\n" if $DEBUG_RSYNC;

    return $out1 eq $out2;
}

sub _msg_log_rsync($self, $file, $node, $sub, $request) {
    my $msg = '';
    $msg .= " [req=".$request->id.",".$request->command."] " if $request;
    $msg .="Domain::$sub ".$self->name.". Tranferring $file to ".$node->host;
    return $msg;
}

sub _rsync_volumes_back($self, $node, $request=undef) {
    my $rsync = File::Rsync->new(update => 1, sparse => 1, archive => 1);
    my $vm_local = $self->_vm->new( host => 'localhost' );
    for my $file ( $self->list_volumes() ) {
        my ($dir) = $file =~ m{(.*)/.*};
        next if $vm_local->shared_storage($node, $dir);

        my $msg = $self->_msg_log_rsync($file, $node, "rsync_back", $request);

        $request->status("syncing") if $request;
        $request->error($msg)       if $request;
        warn "$msg\n" if $DEBUG_RSYNC;
        my $t0 = time;
        $rsync->exec(src => 'root@'.$node->host.":".$file ,dest => $file );
        warn "Domain::rsync_volumes_back ".(time - $t0)." seconds $file" if $DEBUG_RSYNC;
        if ( $rsync->err ) {
            $request->status("done",join(" ",@{$rsync->err}))   if $request;
            last;
        }
    }
    $self->_vm->refresh_storage_pools();
}

sub _pre_migrate($self, $node, $request = undef) {

    confess "Error: node ".$node->name." not active" if !$node->is_active(1);

    $self->_check_equal_storage_pools($node) if $self->_vm->is_active;

    $self->_internal_autostart(0);

    $self->check_status();
    confess "ERROR: Active domains can't be migrated"   if $self->is_active;

    if ( $self->id_base ) {
        my $base = Ravada::Domain->open($self->id_base);
        confess "ERROR: base ".$base->name." not prepared in node ".$node->name
        if !$base->base_in_vm($node->id);
        confess "ERROR: base id ".$self->id_base." not found."  if !$base;

        return unless $self->_check_all_parents_in_node($node);

        $self->_set_base_vm_db($node->id,0) unless $node->is_local;
    }
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
        return if !$value && !$self->is_known;
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
        $self->_check_all_parents_in_node($vm);
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

sub _check_all_parents_in_node($self, $vm) {
    my @bases;
    my $base = $self;
    for ( ;; ) {
        last if !$base->id_base;
        $base = Ravada::Domain->open($base->id_base);
        push @bases,($base) if !$base->base_in_vm($vm->id)
        || !$base->_base_files_in_vm($vm);
    }
    return 1 if !@bases;
    my $req;
    for my $base ( reverse @bases) {
        $base->_set_base_vm_db($vm->id,0);
        my @after_req;
        @after_req = ( after_request_ok => $req->id) if $req;
        $req = Ravada::Request->set_base_vm(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain => $base->id
            ,id_vm => $vm->id
            ,@after_req
        );
    }
    return 0;
}

sub _set_clones_autostart($self, $value) {
    for my $clone_data ($self->clones) {
        next if $clone_data->{is_volatile};
        my $clone = Ravada::Domain->open($clone_data->{id}) or next;
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

    confess "ERROR: Missing user owner of new domain"   if !$user;

    for (qw(is_pool start add_to_pool from_pool with_cd volatile id_owner
        alias storage options)) {
        delete $args{$_};
    }
    confess "ERROR: Unknown arguments ".join(",",sort keys %args)   if keys %args;
}

=head2 list_vms

Returns a list for virtual machine managers where this domain is base

=cut

sub list_vms($self, $check_host_devices=0) {
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
    return @vms if !$check_host_devices;

    return $self->_filter_vm_available_hd(@vms);
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

sub _base_files_in_vm($self,$vm) {
    $vm = Ravada::VM->open($vm) if !ref($vm);
    for my $file ($self->list_files_base) {
        return 0 if !$vm->file_exists($file);
    }
    return 1;
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
    my $id_daemon = Ravada::Utils::user_daemon->id;
    for my $current ( sort { $a->{name} cmp $b->{name} } $self->clones) {
        next if $current->{is_base} ||
            ( $current->{is_volatile} && $current->{id_owner} != $id_daemon);
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
            next if !$clone; #it may be removed on shutdown

            if(!$clone->client_status
                || lc($clone->client_status) eq lc('disconnected')) {
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
    my @clones = grep {!$_->{is_base} && $_->{is_pool} } $self->clones ;
    if (!$clone_data && scalar(@clones)<$self->pool_clones) {
        $clone_data = $self->_create_clone_in_pool();
    }
    die "Error: no free clones in pool for ".$self->name."\n"
        if !$clone_data;

    my $clone = Ravada::Domain->open($clone_data->{id});
    $clone->id_owner($user->id);
    $clone->_data( comment => $user->name );
    return $clone;
}

sub _create_clone_in_pool($self) {

    my $owner = Ravada::Auth::SQL->search_by_id($self->_data('id_owner'));

    my $n = scalar $self->clones()+1;
    my $clone = $self->clone(
        user => $owner
        ,name => $self->name."-".$n."-".Ravada::Utils::random_name(2)
        ,add_to_pool => 1
        ,from_pool => 0
        ,start => 1
    );
    my $clone_data = { id => $clone->id };
    return $clone_data;

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

    confess "Error: can't do force on read only" if $force && $self->readonly;

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

sub _run_iptstate($self, $force=undef) {
    if (!$force && $self->_vm->{_iptstate}
        && ( time - $self->_vm->{_iptstate_time} < $TIME_CACHE_NETSTAT+1 ) ) {
        return $self->_vm->{_iptstate};
    }
    my @cmd = ("iptstate", "-1","-L","--no-color","-o");
    my ( $out, $err) = $self->_vm->run_command(@cmd);
    $self->_vm->{_iptstate} = $out;
    $self->_vm->{_iptstate_time} = time;

    return $out;
}


sub _client_connection_status($self, $force=undef) {

    my $status = $self->_client_connection_status_display($force);
    return $status if $status =~ /^connected/;

    $status = $self->_client_connection_status_port($force);
    return $status;
}

sub _client_connection_status_display($self, $force) {
    my $netstat_out = $self->_run_netstat($force);
    for my $display  ( $self->display_info(Ravada::Utils::user_daemon )) {
        my $port = $display->{port} or next;
        my $ip = $display->{ip} or next;

        my @out = split(/\n/,$netstat_out);
        for my $line (@out) {
            my @netstat_info = split(/\s+/,$line);
            if ( $netstat_info[2] =~ /:$port$/ ) {
                return 'connected ('.$display->{driver}.")";
            }
        }
    }
    return 'disconnected';
}


sub _client_connection_status_port($self, $force) {
    my $iptstate_out = $self->_run_iptstate($force);

    for my $port ( $self->list_ports ) {
        my $public_port = $port->{public_port} or next;
        for my $line (split /\n/,$iptstate_out) {
            my ($ip_port,$status) = $line =~/^[0-9.:]+\s+\d+\.\d+\.\d+\.\d+:(\d+)\s+\w+\s+(\w+)/;
            next if !defined $ip_port || $public_port != $ip_port;
            last if $status ne 'ESTABLISHED';
            return 'connected ('.($port->{name} or $port->{internal_port}).")";
        }
    }
    return 'disconnected';
}

=head2 needs_restart

Returns true or false if the virtual machine needs to be restarted so some
hardware change can be applied.

=cut

sub needs_restart($self, $value=undef) {
    return $self->_data('needs_restart') if !defined $value;
    return $self->_data('needs_restart',$value);
}

sub auto_compact($self, $value=undef) {
    return $self->_data('auto_compact', $value) if defined $value;

    $value = $self->_data('auto_compact');
    if (!defined $value && $self->id_base) {
        my $base = Ravada::Front::Domain->open($self->id_base);
        return $base->auto_compact;
    }
    return $value;
}

sub _post_change_hardware($self, $hardware, $index, $data=undef) {

    if ($hardware eq 'disk' && ( defined $index || $data ) && $self->is_known() ) {
        my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM volumes WHERE id_domain=?");
        $sth->execute($self->id);
        $self->list_volumes_info();
    }
    $self->info(Ravada::Utils->user_daemon) if $self->is_known();

    $self->needs_restart(1) if $self->is_known && $self->_data('status') eq 'active' && $hardware ne 'memory' && $hardware !~ /cpu/;
    $self->post_prepare_base() if $self->is_base();
}

sub _fix_hw_booleans($data) {
    for my $key (keys %$data) {
        next if !ref($data->{$key});
        if (ref($data->{$key}) eq 'HASH') {
                _fix_hw_booleans($data->{$key});
        } elsif(ref($data->{$key}) eq 'ARRAY') {
            for my $item (@{$data->{$key}}) {
                _fix_hw_booleans($item);
            }
        } elsif(ref($data->{$key}) eq 'JSON::PP::Boolean') {
                $data->{$key} = ''.$data->{$key};
        } else {
            confess "Error: expecting scalar or hash or boolean "
                .Dumper(ref($data->{$key}) ,$data->{$key});
        }
    }
}

sub _fix_hw_ignore_fields($data) {
    unlock_hash(%$data);
    for my $key (keys %$data) {
        delete $data->{$key} if $key =~ /^_/;
    }
    lock_hash(%$data);
}

sub _around_change_hardware($orig, $self, $hardware, $index=undef, $data=undef) {

    _fix_hw_booleans($data);

    if ($hardware eq 'filesystem') {
        $self->_change_info_filesystem($data);
    }

    _fix_hw_ignore_fields($data);

    my $real_id_vm;
    if ($hardware eq 'disk' && !$self->_vm->is_local) {
        $real_id_vm = $self->_vm->id;
        my $vm_local = $self->_vm->new( host => 'localhost' );
        $self->_set_vm($vm_local, 1);
    }

    my $is_display_builtin;

    if ($hardware eq 'display') {

        my @display = Ravada::Front::Domain::_get_controller_display($self);
        my $current_data;
        if (defined $index) {
            $current_data = $display[$index] or confess "Error: missing graphics $index , only ".scalar(@display)." found";
            if ($current_data->{is_secondary}) {
                my ($driver) = $current_data->{driver} =~ /(.*)-\w+/;
                $current_data = $self->_get_display($driver);
            }
            if($current_data->{driver} && exists $data->{driver}
                && $data->{driver}
                && $current_data->{driver} ne $data->{driver}) {
                unlock_hash(%$data);
                $data->{port}='';
                lock_hash(%$data);
                $self->_update_display($data, $current_data);
            }
        } else {
            $current_data = $self->_get_display($data->{driver});
        }
        $is_display_builtin = $self->_is_display_builtin($current_data->{driver});
        $self->_store_display($data, $current_data);

    }
    if ( $hardware ne 'display' || $is_display_builtin) {
        unlock_hash(%$data);
        $orig->($self, $hardware, $index,$data);
        $self->_redefine_instances() if $self->is_known();
    }

    if ( $real_id_vm ) {
        my $id_vm = $real_id_vm;
        my $vm = Ravada::VM->open($id_vm);
        $self->_set_vm($vm, 1);
    }
    $self->_post_change_hardware($hardware, $index, $data);
}



sub _add_info_filesystem($self, $data) {
    return if !keys %$data;

    confess "Error: undefined source ".Dumper($data)
    if exists $data->{source} && !defined $data->{source}
    || (ref($data->{source}) && !keys %{$data->{source}});

    my $data2 = dclone($data);
    $data2->{id_domain} = $self->id;
    $data2->{source} = $data2->{source}->{dir} if ref($data2->{source});

    my $sql = "INSERT INTO domain_filesystems ("
    .join(",",sort keys %$data2)
    .") VALUES ("
    .join(",",map { '?' } keys %$data2)
    .")";

    my $sth = $$CONNECTOR->dbh->prepare($sql);
    $sth->execute(map {$data2->{$_} } sort keys %$data2);
}

sub _remove_info_filesystem($self, $id_filesystem) {

    my $sth = $self->_dbh->prepare("DELETE FROM domain_filesystems "
        ." WHERE id_domain=? AND id=?"
    );
    $sth->execute($self->id, $id_filesystem);
}

sub _change_info_filesystem($self, $data) {
    return if !keys %$data;

    my $data2 = dclone($data);
    unlock_hash(%$data);
    my $chroot = delete $data->{chroot};
    my $subdir_uid = delete $data->{subdir_uid};
    lock_hash(%$data);

    unlock_hash(%$data2);# it is local to this sub, so we may change it
    $data2->{source} = $data2->{source}->{dir} if ref($data2->{source});
    delete $data2->{target};

    my $id = delete $data2->{_id};
    confess "Missing _id in data2 ".Dumper($data2) if !defined $id;
    for my $key (keys %$data2) {
        delete $data2->{$key} if $key =~ /^_/;
    }

    my $sql = "UPDATE domain_filesystems SET "
        .join(",", map { "$_=?" } sort keys %$data2)
        ;

    my @values = map { $data2->{$_} } sort keys %$data2;
    my $sth = $self->_dbh->prepare("$sql WHERE id=?");
    $sth->execute(@values,$id);
}

sub _load_info_filesystem($self, $list) {
    my $sth = $self->_dbh->prepare(
        "SELECT * FROM domain_filesystems "
        ." WHERE id_domain=? AND source=?"
    );
    for my $item (@$list) {
        unlock_hash(%$item);

        my $source = $item->{source};
        $source = $item->{source}->{dir} if ref($item->{source});

        $sth->execute($self->id,$source);
        my $info = $sth->fetchrow_hashref();

        if ( !$info->{id} ) {
            my $data = {
                source => $source
            };
            $self->_add_info_filesystem($data);
            $sth->execute($self->id,$source);
            $info = $sth->fetchrow_hashref();
        }

        $item->{chroot} = delete $info->{chroot};
        $item->{subdir_uid} = delete $info->{subdir_uid};
        $item->{_id} = $info->{id};
        lock_hash(%$item);
    }
}

sub _create_filesystem($self, $source, $uid, $gid=0) {
    return if !defined $source;

    my @stat = stat($source);
    if (!@stat) {
        mkdir($source) or confess "$! mkdir $source";
    } else {
        my $mode = $stat[2];
        die "Error: $source already exists and is not a directory"
        if !S_ISDIR($mode) && !S_ISLNK($mode);
    }
    if (defined $uid &&( !@stat || $stat[4] != $uid)) {
        chown $uid,undef,$source or die "$! chown $uid, $gid, $source";
    }

}

sub _clone_filesystems($self) {
    my $id_base = $self->id_base() or return;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_filesystems "
        ." WHERE id_domain=?"
    );
    $sth->execute($id_base);
    while ( my $row = $sth->fetchrow_hashref ) {
        delete $row->{id};
        $self->_add_info_filesystem($row);
    }
}

sub _chroot_filesystems($self) {
    my $id_base = $self->id_base() or return;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_filesystems "
        ." WHERE id_domain=?"
    );
    $sth->execute($id_base);
    while ( my $row = $sth->fetchrow_hashref ) {
        next if !$row->{chroot};
        confess Dumper($row) if $row->{source} !~ m{^/};
        my $data = $self->_search_filesystem_index($row->{source});
        unlock_hash(%$data);
        my $source = $row->{source}."/".$self->name;
        $data->{source}->{dir} = $source;
        my $index = delete $data->{_index};
        lock_hash(%$data);

        $self->change_hardware('filesystem',$index, $data);

        $self->_create_filesystem($source,$row->{subdir_uid});
    }
    $sth->finish;
}

sub _search_filesystem_index($self, $source) {
    my $hw = $self->get_controllers();
    for my $n ( 0 .. scalar(@{$hw->{filesystem}}) ) {
        my $fs = $hw->{filesystem}->[$n];
        unlock_hash(%$fs);
        $fs->{_index} = $n;
        lock_hash(%$fs);
        return $fs if $fs->{source}->{dir} eq $source;
    }
    return;
}

sub _get_display_port($self, $display) {
    my $driver = $self->drivers('display');

    my ($selected)
    = grep { lc($_->{name}) eq lc($display->{driver}) || lc($_->{value}) eq lc($display->{driver})}
    $driver->get_options;

    confess "Error: unknown display driver $display->{driver} ".Dumper([$driver->get_options]) if !$selected;

    die "Error: display driver port not defined ".Dumper($selected)
    unless defined $selected->{data};

    $display->{port} = $selected->{data};
    $display->{driver} = $selected->{value};
}

sub _add_hardware_display($orig, $self, $index, $data) {

    my $is_builtin = 1;

    if ( $data->{driver} ) {
        die "Error: display ".$data->{driver}." duplicated.\n"
        if $self->_get_display($data->{driver});

        $is_builtin = $self->_is_display_builtin($data->{driver});
    }

    $self->_get_display_port($data)
    if exists $data->{driver}
    && !$is_builtin
    && (!exists $data->{port} || !defined $data->{port});

    if ( !$is_builtin && exists $data->{port}
        && defined $data->{port} && $data->{port} ne 'auto') {

        my $sth = $$CONNECTOR->dbh->prepare("SELECT *"
        ." FROM domain_ports WHERE id_domain=? AND internal_port=?");
        $sth->execute($self->id, $data->{port});
        my ($exposed) = $sth->fetchrow;

        confess "Error: ".$self->name."[".$self->id."] display $data->{driver} can not be used because port $data->{port} "
        ." is already exported. Remove it from hardware / ports\n"
        if $exposed;

        my $public_port = $self->expose( port => $data->{port}
            , name => $data->{driver}
            , restricted => 1
        );
        my $port = $self->exposed_port($data->{port});
        $data->{port} = $public_port;
        $data->{id_domain_port} = $port->{id};
    }

    $orig->($self, 'display', $index, $data) if $is_builtin;
    $self->_store_display($data);
}

sub _check_duplicated_volume_name($self, $file) {
    return if !$file;

    my ($name) = $file =~ m{.*/(.*)};
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,name FROM volumes WHERE id_domain=? "
        ." AND (name=? or file=?)"
    );
    $sth->execute($self->id, $name, $file);
    my ($id_found) = $sth->fetchrow;
    die "Error: volume '$name' already exists in ".$self->name."\n"
    if $id_found;
}

sub _add_hardware_disk($orig, $self, $index, $data) {

    die "Error: new disk volumes can not be added to bases\n"
    if $self->is_base;

    my $real_id_vm;
    if (!$self->_vm->is_local) {
        $real_id_vm = $self->_vm->id;
        my $vm_local = $self->_vm->new( host => 'localhost' );
        $self->_set_vm($vm_local, 1);
    }

    $self->_check_duplicated_volume_name($data->{file});
    $orig->($self, 'disk', $index, $data);

    if (( defined $index || $data ) && $self->is_known() ) {
        my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM volumes WHERE id_domain=?");
        $sth->execute($self->id);
    }
    $self->list_volumes_info();
    $self->_redefine_instances();

    if ( $real_id_vm ) {
        my $id_vm = $real_id_vm;
        my $vm = Ravada::VM->open($id_vm);
        $self->_set_vm($vm, 1);
    }
}

sub _around_add_hardware($orig, $self, $hardware, $index, $data=undef) {
    confess "Error: minimal add hardware index>=0 , got '$index'" if defined $index && $index <0;

    my $data_orig = undef;
    $data_orig = dclone($data ) if ref($data);

    if ($hardware eq 'display' ) {
        _add_hardware_display($orig, $self, $index, $data);
    } elsif ($hardware eq 'disk') {
        _add_hardware_disk($orig, $self, $index, $data);
    } else {
        $orig->($self, $hardware, $index, $data);
        if ( $hardware eq 'filesystem' ) {
            $self->_add_info_filesystem($data_orig);
        }
    }
    if (!$hardware eq 'disk' && $self->is_known() && !$self->is_base ) {
        # disk is changed in main node, then redefined already
        $self->_redefine_instances();
    }

    $self->needs_restart(1) if $self->is_known && $self->_data('status') eq 'active';
    $self->_post_change_hardware( $hardware, $index, $data);
}

sub _delete_db_display_by_driver($self, $driver) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM domain_displays WHERE id_domain=? AND driver=?"
    );
    $self->{_display_deleted}++;
    $sth->execute($self->id, $driver);
}

sub _around_remove_hardware($orig, $self, $hardware, $index=undef, $options=undef) {
    confess "Error: supply either index or options when removing hardware " if !defined $index && !defined $options;

    my $id_filesystem;
    if ( $hardware eq 'filesystem') {
        my @fs = $self->get_controller('filesystem');
        $id_filesystem = $fs[$index]->{_id};
    }

    die "Error: disk volumes can not be removed from bases\n"
    if $hardware eq 'disk' && $self->is_base;

    my $display;
    if ( $hardware eq 'display' ) {
        $display = $self->_get_display_by_index($index);
        confess "Error: display index $index not found in ".$self->name
        if !$display || !$display->{driver};

        my $driver = $display->{driver};
        if ($display->{is_secondary}) {
            my ($cur_driver) = $display->{driver} =~ /(.*)-\w+/;
            confess "I can't guess primary driver for $display->{driver}"
            if !$driver;

            $display=$self->_get_display($driver);
            confess "Error: display $driver not found in ".$self->name
            if !$display || !$display->{driver};

            $index = undef;
            $driver=$cur_driver;
        }
        if ( !$display->{is_builtin} ) {
            my $port = $self->exposed_port($display->{driver});
            $self->remove_expose($port->{internal_port}) if $port;
        }
        $self->_delete_db_display_by_driver($driver);
        if ($display->{is_builtin}) {
            if (defined $index) {
                $orig->($self, $hardware, $index);
            } else {
                $orig->($self, $hardware, $index, type => $driver);
            }
            $driver .= "-tls";
            $self->_delete_db_display_by_driver($driver);
        }
    } else {
        $orig->($self, $hardware, $index, %$options)
    }

    $self->_remove_info_filesystem($id_filesystem)
    if $hardware eq 'filesystem';

    if ( $self->is_known() && !$self->is_base ) {
        $self->_redefine_instances();
    }
    $self->_post_change_hardware( $hardware, $index);

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
    confess "Error: undefined value" unless defined $value;
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
    my $type      = delete $args{type}      or confess "Error: Missing type";

    return $self->_allow_group_access(%args, type=> $type)    if $type =~ /^group/;

    my $attribute = delete $args{attribute} or confess "Error: Missing attribute";
    my $value     = delete $args{value}     or confess "Error: Missing value";
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

sub _allow_group_access($self, %args) {
    my $group = delete $args{group};
    my $id_group = delete $args{id_group};
    confess "Error: group name or id_group required" unless $group || $id_group;
    confess "Error: wrong group name '$group'" if $group && $group =~ /^\d+$/;

    my $type = delete $args{type};
    $type =~ s/.*\.(.*)/$1/;
    $type = 'ldap' if !$type || $type eq 'group';

    confess "Error: unknown args ".Dumper(\%args) if keys %args;
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO group_access "
        ."( id_domain, id_group, name, type)"
        ." VALUES(?,?,?,? )"
    );
    $sth->execute($self->id,$id_group, $group, $type);
}

=head2 list_access_groups

Returns the list of groups who can access this virtual machine

=cut

sub list_access_groups($self, $type) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,id_group,name from group_access "
        ." WHERE id_domain=?"
        ."   AND type=?"
    );
    $sth->execute($self->id, $type);
    my @groups;
    my $sth_gname = $$CONNECTOR->dbh->prepare("SELECT name FROM groups_local WHERE id=?");
    while ( my $row = $sth->fetchrow_hashref ) {
        if (!$row->{name} && $row->{id_group}) {
            $sth_gname->execute($row->{id_group});
            ($row->{name}) = $sth_gname->fetchrow;
        }
        push @groups,($row->{name});
    }
    return @groups;
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
sub delete_ldap_access($self, @id_access) {
    for my $id_access (@id_access) {

    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM access_ldap_attribute "
        ."WHERE id_domain=? AND id=? ");
    $sth->execute($self->id, $id_access);

    }
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
    confess "Error: undefined value" unless defined $value;
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

sub list_instances($self, $id=undef) {
    return () if !$id && !$self->is_known();

    $id = $self->id if !defined $id;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_instances "
        ." WHERE id_domain=?"
    );
    $sth->execute($id);

    my @instances;
    while (my $row = $sth->fetchrow_hashref) {
        lock_hash(%$row);
        push @instances, ( $row );
    }
    return @instances;
}

=head2 has_non_shared_storage

Return wether this virtual machine has non shared storage volumes

=cut

sub has_non_shared_storage($self, $node=$self->_vm->new(host => 'localhost')) {
    my $id1 = $self->_vm->id;
    my $id2 = $node->id;

    confess "Error: both nodes are the same ".$self->_vm->name
    ." and ".$node->name
    if $id1 == $id2;

    my $nodes_id = join(",",sort ($id1,$id2));

    my $shared_storage_cache = $self->_data('shared_storage');

    my $shared_storage = {};
    $shared_storage = decode_json($shared_storage_cache)
    if $shared_storage_cache;

    my $has_non_shared;
    if ($shared_storage && exists $shared_storage->{$nodes_id}) {
        $has_non_shared = $shared_storage->{$nodes_id};
        return $has_non_shared if defined $has_non_shared;
    }
    for my $file ( $self->list_volumes ) {
        my ($dir) = $file =~ m{(.*)/};
        $has_non_shared = !$self->_vm->shared_storage($node, $dir);
        last if $has_non_shared
    }
    $shared_storage->{$nodes_id}= $has_non_shared;
    $self->_data('shared_storage' => encode_json($shared_storage));
    return $has_non_shared;
}

sub has_nat_interfaces($self) {
    return 0;
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

=head2 compact

Compact volumes of a virtual machine. It creates a backup copy unless
specified in the request.

    $domain->compact();

    $comain->compact($request);

Usually called through Ravada::Request->compact();

=cut

sub compact($self, $request=undef) {
    #first check if active, that will trigger status refresh
    die "Error: ".$self->name." can't be compacted because it is active\n"
    if $self->is_active;

    # now check the status, it may be hibernated or in some other
    my $status = $self->_data('status');
    die "Error: ".$self->name." can't be compacted because it is $status\n"
    unless $status eq 'shutdown';

    my $keep_backup = 1;
    $keep_backup = $request->defined_arg('keep_backup') if $request;
    $keep_backup = 1 if !defined $keep_backup;

    my $backed_up = '';
    $backed_up = " [backed up]" if $keep_backup;

    my $out = '';
    for my $vol ( $self->list_volumes_info ) {
        next if !$vol->file || $vol->file =~ /iso$/;
        if ( !$self->is_active ) {
            my $vm = $self->_vm->new ( host => 'localhost' );
            $vol->vm($vm);
        }
        $request->error("compacting ".$vol->file."$backed_up") if $request;
        $out .= $vol->info->{target}." ".($vol->compact($keep_backup) or '');
    }
    $request->error($out) if $request;
    $self->_data('is_compacted' => 1);

    $self->_data('has_backups' => $self->_data('has_backups') +1 ) if $keep_backup;
}

=head2 purge

Purges old backup volumes of a virtual machine

=cut


sub purge($self, $request=undef) {
    my $vm = $self->_vm->new ( host => 'localhost' );
    for my $vol ( $self->list_volumes_info ) {
        next if !$vol->file || $vol->file =~ /iso$/;
        my ($dir, $file) = $vol->file =~ m{(.*)/(.*)};
        my ($out, $err) = $vm->run_command("ls",$dir);
        die $err if $err;
        my @found = grep { /^$file/ } $out =~ m{^(.*backup)}mg;
        for my $file_backup ( @found ) {
            $vm->remove_file("$dir/$file_backup");
        }
    }
    $self->_data( 'has_backups' => 0 );
}

sub _check_port($self, $port, $ip=$self->ip, $request=undef) {
    my ($out, $err) = $self->_vm->run_command("nc","-z","-v","-w",1,$ip,$port);

    return 1 if $err =~ /succeeded!/;
    return 0 if $err =~ /failed/;
    warn $err;
    return 0;
}

sub _set_ports_down($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_ports set is_active=0 "
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);
}

sub _set_displays_down($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domain_displays set is_active=0,port=NULL "
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);
}

=head2 refresh_ports

Refresh the status of the exposed ports

=cut

sub refresh_ports($self, $request=undef) {
    return if !$self->list_ports;

    my $sth_update = $$CONNECTOR->dbh->prepare("UPDATE domain_ports "
        ." SET is_active=? "
        ." WHERE id_domain=? AND id=?"
    );
    my $sth_update_display = $$CONNECTOR->dbh->prepare("UPDATE domain_displays "
        ." SET is_active=? "
        ."  WHERE id_domain_port=?"
    );
    my $is_active = $self->is_active();
    my $ip;
    $ip = $self->ip if $is_active;

    my $port_down = 0;
    my $msg = '';
    for my $port ($self->list_ports) {
        my $is_port_active;
        if ($is_active && $ip) {
            $is_port_active = $self->_check_port($port->{internal_port}, $ip, $request);
        } else {
            $is_port_active = 0;
        }
        $port_down++ if !$is_port_active;
        $sth_update->execute($is_port_active, $self->id, $port->{id});
        $sth_update_display->execute($is_port_active, $port->{id})
        if $port->{name};

        $msg .= " , " if $msg;
        my $is_port_active_txt = "up";
        $is_port_active_txt = "down" if !$is_port_active;
        $msg .= " $port->{internal_port}:$is_port_active_txt";
    }
    die "Virtual machine ".$self->name." is not up. retry.\n"if !$ip;
    die "Virtual machine ".$self->name." $ip has ports down: $msg. retry.\n"
    if $port_down;

    if (($msg) && ($request))
    {
        my $uid = $request->args("uid");
        my $user;
        $user = Ravada::Auth::SQL->search_by_id($uid) if ($uid);
        $user->send_message($msg) if ($user);
    }
}

sub can_host_devices { return 0 }

sub add_host_device($self, $host_device) {
    my $id_hd = $host_device;
    $id_hd = $host_device->id if ref($host_device);

    confess if !$id_hd;

    my $sth = $$CONNECTOR->dbh->prepare("INSERT INTO host_devices_domain "
        ."(id_host_device, id_domain) "
        ." VALUES ( ?, ? ) "
    );
    $sth->execute($id_hd, $self->id);
}

sub remove_host_device($self, $host_device) {
    confess if !ref($host_device);
    confess if $self->readonly;

    my $id_hd = $host_device->id;

    $self->_dettach_host_device($host_device);

    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices_domain "
        ." WHERE id_domain=? AND id_host_device=?"
    );
    $sth->execute($self->id, $id_hd);
    if ($self->is_base) {
        for my $clone_data ( $self->clones ) {
            my $clone = Ravada::Domain->open($clone_data->{id});
            $clone->remove_host_device($host_device);
        }
    }
}

sub list_host_devices($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM host_devices WHERE id IN (SELECT id_host_device FROM  host_devices hd, host_devices_domain hdd "
        ." WHERE hdd.id_domain=?"
        ."    AND hdd.id_host_device = hd.id )"
        ."    AND enabled=1"
    );
    $sth->execute($self->id);

    my @found;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{devices} = '' if !defined $row->{devices};
        $row->{devices_node} = '{}' if !defined $row->{devices_node};
        push @found,(Ravada::HostDevice->new(%$row));
    }

    return @found;
}

sub list_host_devices_attached($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT hdd.*, hd.name as host_device_name "
        ." FROM host_devices_domain hdd , host_devices hd "
        ." WHERE hdd.id_domain=? "
        ."   AND hdd.id_host_device = hd.id "
        ."   AND hd.enabled=1"
    );
    $sth->execute($self->id);

    my $sth_locked = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM host_devices_domain_locked "
        ." WHERE id_domain=? AND name=?"
    );

    my @found;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{is_locked} = 0;
        if ($row->{name}) {
            $sth_locked->execute($self->id, $row->{name});
            my ($is_locked) = $sth_locked->fetchrow();
            $row->{is_locked} = 1 if $is_locked;
        }
        push @found,($row);
    }

    return @found;
}

# adds host devices to domain instance
# usually run right before startup
sub _add_host_devices($self, @args) {
    $self->_attach_host_devices(@args);
}

sub _backup_config_no_hd($self) {
    $self->_dettach_host_devices();
    $self->_data('config_no_hd' => $self->get_config_txt);
}

sub _restore_config_no_hd($self) {
    my $config_no_hd = $self->_data('config_no_hd');
    return if !$config_no_hd;
    $self->reload_config($config_no_hd);
}

sub _attach_host_devices($self, @args) {
    my @host_devices = $self->list_host_devices();
    return if !@host_devices;
    return if $self->is_active();

    my ($request);
    if (!(scalar(@args) % 2)) {
        my %args = @args;
        $request = delete $args{request} if exists $args{request};
    }

    $self->_clean_old_hd_locks();
    $self->_backup_config_no_hd();
    my $doc = $self->get_config();
    for my $host_device ( @host_devices ) {
        next if !$host_device->enabled();
        my $device_configured = $self->_device_already_configured($host_device);

        my $device;
        if ( $device_configured ) {
            if ( $host_device->enabled()
                    && $host_device->is_device($device_configured, $self->_vm->id)
                    && $self->_lock_host_device($host_device) ) {
                $device = $device_configured;
            } else {
                $self->_dettach_host_device($host_device, $doc, $device_configured);
            }
        }
        $device = $self->_search_free_device($host_device) if !$device;

        $self->_lock_host_device($host_device, $device);

        for my $entry( $host_device->render_template($device) ) {
            if ($entry->{type} eq 'node') {
                $self->add_config_node($entry->{path}, $entry->{content}, $doc);
            } elsif ($entry->{type} eq 'unique_node') {
                $self->add_config_unique_node($entry->{path}, $entry->{content}, $doc);
            } elsif($entry->{type} eq 'attribute') {
                $self->change_config_attribute($entry->{path}, $entry->{content}, $doc);
            } elsif($entry->{type} eq 'namespace') {
                $self->change_namespace($entry->{path}, $entry->{content}, $doc);
            } else {
                die "Error in host_device ".$host_device->name
                ." template: ".$entry->{path}
                ." Unknown type ".($entry->{type} or '<UNDEF>');
            }
        }
    }
    $self->reload_config($doc);

}

sub _search_free_device($self, $host_device) {
    my ($device) = $host_device->list_available_devices($self->_data('id_vm'));
    if ( !$device ) {
       $device = _refresh_domains_with_locked_devices($host_device);
       if (!$device) {
           $self->_data(status => 'down');
           $self->_unlock_host_devices();
           die "Error: No available devices in ".$self->_vm->name." for ".$host_device->name."\n";
       }
    }
    return $device;
}

sub _dettach_host_devices($self) {
    my @host_devices = $self->list_host_devices();
    for my $host_device ( @host_devices ) {
        $self->_dettach_host_device($host_device);
    }
    $self->_unlock_host_devices();
    $self->_restore_config_no_hd();
}

sub _dettach_host_device($self, $host_device, $doc=$self->get_config
    ,$device = $self->_device_already_configured($host_device)
) {

    return if !defined $device or !length($device);

    for my $entry( $host_device->render_template($device) ) {

        if ($entry->{type} eq 'node') {
            $self->remove_config_node($entry->{path}, $entry->{content}, $doc);
        } elsif ($entry->{type} eq 'unique_node') {
            $self->remove_config_node($entry->{path}, $entry->{content}, $doc);
        } elsif($entry->{type} eq 'attribute') {
            $self->remove_config_attribute($entry->{path}, $entry->{content}, $doc);
        } elsif($entry->{type} eq 'namespace') {
            $self->remove_namespace($entry->{path}, $entry->{content}, $doc);
        } else {
            die "Error in host_device ".$host_device->name
            ." template: ".$entry->{path}
            ." Unknown type ".($entry->{type} or '<UNDEF>');
        }
    }
    $self->reload_config($doc);

    $self->_unlock_host_device($device);
}

# marks a host device as being used by a domain
sub _lock_host_device($self, $host_device, $device=undef) {
    if (!defined $device) {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM host_devices_domain "
            ." WHERE id_domain=? AND id_host_device=?"
        );
        $sth->execute($self->id, $host_device->id);
        ($device) = $sth->fetchrow;
        confess "Error: no device name defined for id_domain=".$self->id
        ." and id_host_device=".$host_device->id
        if !defined $device || !length($device);
    }

    my $id_domain_locked = $self->_check_host_device_already_used($device);

    my $id_vm = $self->_data('id_vm');
    $id_vm = $self->_vm->id if !$id_vm;

    return 1 if defined $id_domain_locked &&  $self->id == $id_domain_locked;

    return 0 if defined $id_domain_locked;

    my $query = "INSERT INTO host_devices_domain_locked (id_domain,id_vm,name,time_changed) VALUES(?,?,?,?)";

    my $sth = $$CONNECTOR->dbh->prepare($query);
    cluck if !$id_vm;
    eval { $sth->execute($self->id,$id_vm, $device,time) };
    if ($@) {
        warn $@;
        $self->_data(status => 'shutdown');
        die "Error: device $device already in use $@\n";
    }

    $sth=$$CONNECTOR->dbh->prepare("UPDATE host_devices_domain SET name=?"
        ." WHERE id_domain=? AND id_host_device=?"
    );
    $sth->execute($device, $self->id, $host_device->id);

    return 1;
}

sub _clean_old_hd_locks($self) {
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices_domain_locked "
        ." WHERE id_domain=? AND id_vm <> ?"
    );
    $sth->execute($self->id, $self->_vm->id);

}

sub _unlock_host_devices($self, $time_changed=3) {
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices_domain_locked "
        ." WHERE id_domain=? AND time_changed<=?"
    );
    $sth->execute($self->id, time-$time_changed);
}

sub _unlock_host_device($self, $name) {
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices_domain_locked "
        ." WHERE id_domain=? AND name=? AND time_changed<?"
    );
    $sth->execute($self->id, $name,time-60);
}


sub _check_host_device_already_used($self, $device) {

    my $query = "SELECT id_domain,time_changed FROM host_devices_domain_locked "
    ." WHERE id_vm=? AND name=?"
    ;
    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute($self->_data('id_vm'), $device);
    my ($id_domain,$time_changed) = $sth->fetchrow;
    #    warn "\n".($id_domain or '<UNDEF>')." [".$self->id."] had locked $device\n";

    return if !defined $id_domain;
    return $id_domain if $id_domain == $self->id;

    my $domain = Ravada::Domain->open($id_domain);

    return $id_domain if time-$time_changed < 10 || $domain->is_active;

    $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices_domain_locked "
        ." WHERE id_domain=?");
    $sth->execute($id_domain);
    return;
}

sub _device_already_configured($self, $host_device) {
    my $query = "SELECT name FROM host_devices_domain WHERE id_domain=? AND id_host_device=?";

    confess if !ref($host_device);
    my @args = ($self->id, $host_device->id);

    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute(@args);

    my ($name) = $sth->fetchrow;
    return $name;
}

sub _refresh_domains_with_locked_devices($host_device) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT hdd.id_domain,hdd_locked.name "
        ." FROM host_devices_domain hdd, host_devices_domain_locked hdd_locked"
        ." WHERE hdd.id_host_device=?"
        ."   AND hdd.id_domain=hdd_locked.id_domain"
    );
    my $sth_delete = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices_domain_locked "
        ." WHERE id_domain=?");
    $sth->execute($host_device->id);

    my $free_device;
    while ( my ($id_domain, $device) = $sth->fetchrow ) {
        my $domain = Ravada::Domain->open($id_domain);
        next if $domain->is_active();
        $sth_delete->execute($id_domain);
        Ravada::Request->refresh_machine(
            id_domain => $id_domain
            ,uid => Ravada::Utils::user_daemon->id
        );
        $free_device = $device;
    }
    return $free_device;
}

sub list_backups($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM domain_backups "
        ." WHERE id_domain=?"
    );
    $sth->execute($self->id);
    my @ret;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @ret, ( $row );
    }
    return @ret;
}

sub config_files($self) {
}

sub _backup_owner($self) {
    my $owner = Ravada::Auth::SQL->search_by_id($self->_data('id_owner'));
    my $filename = $self->_vm->dir_backup()."/".$self->name."_owner.json";
    CORE::open my $out,">",$filename or die "$! $filename";
    print $out encode_json($owner->{_data});
    close $filename;

    return $filename;
}

sub _list_parent_volumes($self) {
    die "Error: ".$self->name." has no parent" if !$self->_data('id_base');
    my $base = Ravada::Domain->open($self->_data('id_base'));

    return [$base->list_files_base()];
}

sub _expand_backup_metadata($self, $data) {
    $data->{owner} = Ravada::Utils::search_user_name($$CONNECTOR->dbh
        ,$data->{id_owner});

    delete $data->{screenshot};
    delete $data->{info};
    delete $data->{spice_password};

    if($data->{id_base}) {
        $data->{base} = Ravada::Request::_search_domain_name(undef
            ,delete $data->{id_base});
        $data->{parent_volumes} = $self->_list_parent_volumes();
    }
    if ($data->{is_base}) {
        $data->{base_volumes} = [$self->list_files_base(1)];
    }
}



sub backup($self) {
    my @files_data = $self->config_files();
    #read data extra just in case it wasn't already read
    $self->_data_extra('id_domain');
    for my $field ( keys %$self) {
        next if $field !~ /^_data/;
        my $filename = $self->_vm->dir_backup()."/".$self->name.$field.".json";
        CORE::open my $out,">",$filename or die "$! $filename";

        my %data = %{$self->{$field}};
        $self->_expand_backup_metadata(\%data) if $field eq '_data';

        print $out encode_json(\%data);
        close $filename;
        push @files_data,($filename);
    }
    push @files_data,($self->_backup_owner);

    push @files_data,($self->list_files_base()) if $self->is_base();

    my $now = Ravada::Utils::date_now();
    $now =~ tr/ :/_-/;
    my $file_backup = $self->_vm->dir_backup()."/".$self->name.".$now.tgz";
    my @cmd = ("tar","czvf",$file_backup,@files_data
    ,$self->list_volumes);
    $self->_vm->run_command(@cmd);

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO domain_backups (id_domain, file, date_created) "
        ." VALUES (?,?,?)"
    );
    $sth->execute($self->id, $file_backup, Ravada::Utils::date_now());
    return $file_backup;
}

sub _confirm_restore($self) {
    if ($ENV{TERM}) {
            print "Virtual Machine ".$self->name." already exists."
            ." All the data will be overwritten."
            ." Are you sure you want to restore a backup ?";
            my $answer = <STDIN>;
            return 0 unless $answer =~ /^y/i;
    }
    return 1;
}

sub _parse_file($file) {
    CORE::open my $f,"<",$file or confess "$! $file";
    my $json = join "",<$f>;
    close $f;

    return decode_json($json);
}

sub _search_domain_to_restore($data, $file_extra) {
    my $data_extra = _parse_file($file_extra);

    my $id = $data->{id};
    my $name = $data->{name};
    my $vm = Ravada::VM->open($data->{id_vm});

    my $sth = _dbh->prepare("SELECT * FROM domains "
        ."WHERE id=? OR name=?"
    );
    $sth->execute($id,$name);
    my $domain_old = $sth->fetchrow_hashref;
    if ($domain_old && $domain_old->{name} ne $name) {
        die "Domain id='$id' already exists, it is called "
            .$domain_old->{name};
    }
    if (!$domain_old) {
        my $domain = $vm->create_domain(
            name => $name
            ,config => $data_extra->{xml}
            ,id_owner => Ravada::Utils::user_daemon->id
            ,id => $id
        );
        $domain_old = $domain;
    } else {
        $domain_old = Ravada::Domain->open($domain_old->{id});
    }
}

sub _extract_metadata($file, $name) {
    my $dir = "/var/tmp";
    my @cmd = ("tar","tzvf",$file,"-C",$dir);
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    my ($file_data) = $out =~ m{^.*\d{4}-\d\d-\d\d [0-9:]+ (.*_data.json)$}m;
    @cmd = ("tar","xzvf",$file,"-C",$dir,$file_data);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    my $data = _parse_file("$dir/$file_data");
    unlink "$dir/$file_data";
    lock_hash(%$data);
    return $data;
}

sub _check_metadata_before_restore($data) {
    return if !exists $data->{base};
    unlock_hash(%$data);
    my $base = delete $data->{base};
    if ($base) {
        my $id = Ravada::Request::_search_domain_id(undef,$base);
        if (!$id) {
            die "Error: base $base not found.\n";
        }
        $data->{id_base} = $id;
    }
    lock_hash(%$data);
}

sub _check_parent_base_volumes($data, $file) {
    return if !$data->{id_base};

    if (!exists $data->{parent_volumes}
        || ! scalar(@{$data->{parent_volumes}})) {
            warn "Warning: this machine is clone but I can't see the parent volumes list ".Dumper($data);
            return;
    }
    my $vm = Ravada::VM->open(type => $data->{vm});
    my %fail = ();
    for my $vol (@{$data->{parent_volumes}}) {
        next if $vm->file_exists($vol);
        $fail{$vol}++;
    }
    die "Error: base files not found : ".join(" ",sort keys %fail)
    ."\n" if keys %fail;

    unlock_hash(%$data);
    delete $data->{parent_volumes};
    lock_hash(%$data);

}

sub restore_backup($self, $backup, $interactive, $rvd_back=undef) {
    my $file = $backup;
    $file = $backup->{file} if ref($backup);

    die "Error: missing file  '$file'" if ! -e $file;

    my ($name) = $file =~ m{.*/(.*?).\d{4}-\d\d-\d\d_\d\d-\d\d-};
    if (!$self) {
        $self = $rvd_back->search_domain($name);
    }
    die "Error: ".$self->name." is active, shut it down to restore.\n"
    if $self && $self->is_active;

    return if $self && $interactive && !$self->_confirm_restore();

    my $data = _extract_metadata($file,$name);
    _check_metadata_before_restore($data);
    _check_parent_base_volumes($data, $file) if $data->{id_base};

    my $vm = Ravada::VM->open(type => $data->{vm});

    my @cmd = ("tar","xzvf",$file,"-C","/");
    my ($out,$err) = $vm->run_command(@cmd);
    warn $err if $err;

    my ($file_data_extra) = $out =~ m{^(.*_data_domains.*.json)$}m;
    my ($file_data_owner) = $out =~ m{^(.*owner.json)$}m;

    $self = _search_domain_to_restore($data,"/$file_data_extra") if !$self;

    _restore_backup_metadata($self
        ,$data
        ,"/$file_data_owner"
    );

    return $self;
}

sub _restore_owner($self, $data, $file_data_owner) {
    my $id_owner = Ravada::Utils::search_user_id($$CONNECTOR->dbh
        ,delete $data->{owner});
    if ($id_owner) {
        $data->{id_owner} = $id_owner;
        return;
    }

    CORE::open my $f,"<",$file_data_owner or confess "$! $file_data_owner";
    my $json = join "",<$f>;
    close $f;

    my $data_owner = decode_json($json);

    my $id = $data_owner->{id};
    my $clashed_user = Ravada::Auth::SQL->search_by_id($id);

    if ($clashed_user) {
        die "Error: Owner id $id clashes with user ".$clashed_user->name
        ." here.";
    }

    my $sql = "INSERT INTO users (".join(",",sort keys %$data_owner).")"
    ." VALUES(".join(",",map {'?'} keys %$data_owner)." )";

    my $sth = $$CONNECTOR->dbh->prepare($sql);
    $sth->execute(map { $data_owner->{$_}} sort keys %$data_owner );
}

sub _restore_base_volumes_metadata($self, $data) {
    return if !exists $data->{base_volumes};

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO file_base_images "
        ." (id_domain , file_base_img, target )"
        ." VALUES(?,?,?)"
    );

    for my $vol ( @{$data->{base_volumes}}) {
        $sth->execute($self->id, $vol->[0], $vol->[1]);
    }
    unlock_hash(%$data);
    delete $data->{base_volumes};
    lock_hash(%$data);
}

sub _restore_backup_metadata($self, $data, $file_data_owner) {
    unlock_hash(%$data);
    delete $data->{id};
    delete $data->{internal_id};
    delete $data->{info};
    delete $data->{date_changed};

    _restore_owner($self,$data,$file_data_owner);
    _restore_base_volumes_metadata($self, $data);

    for my $field (keys %$data) {
        next if( !exists $self->{_data}->{$field} || !defined $self->{_data}->{$field})
        && !defined $data->{$field};

        next if exists $self->{_data}->{$field}
        && defined $self->{_data}->{$field}
        && defined $data->{$field}
        && $self->{_data}->{$field} eq $data->{$field};

        $self->_data($field => $data->{$field});
    }
    lock_hash(%$data);

}

sub remove_backup($self, $backup, $remove_file=0) {
    if ($remove_file) {
        my ($file) = $backup->{file};
        if ( $self->_vm->file_exists($file) ) {
            $self->_vm->remove_file($file);
        }
    }
    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM domain_backups WHERE id=?"
    );
    $sth->execute($backup->{id});
}

sub share($self, $user) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO domain_share "
        ."(id_domain, id_user)"
        ." VALUES(?,?)"
    );
    $sth->execute($self->id, $user->id);
}

sub remove_share($self, $user) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM domain_share "
        ." WHERE id_domain=? AND id_user=?"
    );
    $sth->execute($self->id, $user->id);
}


sub list_shares($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT u.name FROM users u,domain_share ds "
        ." WHERE u.id=ds.id_user "
        ."   AND ds.id_domain=?"
    );
    $sth->execute($self->id);
    my @shares;
    while (my ($name) = $sth->fetchrow) {
        push @shares,($name);
    }
    return @shares;
}

sub bundle($self) {
    my $sth = $self->_dbh->prepare("SELECT * FROM bundles "
        ." WHERE id IN (SELECT id_bundle FROM domains_bundle "
        ."              WHERE id_domain=?)"
    );
    $sth->execute($self->id);
    my $bundle = $sth->fetchrow_hashref;
    return if !keys %$bundle;
    lock_hash(%$bundle);
    return $bundle;

}

sub is_in_bundle($self) {
    my $id=( $self->id_base or $self->id);
    my $sth = $self->_dbh->prepare("SELECT id FROM bundles "
        ." WHERE id IN (SELECT id_bundle FROM domains_bundle "
        ."              WHERE id_domain=?)"
    );
    $sth->execute($id);
    my ($id_bundle) = $sth->fetchrow;
    return $id_bundle;

}

1;
