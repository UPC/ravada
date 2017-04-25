package Ravada::Domain;

use warnings;
use strict;

=head1 NAME

Ravada::Domain - Domains ( Virtual Machines ) library for Ravada

=cut

use Carp qw(carp confess croak cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use Image::Magick;
use JSON::XS;
use Moose::Role;
use Sys::Statistics::Linux;
use IPTables::ChainMgr;

use Ravada::Domain::Driver;
use Ravada::Utils;

our $TIMEOUT_SHUTDOWN = 20;
our $CONNECTOR;

our $MIN_FREE_MEMORY = 1024*1024;
our $IPTABLES_CHAIN = 'RAVADA';

_init_connector();

requires 'name';
requires 'remove';
requires 'display';

requires 'is_active';
requires 'is_hibernated';
requires 'is_paused';
requires 'start';
requires 'shutdown';
requires 'shutdown_now';
requires 'force_shutdown';
requires '_do_force_shutdown';

requires 'pause';
requires 'resume';
requires 'prepare_base';

requires 'rename';

#storage
requires 'add_volume';
requires 'list_volumes';

requires 'disk_device';

requires 'disk_size';

requires 'spinoff_volumes';

requires 'clean_swap_volumes';
#hardware info

requires 'get_info';
requires 'set_memory';
requires 'set_max_mem';

requires 'hybernate';

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
    is => 'ro',
    ,isa => 'Object'
    ,required => 0
);

has '_vm' => (
    is => 'ro',
    ,isa => 'Object'
    ,required => 1
);

##################################################################################3
#


##################################################################################3
#
# Method Modifiers
#

before 'display' => \&_allowed;

before 'remove' => \&_pre_remove_domain;
#\&_allow_remove;
 after 'remove' => \&_after_remove_domain;

before 'prepare_base' => \&_pre_prepare_base;
 after 'prepare_base' => \&_post_prepare_base;

before 'start' => \&_start_preconditions;
 after 'start' => \&_post_start;

before 'pause' => \&_allow_manage;
 after 'pause' => \&_post_pause;

before 'hybernate' => \&_allow_manage;
 after 'hybernate' => \&_post_pause;

before 'resume' => \&_allow_manage;
 after 'resume' => \&_post_resume;

before 'shutdown' => \&_pre_shutdown;
after 'shutdown' => \&_post_shutdown;
after 'shutdown_now' => \&_post_shutdown_now;

before 'force_shutdown' => \&_pre_shutdown_now;
after 'force_shutdown' => \&_post_shutdown_now;

before 'remove_base' => \&_can_remove_base;
after 'remove_base' => \&_post_remove_base;

before 'rename' => \&_pre_rename;
after 'rename' => \&_post_rename;

after 'screenshot' => \&_post_screenshot;
##################################################

sub _vm_connect {
    my $self = shift;
    $self->_vm->connect();
}

sub _vm_disconnect {
    my $self = shift;
    $self->_vm->disconnect();
}

sub _start_preconditions{
    my ($self) = @_;

    if (scalar @_ %2 ) {
        _allow_manage_args(@_);
    } else {
        _allow_manage(@_);
    }
    _check_free_memory();
    _check_used_memory(@_);

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

sub _allow_remove {
    my $self = shift;
    my ($user) = @_;

    $self->_allowed($user);
    $self->_check_has_clones() if $self->is_known();

}

sub _pre_prepare_base {
    my $self = shift;
    my ($user, $request) = @_;

    $self->_allowed($user);

    # TODO: if disk is not base and disks have not been modified, do not generate them
    # again, just re-attach them 
    $self->_check_disk_modified() if $self->is_base();
    $self->_check_has_clones();

    $self->is_base(0);
    $self->_post_remove_base();
    if ($self->is_active) {
        $self->shutdown(user => $user);
        $self->{_was_active} = 1;
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
    if ($self->id_base ) {
        $self->spinoff_volumes();
    }
};

sub _post_prepare_base {
    my $self = shift;

    my ($user) = @_;

    $self->is_base(1);
    if ($self->{_was_active} ) {
        $self->start($user) if !$self->is_active;
    }
    delete $self->{_was_active};

    $self->_remove_id_base();
};


sub _check_has_clones {
    my $self = shift;
    return if !$self->is_known();

    my @clones = $self->clones;
    die "Domain ".$self->name." has ".scalar @clones." clones : ".Dumper(\@clones)
        if $#clones>=0;
}

sub _check_free_memory{
    my $lxs  = Sys::Statistics::Linux->new( memstats => 1 );
    my $stat = $lxs->get;
    die "ERROR: No free memory. Only ".int($stat->memstats->{realfree}/1024)
            ." MB out of ".int($MIN_FREE_MEMORY/1024)." MB required." 
        if ( $stat->memstats->{realfree} < $MIN_FREE_MEMORY );
}

sub _check_used_memory {
    my $self = shift;
    my $used_memory = 0;

    my $lxs  = Sys::Statistics::Linux->new( memstats => 1 );
    my $stat = $lxs->get;

    # We get mem total less the used for the system
    my $mem_total = $stat->{memstats}->{memtotal} - 1*1024*1024;

    for my $domain ( $self->_vm->list_domains ) {
        my $alive;
        eval { $alive = 1 if $domain->is_active && !$domain->is_paused };
        next if !$alive;

        my $info = $domain->get_info;
        $used_memory += $info->{memory};
    }

    confess "ERROR: Out of free memory. Using $used_memory RAM of $mem_total available" if $used_memory>= $mem_total;
}

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

    die "User ".$user->name." [".$user->id."] not allowed to access ".$self->domain
        ." owned by ".($id_owner or '<UNDEF>')."\n".Dumper($self)
            if (defined $id_owner && $id_owner != $user->id );

    confess $err if $err;

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

sub id {
    return $_[0]->_data('id');

}


##################################################################################

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    _init_connector();

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_domain_db( name => $self->name);

    confess "No DB info for domain ".$self->name    if !$self->{_data};
    confess "No field $field in domains"            if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub __open {
    my $self = shift;

    my %args = @_;

    my $id = $args{id} or confess "Missing required argument id";
    delete $args{id};

    my $row = $self->_select_domain_db ( );
    return $self->search_domain($row->{name});
#    confess $row;
}

=head2 is_known

Returns if the domain is known in Ravada.

=cut

sub is_known {
    my $self = shift;
    return $self->_select_domain_db(name => $self->name);
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

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM domains WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $self->{_data} = $row;
    return $row if $row->{id};
}

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

    my $query = "INSERT INTO domains "
            ."(" . join(",",sort keys %field )." )"
            ." VALUES (". join(",", map { '?' } keys %field )." ) "
    ;
    my $sth = $$CONNECTOR->dbh->prepare($query);
    eval { $sth->execute( map { $field{$_} } sort keys %field ) };
    if ($@) {
        #warn "$query\n".Dumper(\%field);
        die $@;
    }
    $sth->finish;

}

=head2 pre_remove

Code to run before removing the domain. It can be implemented in each domain.
It is not expected to run by itself, the remove function calls it before proceeding.

    $domain->pre_remove();  # This isn't likely to be necessary
    $domain->remove();      # Automatically calls the domain pre_remove method

=cut

sub pre_remove { }

sub _pre_remove_domain {
    my $self = shift;
    eval { $self->id };
    $self->pre_remove();
    $self->_allow_remove(@_);
    $self->pre_remove();
}

sub _after_remove_domain {
    my $self = shift;
    if ($self->is_base) {
        $self->_do_remove_base(@_);
        $self->_remove_files_base();
    }
    return if !$self->{_data};
    $self->_remove_base_db();
    $self->_remove_domain_db();
}

sub _remove_domain_db {
    my $self = shift;

    return if !$self->is_known();

    $self->_select_domain_db or return;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains "
        ." WHERE id=?");
    $sth->execute($self->id);
    $sth->finish;
}

sub _remove_files_base {
    my $self = shift;

    for my $file ( $self->list_files_base ) {
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

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM requests "
        ." WHERE id_domain=? AND status <> 'done'");
    $sth->execute($self->id);
    my ($id) = $sth->fetchrow;
    $sth->finish;

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

sub clones {
    my $self = shift;

    _init_connector();

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, name FROM domains "
            ." WHERE id_base = ?");
    $sth->execute($self->id);
    my @clones;
    while (my $row = $sth->fetchrow_hashref) {
        # TODO: open the domain, now it returns only the id
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

=head2 json
Returns the domain information as json
=cut

sub json {
    my $self = shift;

    my $id = $self->_data('id');
    my $data = $self->{_data};
    $data->{is_active} = $self->is_active;

    return encode_json($data);
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

    $in->Write("png24:$file_out");

    chmod 0755,$file_out or die "$! chmod 0755 $file_out";
}

=head2 remove_base
Makes the domain a regular, non-base virtual machine and removes the base files.
=cut

sub remove_base {
    my $self = shift;
    return $self->_do_remove_base();
}

sub _do_remove_base {
    my $self = shift;
    $self->is_base(0);
    for my $file ($self->list_files_base) {
        next if ! -e $file;
        unlink $file or die "$! unlinking $file";
    }
    $self->storage_refresh()    if $self->storage();
}

sub _can_remove_base {
    _allow_manage(@_);
    _check_has_clones(@_);
}

sub _post_remove_base {
    my $self = shift;
    $self->_remove_base_db(@_);
    $self->_post_remove_base_domain();
}

sub _pre_shutdown_domain {}

sub _post_remove_base_domain {}

sub _remove_base_db {
    my $self = shift;

    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM file_base_images "
        ." WHERE id_domain=?");

    $sth->execute($self->id);
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

    my $name = $args{name} or confess "ERROR: Missing domain cloned name";
    confess "ERROR: Missing request user" if !$args{user};

    my $uid = $args{user}->id;

    $self->prepare_base($args{user})  if !$self->is_base();

    my $id_base = $self->id;

    return $self->_vm->create_domain(
        name => $name
        ,id_base => $id_base
        ,id_owner => $uid
        ,vm => $self->vm
        ,_vm => $self->_vm
    );
}

sub _post_pause {
    my $self = shift;
    my $user = shift;

    $self->_remove_iptables(user => $user);
}

sub _pre_shutdown {
    my $self = shift;

    $self->_allow_manage_args(@_);

    $self->_pre_shutdown_domain();

    if ($self->is_paused) {
        my %args = @_;
        $self->resume(user => $args{user});
    }
}

sub _post_shutdown {
    my $self = shift;

    my %arg = @_;
    my $timeout = $arg{timeout};

    $self->_remove_temporary_machine(@_);
    $self->_remove_iptables(@_);
    $self->clean_swap_volumes(@_) if $self->id_base() && !$self->is_active;

    if (defined $timeout) {
        if ($timeout<2 && $self->is_active) {
            sleep $timeout;
            return $self->_do_force_shutdown() if $self->is_active;
        }

        my $req = Ravada::Request->force_shutdown_domain(
                 name => $self->name
                , uid => $arg{user}->id
                 , at => time+$timeout 
        );
    }
}

sub _pre_shutdown_now {
    my $self = shift;
    return if !$self->is_active;
}

sub _post_shutdown_now {
    my $self = shift;
    my $user = shift;

    $self->_post_shutdown(user => $user);
}

=head2 can_hybernate

Returns wether a domain supports hybernation

=cut

sub can_hybernate { 0 };

=head2 add_volume_swap

Adds a swap volume to the virtual machine

Arguments:

    size => $kb
    name => $name (optional)

=cut

sub add_volume_swap {
    my $self = shift;
    my %arg = @_;

    $arg{name} = $self->name if !$arg{name};
    $self->add_volume(%arg, swap => 1);
}

sub _remove_iptables {
    my $self = shift;

    my $args = {@_};

    confess "Missing user=>\$user" if !$args->{user};

    my $ipt_obj = _obj_iptables();

    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE iptables SET time_deleted=?"
        ." WHERE id=?"
    );
    for my $row ($self->_active_iptables($args->{user})) {
        my ($id, $iptables) = @$row;
        $ipt_obj->delete_ip_rule(@$iptables);
        $sth->execute(Ravada::Utils::now(), $id);
    }
}

sub _remove_temporary_machine {
    my $self = shift;

    my %args = @_;
    my $user;

    return if !$self->is_known();

    eval { $user = Ravada::Auth::SQL->search_by_id($self->id_owner) };
    return if !$user;

    if ($user->is_temporary) {
        $self->remove($user);
        my $req= $args{request};
        $req->status(
            "removing"
            ,"Removing domain ".$self->name." after shutdown"
            ." because user "
            .$user->name." is temporary")
                if $req;
    }
}

sub _post_resume {
    return _post_start(@_);
}

sub _post_start {
    my $self = shift;

    $self->_add_iptable(@_);
}

sub _add_iptable {
    my $self = shift;
    return if scalar @_ % 2;
    my %args = @_;

    my $remote_ip = $args{remote_ip} or return;

    my $user = $args{user};
    my $uid = $user->id;

    my $display = $self->display($user);
    my ($local_ip, $local_port) = $display =~ m{\w+://(.*):(\d+)};

    my $ipt_obj = _obj_iptables();
	# append rule at the end of the RAVADA chain in the filter table to
	# allow all traffic from $local_ip to $remote_ip via port $local_port
    #
    my @iptables_arg = ($remote_ip
                        ,$local_ip, 'filter', $IPTABLES_CHAIN, 'ACCEPT',
                        ,{'protocol' => 'tcp', 's_port' => 0, 'd_port' => $local_port});

	my ($rv, $out_ar, $errs_ar) = $ipt_obj->append_ip_rule(@iptables_arg);

    $self->_log_iptable(iptables => \@iptables_arg, @_);

    @iptables_arg = ( '0.0.0.0'
                        ,$local_ip, 'filter', $IPTABLES_CHAIN, 'DROP',
                        ,{'protocol' => 'tcp', 's_port' => 0, 'd_port' => $local_port});
    
    ($rv, $out_ar, $errs_ar) = $ipt_obj->append_ip_rule(@iptables_arg);
    
    $self->_log_iptable(iptables => \@iptables_arg, %args);

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
    my $user = Ravada::Auth::SQL->search_by_id($args{uid});
    $args{user} = $user;
    delete $args{uid};
    $self->_add_iptable(%args);
}

sub _obj_iptables {

	my %opts = (
    	'use_ipv6' => 0,         # can set to 1 to force ip6tables usage
	    'ipt_rules_file' => '',  # optional file path from
	                             # which to read iptables rules
	    'iptout'   => '/tmp/iptables.out',
	    'ipterr'   => '/tmp/iptables.err',
	    'debug'    => 0,
	    'verbose'  => 0,

	    ### advanced options
	    'ipt_alarm' => 5,  ### max seconds to wait for iptables execution.
	    'ipt_exec_style' => 'waitpid',  ### can be 'waitpid',
	                                    ### 'system', or 'popen'.
	    'ipt_exec_sleep' => 0, ### add in time delay between execution of
	                           ### iptables commands (default is 0).
	);

	my $ipt_obj = IPTables::ChainMgr->new(%opts)
    	or die "[*] Could not acquire IPTables::ChainMgr object";

	my $rv = 0;
	my $out_ar = [];
	my $errs_ar = [];

	#check_chain_exists
	($rv, $out_ar, $errs_ar) = $ipt_obj->chain_exists('filter', $IPTABLES_CHAIN);
    if (!$rv) {
		$ipt_obj->create_chain('filter', $IPTABLES_CHAIN);
        $ipt_obj->add_jump_rule('filter','INPUT', 1, $IPTABLES_CHAIN);
	}
	# set the policy on the FORWARD table to DROP
#    $ipt_obj->set_chain_policy('filter', 'FORWARD', 'DROP');

    return $ipt_obj;
}

sub _log_iptable {
    my $self = shift;
    if (scalar(@_) %2 ) {
        carp "Odd number ".Dumper(\@_);
        return;
    }
    my %args = @_;
    my $remote_ip = $args{remote_ip};#~ or return;

    my $user = $args{user};
    my $uid = $args{uid};
    confess "Chyoose wehter uid or user "
        if $user && $uid;
    lock_hash(%args);

    $uid = $args{user}->id if !$uid;

    my $iptables = $args{iptables};

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO iptables "
        ."(id_domain, id_user, remote_ip, time_req, iptables)"
        ."VALUES(?, ?, ?, ?, ?)"
    );
    $sth->execute($self->id, $uid, $remote_ip, Ravada::Utils::now()
        ,encode_json($iptables));
    $sth->finish;

}

sub _active_iptables {
    my $self = shift;
    my $user = shift;

    confess "Missing \$user" if !$user;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,iptables FROM iptables "
        ." WHERE "
        ."    id_domain=?"
        ."    AND id_user=? "
        ."    AND time_deleted IS NULL"
        ." ORDER BY time_req DESC "
    );
    $sth->execute($self->id, $user->id);
    my @iptables;
    while (my ($id, $iptables) = $sth->fetchrow) {
        push @iptables, [ $id, decode_json($iptables)];
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

    my $sth = $$CONNECTOR->dbh->prepare("UPDATE domains set name=?"
                ." WHERE id=?");
    $sth->execute($new_name, $self->id);
    $sth->finish;
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
    }
    return $self->_data('is_public');
}

=head2 clean_swap_volumes

Check if the domain has swap volumes defined, and clean them

    $domain->clean_swap_volumes();

=cut

sub clean_swap_volumes {
    my $self = shift;
    for my $file ( $self->list_volumes) {
        $self->clean_disk($file)
            if $file =~ /\.SWAP\.\w+$/;
    }
}


sub _pre_rename {
    my $self = shift;

    my %args = @_;
    my $name = $args{name};
    my $user = $args{user};

    $self->_check_duplicate_domain_name(@_);

    $self->shutdown(user => $user)  if $self->is_active;
}

sub _post_rename {
    my $self = shift;
    my %args = @_;

    $self->_rename_domain_db(@_);
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

=head2 drivers

List the drivers available for a domain. It may filter for a given type.

    my @drivers = $domain->drivers();
    my @video_drivers = $domain->drivers('video');

=cut

sub drivers {
    my $self = shift;
    my $name = shift;
    my $type = (shift or $self->_vm->type);

    _init_connector();

    $type = 'qemu' if $type =~ /^KVM$/;
    my $query = "SELECT id from domain_drivers_types "
        ." WHERE vm=?";
    $query .= " AND name=?" if $name;

    my $sth = $$CONNECTOR->dbh->prepare($query);

    my @sql_args = ($type);
    push @sql_args,($name)  if $name;

    $sth->execute(@sql_args);

    my @drivers;
    while ( my ($id) = $sth->fetchrow) {
        push @drivers,Ravada::Domain::Driver->new(id => $id, domain => $self);
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

sub remote_ip {
    my $self = shift;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT remote_ip FROM iptables "
        ." WHERE "
        ."    id_domain=?"
        ."    AND time_deleted IS NULL"
        ." ORDER BY time_req DESC "
    );
    $sth->execute($self->id);
    my ($remote_ip) = $sth->fetchrow();
    $sth->finish;
    return ($remote_ip or undef);

}

sub _dbh {
    my $self = shift;
    _init_connector() if !$CONNECTOR || !$$CONNECTOR;
    return $$CONNECTOR->dbh;
}

1;
