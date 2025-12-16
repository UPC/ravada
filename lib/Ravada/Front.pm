package Ravada::Front;

use strict;
use warnings;

=head1 NAME

Ravada::Front - Web Frontend library for Ravada

=cut

use Carp qw(carp);
use DateTime;
use DateTime::Format::DateParse;
use Hash::Util qw(unlock_keys lock_hash lock_keys);
use IPC::Run3 qw(run3);
use JSON::XS;
use Moose;
use Storable qw(dclone);
use Ravada;
use Ravada::Auth::LDAP;
use Ravada::Front::Domain;
use Ravada::Front::Domain::KVM;
use Ravada::Route;

use feature qw(signatures);
no warnings "experimental::signatures";

use Data::Dumper;

has 'config' => (
    is => 'ro'
    ,isa => 'Str'
);
has 'connector' => (
        is => 'rw'
);
has 'backend' => (
    is => 'ro',
    isa => 'Ravada'

);

has 'fork' => (
    is => 'rw'
    ,isa => 'Int'
    ,default => 1
);

our $CONNECTOR;# = \$Ravada::CONNECTOR;
our $TIMEOUT = 20;
our @VM_TYPES = ('KVM');

our %VM;
our %VM_ID;
our $PID_FILE_BACKEND = '/var/run/rvd_back.pid';

our $LOCAL_TZ = DateTime::TimeZone->new(name => 'local');
###########################################################################
#
# method modifiers
#

around 'list_machines' => \&_around_list_machines;

=head2 BUILD

Internal constructor

=cut

sub BUILD {
    my $self = shift;
    if ($self->connector) {
        $CONNECTOR = $self->connector;
    } else {
        Ravada::_init_config($self->config()) if $self->config;
        $CONNECTOR = Ravada::_connect_dbh();
    }
    Ravada::_init_config($self->config()) if $self->config;
    Ravada::Auth::init($Ravada::CONFIG);
    $CONNECTOR->dbh();
    @VM_TYPES = @{$Ravada::CONFIG->{vm}};
}

=head2 list_bases

Returns a list of the base domains as a listref

    my $bases = $rvd_front->list_bases();

=cut

sub list_bases($self, %args) {
    $args{is_base} = 1;
    my $query = "SELECT name, id, is_base, id_owner FROM domains "
        ._where(%args)
        ." ORDER BY name";

    my $sth = $CONNECTOR->dbh->prepare($query);
    $sth->execute(map { $args{$_} } sort keys %args);

    my @bases = ();
    while ( my $row = $sth->fetchrow_hashref) {
        my $domain;
        eval { $domain   = $self->search_domain($row->{name}) };
        next if !$domain;
        $row->{has_clones} = $domain->has_clones;
        $row->{is_locked} = 0 if !exists $row->{is_locked};
        delete $row->{spice_password};
        push @bases, ($row);
    }
    $sth->finish;

    return \@bases;
}

=head2 list_machines_user

Returns a list of machines available to the user

If the user has ever clone the base, it shows this information. It show the
base data if not.

Arguments: user

Returns: listref of machines

=cut

sub list_machines_user($self, $user, $access_data={}) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,name,alias,is_public, description, screenshot, id_owner, is_base, date_changed, show_clones"
        ." FROM domains "
        ." WHERE ( is_base=1 OR ( id_base IS NULL AND id_owner=?))"
        ." ORDER BY alias"
    );
    my ($id, $name, $alias, $is_public, $description, $screenshot, $id_owner, $is_base, $date_changed, $show_clones);
    $sth->execute($user->id);
    $sth->bind_columns(\($id, $name, $alias, $is_public, $description, $screenshot, $id_owner, $is_base, $date_changed,$show_clones));

    my $bookings_enabled = $self->setting('/backend/bookings');
    my @list;

    while ( $sth->fetch ) {

        # check if enabled settings and this user not allowed
        next if $bookings_enabled && !Ravada::Front::Domain->open($id)->allowed_booking($user);

        my @clones = $self->search_clone(
            id_owner =>$user->id
            ,id_base => $id
        );
        push @clones,$self->_search_shared($id, $user->id);

        my ($clone) = ($clones[0] or undef);

        next unless
        $clone && $show_clones && $user->allowed_access_group($id)
        || $user->is_admin
        || ($is_public && $user->allowed_access($id))
        || ($id_owner == $user->id);

        $name = $alias if defined $alias;
        my $base = { id => $id, name => Encode::decode_utf8($name)
            , alias => Encode::decode_utf8($alias or $name)
            , is_public => ($is_public or 0)
            , screenshot => ($screenshot or '')
            , description => ($description or '')
            , id_clone => undef
            , name_clone => undef
            , is_base => $is_base
            , can_prepare_base => 0
        };


        next unless $self->_access_allowed($id, $base->{id_clone}, $access_data) || ($id_owner == $user->id);

        _copy_clone_info($user, $base, \@clones);

        if (!$is_base) {
            $base = _get_clone_info($user, $base);
            $base->{is_public} = 0;
            $base->{is_base} = 0;
            $base->{list_clones} = [];
            $base->{can_prepare_base} = 1 if $user->can_create_base();
        }
        lock_hash(%$base);

        push @list,($base);
    }
    $sth->finish;
    return \@list;
}

sub _copy_clone_info($user, $base, $clones) {

    my @list;
    for my $clone (@$clones) {
        my $c = _get_clone_info($user, $base, $clone);
        push @list,($c);

    }
    $base->{list_clones} = \@list;
}

sub _get_clone_info($user, $base, $clone = Ravada::Front::Domain->open($base->{id})) {

    my $c = {id => $clone->id
                        ,name => $clone->name
                        ,alias => $clone->alias
                        ,is_active => $clone->is_active
                        ,screenshot => $clone->_data('screenshot')
                        ,date_changed => $clone->_data('date_changed')
        };

    $c->{can_hibernate} = ($clone->is_active && !$clone->is_volatile);
    $c->{can_shutdown} = $clone->is_active;
    $c->{is_locked} = $clone->is_locked;
    $c->{description} = ( $clone->_data('description')
            or $base->{description});

    $c->{can_remove} = ( $user->can_remove() && $user->id == $clone->_data('id_owner'));
    $c->{can_remove} = 0 if !$c->{can_remove};

    if ($clone->is_active && !$clone->is_locked
        && $user->can_screenshot) {
        my $req = Ravada::Request->screenshot(
            id_domain => $clone->id
        );
    }
    return $c;
}

sub _access_allowed($self, $id_base, $id_clone, $access_data) {
    if ($id_clone) {
        my $clone = Ravada::Front::Domain->open($id_clone);
        my $allowed = $clone->access_allowed(%$access_data);
        return $allowed if $allowed;
    }
    my $base = Ravada::Front::Domain->open($id_base);

    my $allowed = $base->access_allowed(%$access_data);
    return 1 if !defined $allowed;
    return $allowed;

}

sub list_machines($self, $user, @filter) {
    return $self->list_domains(@filter) if $user->can_list_machines();

    my @list = ();
    push @list,(@{filter_base_without_clones($self->list_domains(@filter))}) if $user->can_list_clones();
    push @list,(@{$self->_list_own_clones($user)}) if $user->can_list_clones_from_own_base();
    push @list,(@{$self->_list_own_machines($user)}) if $user->can_list_own_machines();

    return [@list] if scalar @list < 2;

    my %uniq = map { $_->{name} => $_ } @list;
    return [sort { $a->{name} cmp $b->{name} } values %uniq];
}

sub _init_available_actions($user, $m) {
  eval { $m->{can_shutdown} = $user->can_shutdown($m->{id}) };

        $m->{can_start} = 0;
        $m->{can_start} = 1 if $m->{id_owner} == $user->id || $user->is_admin
        || $user->_machine_shared($m->{id})
        ;

        $m->{can_reboot} = $m->{can_shutdown} && $m->{can_start};

        $m->{can_view} = 0;
        $m->{can_view} = 1 if $m->{id_owner} == $user->id || $user->is_admin
        || $user->_machine_shared($m->{id})
        ;

        $m->{can_manage} = ( $user->can_manage_machine($m->{id}) or 0);
        eval {
        $m->{can_change_settings} = ( $user->can_change_settings($m->{id}) or 0);
        };
        #may have been deleted just now
        next if $@ && $@ =~ /Unknown domain/;
        die $@ if $@;

        $m->{can_hibernate} = 0;
        $m->{can_hibernate} = 1 if $user->can_shutdown($m->{id})
        && !$m->{is_volatile};
        warn $@ if $@;
}

sub _around_list_machines($orig, $self, $user, @filter) {
    my $machines = $self->$orig($user, @filter);
    for my $m (@$machines) {
        _init_available_actions($user, $m);
        $m->{id_base} = undef if !exists $m->{id_base};
        lock_hash(%$m);
    }
    return $machines;
}

=pod

sub search_clone_data {
    my $self = shift;
    my %args = @_;
    my $query = "SELECT * FROM domains WHERE "
        .(join(" AND ", map { "$_ = ? " } sort keys %args));

    my $sth = $CONNECTOR->dbh->prepare($query);
    $sth->execute( map { $args{$_} } sort keys %args );
    my $row = $sth->fetchrow_hashref;
    return ( $row or {});

}

=cut

=head2 list_domains

Returns a list of the domains as a listref

    my $bases = $rvd_front->list_domains();

=cut

sub list_domains($self, %args) {

    my $query = "SELECT d.name,d.alias, d.id, id_base, is_base, id_vm, status, is_public "
        ."      ,vms.name as node , is_volatile, client_status, id_owner "
        ."      ,comment, is_pool, show_clones"
        ."      ,d.has_clones, d.is_locked"
        ."      ,d.client_status, d.date_status_change, d.autostart "
        ."      ,d.date_changed"
        ." FROM domains d LEFT JOIN vms "
        ."  ON d.id_vm = vms.id ";

    my ($where, $values) = $self->_create_where(\%args);

    my $sth = $CONNECTOR->dbh->prepare("$query $where ORDER BY d.id");
    $sth->execute(@$values);

    my @domains = ();
    while ( my $row = $sth->fetchrow_hashref) {
        for (qw(is_hibernated is_paused)) {
            $row->{$_} = 0;
        }
        $row->{remote_ip} = undef;

        $row->{name}=Encode::decode_utf8($row->{alias})
        if defined $row->{alias} && length($row->{alias});

        $row->{is_active} = 0;
        $row->{remote_ip} = undef;
        {
            if ($row->{status} =~ /active|starting/) {
                $row->{is_active} = 1;
                $row->{is_hibernated} = 0;
                $row->{is_paused} = 0;
                $row->{remote_ip} = Ravada::Domain::remote_ip($row->{id});
            } else {
                $row->{is_active} = 0;
                $row->{is_hibernated} = 1 if $row->{status} eq 'hibernated';
                $row->{is_paused} = 1 if $row->{status} eq 'paused';
            }
            $row->{node} = $self->_node_name($row->{id_vm});
            if (defined $row->{client_status}) {
                ($row->{remote_ip}) = $row->{client_status} =~ /onnected.*?\((.*)\)/;
                $row->{remote_ip} = $row->{client_status} if ! $row->{remote_ip};
            }
            if (!$row->{status} ) {
                if ($row->{is_active}) {
                    $row->{status} = 'active';
                } elsif ($row->{is_hibernated}) {
                    $row->{status} = 'hibernated';
                } else {
                    $row->{status} = 'down';
                }
            }
            $row->{date_status_change} = Ravada::Domain::_date_status_change($row->{date_status_change});
        }
        delete $row->{spice_password};
        push @domains, ($row);
    }
    $sth->finish;

    return \@domains;
}

sub _create_where($self, $args) {
    my $where = '';
    my @values;

    my $date_changed = delete $args->{date_changed};
    for my $field ( sort keys %$args ) {
        $where .= " OR " if $where;
        if (!defined $args->{$field}) {
            $where .= " $field IS NULL ";
            next;
        }
        my $operation = "=";
        $operation = ">=" if $field eq 'date_changed';
        $operation = "like" if $field eq 'name';
        if (!ref($args->{$field})) {
            $where .= " d.$field $operation ?";
            if ($field eq 'name') {
                push @values,('%'.$args->{$field}.'%');
            } else {
                push @values,($args->{$field});
            }
        } else {
            my $option = '';
            for my $value ( @{$args->{$field}} ) {
                $option .= " OR " if $option;
                if (!defined $value) {
                    $option .= " d.$field IS NULL ";
                    next;
                }
                $option .= " d.$field=? ";
                push @values,($value);
            }
            $where .= " ($option) ";
        }
    }
    if ($date_changed) {
        $where = " ( $where ) AND " if $where ;
        $where .= " d.date_changed >= ? ";
        push @values, ($date_changed);
    }

    $where = "WHERE $where" if $where;

    return ($where,\@values);
}


sub _node_name($self, $id_vm) {
    return $self->{_node_name}->{$id_vm}
    if $self->{_node_name}->{$id_vm};

    my $sth = $self->_dbh->prepare("SELECT name FROM vms "
        ." WHERE id=?"
    );
    $sth->execute($id_vm);
    my ($name) = $sth->fetchrow;
    $self->{_node_name}->{$id_vm} = $name;

    return $name;
}

=head2 filter_base_without_clones

filters the list of domains and drops all machines that are unacessible and
bases with 0 machines accessible

=cut

sub filter_base_without_clones($domains) {
    my @list;
    my $size_domains = scalar(@$domains);
    for (my $i = 0; $i < $size_domains; ++$i) {
        if (@$domains[$i]->{is_base}) {
            for (my $j = 0; $j < $size_domains; ++$j) {
                if ($j != $i && !($domains->[$j]->{is_base})
                        && defined $domains->[$j]->{id_base}
                        && $domains->[$j]->{id_base} eq $domains->[$i]->{id}) {
                    push @list, ($domains->[$i]);
                    last;
                }
            }
        }
        else {
            push @list, (@$domains[$i]);
        }
    }
    return \@list;
}

sub _list_own_clones($self, $user) {
    my $machines = $self->list_bases( id_owner => $user->id );
    for my $base (@$machines) {
        confess "ERROR: BAse without id ".Dumper($base) if !$base->{id};
        push @$machines,@{$self->list_domains( id_base => $base->{id} )};
    }
    return $machines;
}

sub _list_own_machines($self, $user) {
    my $machines = $self->list_domains(id_owner => $user->id);
    for my $clone (@$machines) {
        next if !$clone->{id_base};
        push @$machines,@{$self->list_domains( id => $clone->{id_base} )};
    }
    return $machines;
}


sub _where(%args) {
    my $where = '';
    for my $field ( sort keys %args ) {
        $where .= " AND " if $where;
        $where .= " $field=?"
    }
    $where = "WHERE $where" if $where;
    return $where;
}

=head2 list_clones
  Returns a list of the domains that are clones as a listref

      my $clones = $rvd_front->list_clones();
=cut

sub list_clones {
  my $self = shift;
  my %args = @_;

  my $domains = $self->list_domains();
  my @clones;
  for (@$domains ) {
    if($_->{id_base}) { push @clones, ($_); }
  }
  return \@clones;
}
sub _remove_domain_db($self, $id) {
    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth->execute($id);
    $sth->finish;
}

=head2 domain_info

Returns information of a domain

    my $info = $rvd_front->domain_info( id => $id);
    my $info = $rvd_front->domain_info( name => $name);

=cut

sub domain_info {
    my $self = shift;

    my $domains = $self->list_domains(@_);
    return $domains->[0];
}

=head2 domain_exists

Returns true if the domain name exists

    if ($rvd->domain_exists('domain_name')) {
        ...
    }

=cut

sub domain_exists {
    my $self = shift;
    my $name = shift;

    my $sth = $self->_dbh->prepare(
        "SELECT id FROM domains "
        ." WHERE (name=? OR alias=?) "
        ."    AND ( is_volatile = 0 "
        ."          OR is_volatile=1 AND status = 'active' "
        ."         ) "
    );
    $sth->execute($name,$name);
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return 0 if !defined $id;
    return 1;
}

=head2 node_exists

Returns true if the node name exists

    if ($rvd->node('node_name')) {
        ...
    }

=cut

sub node_exists {
    my $self = shift;
    my $name = shift;

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id FROM vms"
        ." WHERE name=? "
    );
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return 0 if !defined $id;
    return 1;
}

=head2 list_vm_types

Returns a reference to a list of Virtual Machine Managers known by the system

=cut

sub list_vm_types {
    my $self = shift;

    return $self->{cache}->{vm_types} if $self->{cache}->{vm_types};

    my $result = [sort @VM_TYPES];

    $self->{cache}->{vm_types} = $result if $result->[0];

    return $result;
}

=head2 list_vms

Returns a list of Virtual Managers

=cut

sub list_vms($self, $type=undef) {

    my $sql = "SELECT id,name,hostname,is_active, vm_type, enabled FROM vms ";

    my @args = ();
    if ($type) {
        $sql .= "WHERE (vm_type=? or vm_type=?)";
        my $type2 = $type;
        $type2 = 'qemu' if $type eq 'KVM';
        @args = ( $type, $type2);
    }
    my $sth = $CONNECTOR->dbh->prepare($sql." ORDER BY vm_type,name");
    $sth->execute(@args);

    my @list;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{bases}= $self->_list_bases_vm($row->{id});
        $row->{machines}= $self->_list_machines_vm($row->{id});
        $row->{type} = $row->{vm_type};
        $row->{action_remove} = 'disabled' if length defined $row->{machines}[0];
        $row->{action_remove} = 'disabled' if $row->{hostname} eq 'localhost';
        $row->{action_remove} = 'disabled' if length defined $row->{bases}[0];
        $row->{is_local} = 0;
        $row->{is_local} = 1  if $row->{hostname} =~ /^(localhost|127)/;
        delete $row->{vm_type};
        lock_hash(%$row);
        push @list,($row);
    }
    $sth->finish;
    return @list;
}

=head2 list_nodes_by_id

Returns a list of Nodes by id

=cut

sub list_nodes_by_id($self, $type=undef) {

    my $sql = "SELECT id,name,hostname,is_active, vm_type, enabled FROM vms ";

    my @args = ();
    if ($type) {
        $sql .= "WHERE (vm_type=? or vm_type=?)";
        my $type2 = $type;
        $type2 = 'qemu' if $type eq 'KVM';
        @args = ( $type, $type2);
    }
    my $sth = $CONNECTOR->dbh->prepare($sql." ORDER BY vm_type,name");
    $sth->execute(@args);

    my %list;
    while (my $row = $sth->fetchrow_hashref) {
        $list{$row->{id}}= $row->{name};
    }
    $sth->finish;
    return \%list;
}


sub _list_bases_vm($self, $id_node) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT d.id FROM domains d,bases_vm bv"
        ." WHERE d.is_base=1"
        ."  AND d.id = bv.id_domain "
        ."  AND bv.id_vm=?"
        ."  AND bv.enabled=1"
    );
    my @bases;
    $sth->execute($id_node);
    while ( my ($id_domain) = $sth->fetchrow ) {
        push @bases,($id_domain);
    }
    $sth->finish;
    return \@bases;
}

sub _list_bases_vm_all($self, $id_node) {

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT d.id, d.name FROM domains d, vms v "
        ." WHERE is_base=? AND vm=v.vm_type"
        ."   AND d.vm =v.vm_type"
        ."   AND v.id=?"
        ." ORDER BY d.name "
    );
    $sth->execute(1, $id_node);
    my $sth_bv = $CONNECTOR->dbh->prepare(
        "SELECT bv.enabled FROM bases_vm bv, domains d "
        ." WHERE bv.id_domain=? AND bv.id_vm=?"
        ."   AND d.id = bv.id_domain "
    );
    my ($id_domain, $name_domain);
    $sth->bind_columns(\($id_domain, $name_domain));

    my $sth_clones = $CONNECTOR->dbh->prepare(
        "SELECT count(*) FROM domain_instances "
        ." WHERE id_vm=? AND id_domain IN (SELECT id FROM domains WHERE id_base=?) "
    );

    my @bases;
    while ( $sth->fetch ) {
        $sth_bv->execute($id_domain, $id_node);
        my ($enabled) = $sth_bv->fetchrow;

        $sth_clones->execute($id_node,$id_domain);
        my ($n_clones) = $sth_clones->fetchrow();

        push @bases,{
                  id => $id_domain
               ,name => $name_domain
             ,clones => $n_clones
            ,enabled => ( $enabled or 0)
        };
    }

    return \@bases;
}

sub _list_machines_vm($self, $id_node) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT d.id, name FROM domains d"
        ." WHERE d.status='active'"
        ."  AND d.id_vm=?"
    );
    my @bases;
    $sth->execute($id_node);
    while ( my ($id_domain, $name) = $sth->fetchrow ) {
        push @bases,({ id => $id_domain, name => $name });
    }
    $sth->finish;
    return \@bases;
}


=head2 list_iso_images

Returns a reference to a list of the ISO images known by the system

=cut

sub list_iso_images {
    my $self = shift;
    my $vm_name = shift;

    my $vm;

    my @iso;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM iso_images ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{options} = decode_json($row->{options})
            if $row->{options};
        $row->{min_ram} = 0.2 if !$row->{min_ram};

        lock_keys(%$row);
        _fix_iso_file_re($row);

        $row->{min_swap_size} = 0 if !$row->{min_swap_size};
        push @iso,($row);
    }
    $sth->finish;
    return \@iso;
}

sub _fix_iso_file_re($row) {
    if ($row->{rename_file}) {
        unlock_keys(%$row);
        $row->{file_re_orig} = $row->{file_re};
        lock_keys(%$row);
        $row->{file_re} = $row->{rename_file};
    } elsif ($row->{url} && !$row->{file_re} ) {
        my ($file_re) = $row->{url} =~ m{.*/([^/]+)$};
        $row->{file_re}= $file_re if $file_re;
    }

    if ($row->{file_re}) {
        $row->{file_re} = '^'.$row->{file_re} unless $row->{file_re} =~ /\^/;
        $row->{file_re} .= '$' unless $row->{file_re} =~ /\$/;
    }

}


=head2 iso_file

Returns a reference to a list of the ISOs known by the system

=cut

sub iso_file ($self, $id_vm, $uid) {

    my $key = "list_isos_$id_vm";
    my $cache = $self->_cache_get($key);
    return $cache if $cache;

    Ravada::Request->refresh_storage(
        id_vm=> $id_vm
	,uid => Ravada::Utils::user_daemon->id
    );

    my $req = Ravada::Request->list_isos(
        id_vm => $id_vm
        ,uid => $uid
    );
    return [] if !$req;
    $self->wait_request($req);
    return [] if $req->status ne 'done';

    my $isos = [];
    $isos = decode_json($req->output()) if $req->output;

    $self->_cache_store($key, $isos);

    return $isos;
}

=head2 list_lxc_templates

Returns a reference to a list of the LXC templates known by the system

=cut


sub list_lxc_templates {
    my $self = shift;

    my @template;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT * FROM lxc_templates ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @template,($row);
    }
    $sth->finish;
    return \@template;

}

=head2 list_users

Returns a reference to a list of the users

=cut

sub list_users($self,$name=undef) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT id, name FROM users ");
    $sth->execute();

    my @users = ();
    while ( my $row = $sth->fetchrow_hashref) {
        next if defined $name && $row->{name} !~ /$name/;
        push @users, ($row);
    }
    $sth->finish;

    return \@users;
}


=head2 list_bases_network

Returns a reference to a list to all the bases in a network

    my $list = $rvd_front->list_bases_network($id_network);

=cut

sub list_bases_network($self, $id_network) {
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM networks where name = 'default'");
    $sth->execute;
    my $default = $sth->fetchrow_hashref();
    $sth->finish;
    lock_hash(%$default);
    warn "Warning: all_domains and no_domains both true for default network ".Dumper($default)
    if $default->{all_domains} && $default->{no_domains};

    my $sth_nd = $CONNECTOR->dbh->prepare("SELECT id,allowed,anonymous FROM domains_network"
            ." WHERE id_domain=? AND id_network=? "
    );

    $sth = $CONNECTOR->dbh->prepare("SELECT * FROM domains where is_base=1 " 
        ." ORDER BY name");
    $sth->execute();
    my @bases;
    while (my $row = $sth->fetchrow_hashref) {

        $sth_nd->execute($row->{id}, $id_network);
        my ($id,$allowed, $anonymous) = $sth_nd->fetchrow;

        $row->{anonymous} = ( $anonymous or 0);

        if (defined $allowed) {
            $row->{allowed} = $allowed;
        } else {
            $row->{allowed} = $default->{all_domains};
            $row->{allowed} = 0 if $default->{no_domains};
        }

        lock_hash(%$row);
        push @bases,($row);
    }

    return \@bases;
}

=head2 create_domain

Request the creation of a new domain or virtual machine

    # TODO: document the args here
    my $req = $rvd_front->create_domain( ... );

=cut

sub create_domain {
    my $self = shift;
    return Ravada::Request->create_domain(@_);
}

=head2 wait_request

Waits for a request for some seconds.

=head3 Arguments

=over

=item * request

=item * timeout (optional defaults to $Ravada::Front::TIMEOUT

=back

Returns: the request

=cut

sub wait_request {
    my $self = shift;
    my $req = shift or confess "Missing request";

    my $timeout = ( shift or $TIMEOUT );

    if ( $self->backend ) {
        if ($self->fork ) {
            $self->backend->process_requests();
        } else {
            $self->backend->_process_requests_dont_fork();
        }
    }

    for ( 1 .. $timeout ) {
        last if $req->status eq 'done';
        sleep 1;
    }
    $req->status("timeout")
        if $req->status eq 'working';

    $req->refresh();
    return $req;

}

=head2 ping_backend

Checks if the backend is alive.

Return true if alive, false otherwise.

=cut

sub ping_backend {
    my $self = shift;

    my $req = Ravada::Request->ping_backend();
    $self->wait_request($req, 2);

    return 1 if $req->status() eq 'done';
    return 0;
}

sub _ping_backend_localhost {
    my $self = shift;
    return 1 if -e $PID_FILE_BACKEND;
    # TODO check the process with pid $PID_FILE_BACKEND is really alive
    return;
}

=head2 open_vm

Connects to a Virtual Machine Manager ( or VMM ( or VM )).
Returns a read-only connection to the VM.

  my $vm = $front->open_vm('KVM');

=cut

sub open_vm {
    my $self = shift;
    my $type = shift or confess "I need vm type";
    my $class = "Ravada::VM::$type";

    if (my $vm = $VM{$type}) {
        if (!$vm->ping || !$vm->is_alive) {
            $vm->disconnect();
            $vm->connect();
        } else {
            return $vm;
        }
    }

    my $proto = {};
    bless $proto,$class;

    my $vm = $proto->new(readonly => 1);
    eval { $vm->vm };
    warn $@ if $@;
    return if $@;
    return $vm if $0 =~ /\.t$/;

    $VM{$type} = $vm;
    return $vm;
}

=head2 search_vm

Calls to open_vm

=cut

sub search_vm {
    return open_vm(@_);
}

=head2 search_clone

Search for a clone of a domain owned by an user.

    my $domain_clone = $rvd_front->(id_base => $domain_base->id , id_owner => $user->id);

=head3 arguments

=over

=item id_base : The id of the base domain

=item id_user

=back

Returns the domain

=cut

sub search_clone($self, %args) {
    confess "Missing id_owner " if !$args{id_owner};
    confess "Missing id_base" if !$args{id_base};

    my ($id_base , $id_owner) = ($args{id_base} , $args{id_owner} );

    delete $args{id_base};
    delete $args{id_owner};

    confess "Unknown arguments ".Dumper(\%args) if keys %args;

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,name FROM domains "
        ." WHERE id_base=? AND id_owner=? AND (is_base=0 OR is_base=NULL)"
        ."   AND is_volatile=0 "
        ." ORDER BY name"
    );
    $sth->execute($id_base, $id_owner);

    my @clones;
    while ( my ($id_domain, $name) = $sth->fetchrow ) {
        push @clones,($self->search_domain($name));
    }
    $sth->finish;

    return $clones[0] if !wantarray;
    return @clones;

}

sub _search_shared($self, $id_base, $id_user) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT d.id, d.name FROM domains d, domain_share ds"
        ." WHERE id_base=? "
        ."   AND ds.id_user=? "
        ."   AND ds.id_domain=d.id "
    );
    $sth->execute($id_base, $id_user);

    my @clones;
    while ( my ($id_domain, $name) = $sth->fetchrow ) {
        push @clones,($self->search_domain($name));
    }
    $sth->finish;

    return @clones;

}

=head2 search_domain

Searches a domain by name

    my $domain = $rvd_front->search_domain($name);

Returns a Ravada::Domain object

=cut

sub search_domain {
    my $self = shift;

    my $name = shift;

    my $sth = $CONNECTOR->dbh->prepare("SELECT id, vm FROM domains WHERE name=? OR alias=?");
    $sth->execute($name, $name);
    my ($id, $tipo) = $sth->fetchrow or return;

    return Ravada::Front::Domain->open($id);
}

=head2 list_requests

Returns a list of requests : ( id , domain_name, status, error )

=cut

sub list_requests($self, $id_domain_req=undef, $seconds=60) {

    my @now = localtime(time-$seconds);
    $now[4]++;
    for (0 .. 4) {
        $now[$_] = "0".$now[$_] if length($now[$_])<2;
    }
    my $time_recent = ($now[5]+=1900)."-".$now[4]."-".$now[3]
        ." ".$now[2].":".$now[1].":".$now[0];
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT requests.id, command, args, requests.date_changed, requests.status"
            ." ,requests.error, id_domain ,domains.name as domain"
            ." ,domains.alias as domain_alias"
            ." ,requests.output "
        ." FROM requests left join domains "
        ."  ON requests.id_domain = domains.id"
        ." WHERE "
        ."    requests.status <> 'done' "
        ."  OR ( requests.date_changed >= ?) "
        ." ORDER BY requests.date_changed "
    );
    $sth->execute($time_recent);
    my @reqs;
    my ($id_request, $command, $j_args, $date_changed, $status
        , $error, $id_domain, $domain, $alias, $output);
    $sth->bind_columns(\($id_request, $command, $j_args, $date_changed, $status
        , $error, $id_domain, $domain, $alias, $output));

    while ( $sth->fetch) {
        my $epoch_date_changed = time;
        if ($date_changed) {
            my ($y,$m,$d,$hh,$mm,$ss) = $date_changed =~ /(\d{4})-(\d\d)-(\d\d) (\d+):(\d+):(\d+)/;
            if ($y)  {
                $epoch_date_changed = DateTime->new(year => $y, month => $m, day => $d
                    ,hour => $hh, minute => $mm, second => $ss
                    ,time_zone => $LOCAL_TZ
                )->epoch;
            }
        }
        next if $command eq 'enforce_limits'
                || $command eq 'refresh_storage'
                || $command eq 'refresh_machine'
                || $command eq 'ping_backend'
                || $command eq 'cleanup'
                || $command eq 'screenshot'
                || $command eq 'connect_node'
                || $command eq 'post_login'
                || $command eq 'list_network_interfaces'
                || $command eq 'list_isos'
                || $command eq 'manage_pools'
                || $command eq 'list_storage_pools'
                || $command eq 'list_cpu_models'
                || $command eq 'list_networks'
                ;
        next if ( $command eq 'force_shutdown'
                || $command eq 'force_reboot'
                || $command eq 'start'
                || $command eq 'shutdown'
                || $command eq 'reboot'
                || $command eq 'hibernate'
                )
                && time - $epoch_date_changed > 5
                && $status eq 'done'
                && !$error;
        next if $id_domain_req && defined $id_domain && $id_domain != $id_domain_req;
        my $args;
        $args = decode_json($j_args) if $j_args;

        $domain = Encode::decode_utf8($alias) if defined $alias;
        if (!$domain && $args->{id_domain}) {
            $domain = $args->{id_domain};
        }
        $domain = $args->{name} if !$domain && $args->{name};

        my $message = ( $self->_last_message($id_request) or $error or '');
        $message =~ s/^$command\s+$status(.*)/$1/i;

        push @reqs,{ id => $id_request,  command => $command, date_changed => $date_changed, status => $status, name => $args->{name}
            ,domain => $domain
            ,date => $date_changed
            ,message => Encode::decode_utf8($message)
            ,error => Encode::decode_utf8($error)
            ,output => Encode::decode_utf8($output)
        };
    }
    $sth->finish;
    return \@reqs;
}

sub _last_message {
    my $self = shift;
    my $id_request = shift;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT subject , message FROM messages WHERE id_request=? ORDER BY date_send DESC,id DESC");
    $sth->execute($id_request);
    my ($subject, $message) = $sth->fetchrow;

    return '' if !$subject;

    $subject = '' if $message && $message =~ /^$subject/;
    return "$subject ".($message or '');
    $sth->finish;

}

=head2 search_domain_by_id

  my $domain = $ravada->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    my $sth = $CONNECTOR->dbh->prepare("SELECT name, id, id_base, is_base FROM domains WHERE id=?");
    $sth->execute($id);

    my $row = $sth->fetchrow_hashref;

    return if !keys %$row;

    lock_hash(%$row);

    return $self->search_domain($row->{name});
}

=head2 start_domain

Request to start a domain.

=head3 arguments

=over

=item user => $user : a Ravada::Auth::SQL user

=item name => $name : the domain name

=item remote_ip => $remote_ip: a Ravada::Auth::SQL user

=back

Returns an object: Ravada::Request.

    my $req = $rvd_front->start_domain(
               user => $user
              ,name => 'mydomain'
        , remote_ip => '192.168.1.1');

=cut

sub start_domain {
    my $self = shift;
    confess "ERROR: Must call start_domain with user=>\$user, name => \$name, remote_ip => \$ip"
        if scalar @_ % 2;

    my %args = @_;

    # TODO check for user argument
    $args{uid} = $args{user}->id    if $args{user};
    delete $args{user};

    return Ravada::Request->start_domain( %args );
}

=head2 list_bases_anonymous

List the available bases for anonymous user in a remote IP

    my $list = $rvd_front->list_bases_anonymous($remote_ip);

=cut

sub list_bases_anonymous {
    my $self = shift;
    my $ip = shift or confess "Missing remote IP";

    my $net = Ravada::Route->new(address => $ip);

    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id, alias, name, id_base, is_public, file_screenshot "
        ."FROM domains where is_base=1 "
        ."AND is_public=1");
    $sth->execute();
    my ($id, $alias, $name, $id_base, $is_public, $screenshot);
    $sth->bind_columns(\($id, $alias, $name, $id_base, $is_public, $screenshot));

    my @bases;
    while ( $sth->fetch) {
        next if !$net->allowed_anonymous($id);
        my %base = ( id => $id, name => Encode::decode_utf8($name)
            , alias => Encode::decode_utf8($alias or $name)
            , is_public => ($is_public or 0)
            , screenshot => ($screenshot or '')
            , is_active => 0
            , id_clone => undef
            , name_clone => undef
            , is_locked => undef
            , can_hibernate => 0

        );
        $base{list_clones} = [];
        lock_hash(%base);
        push @bases, (\%base);
    }
    $sth->finish;

    return \@bases;

}

=head2 disconnect_vm

Disconnects all the conneted VMs

=cut

sub disconnect_vm {
    %VM = ();
}

=head2 enable_node

Enables, disables or delete a node

    $rvd->enable_node($id_node, $value);

Returns true if the node is enabled, false otherwise.

=cut

sub enable_node($self, $id_node, $value) {
    my $sth = $CONNECTOR->dbh->prepare("UPDATE vms SET enabled=? WHERE id=?");
    $sth->execute($value, $id_node);
    $sth->finish;

    return $value;
}

=head2 remove_node

Remove new node from the table VMs

=cut

sub remove_node($self, $id_node, $value) {
    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM vms WHERE id=?");
    $sth->execute($id_node);
    $sth->finish;

    return $value;
}

=head2 add_node

Inserts a new node in the table VMs

=cut

sub add_node($self,%arg) {
    my $sql = "INSERT INTO vms "
        ."("
        .join(",",sort keys %arg)
        .")"
        ." VALUES ( ".join(",", map { '?' } keys %arg).")";

    my $sth = $CONNECTOR->dbh->prepare($sql);
    $sth->execute(map { $arg{$_} } sort keys %arg );
    $sth->finish;

    my $req = Ravada::Request->refresh_vms( _force => 1 );
    return $req->id;
}

sub _cache_delete($self, $key) {
    delete $self->{cache}->{$key};
}

sub _cache_store($self, $key, $value, $timeout=60) {
    $self->{cache}->{$key} = [ $value, time+$timeout ];
}

sub _cache_clean($self) {
    delete $self->{cache};
}

sub _cache_get($self, $key) {

    delete $self->{cache}->{$key}
        if exists $self->{cache}->{$key}
            && $self->{cache}->{$key}->[1] < time;

    return if !exists $self->{cache}->{$key};

    return $self->{cache}->{$key}->[0];

}

=head2 list_network_interfaces

Request to list the network interfaces. Returns a reference to the list.

    my $interfaces = $rvd_front->list_network_interfaces(
        vm_type => 'KVM'
        ,type => 'bridge'
        ,user => $user
    )

=cut

sub list_network_interfaces($self, %args) {

    my $vm_type = delete $args{vm_type}or confess "Error: missing vm_type";
    my $type = delete $args{type} or confess "Error: missing type";
    my $user = delete $args{user} or confess "Error: missing user";
    my $timeout = delete $args{timeout};
    $timeout = 60 if !defined $timeout;

    confess "Error: Unknown args ".Dumper(\%args) if keys %args;

    my $cache_key = "_interfaces_$type";
    return $self->{$cache_key} if exists $self->{$cache_key};

    my $req = Ravada::Request->list_network_interfaces(
        vm_type => $vm_type
          ,type => $type
           ,uid => $user->id
    );
    if  ( defined $timeout ) {
        $self->wait_request($req, $timeout);
    }
    return [] if $req->status ne 'done' || !length($req->output);

    my $interfaces = decode_json($req->output());
    $self->{$cache_key} = $interfaces;

    return $interfaces;
}

sub _dbh {
    $CONNECTOR = $Ravada::CONNECTOR if !defined $CONNECTOR;
    confess if !defined $CONNECTOR;
    return $CONNECTOR->dbh;
}

sub _get_settings($self, $id_parent=0) {
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT id,name,value"
        ." FROM settings "
        ." WHERE id_parent= ? "
    );
    $sth->execute($id_parent);
    my $ret;
    while ( my ( $id, $name, $value) = $sth->fetchrow) {
        $value = 0+$value if defined $value && $value =~ /^\d+$/;
        my $setting_sons = $self->_get_settings($id);
        if ($setting_sons) {
            $ret->{$name} = $setting_sons;
            $ret->{$name}->{id} = $id;
            $ret->{$name}->{value} = $value;
        } else {
            $ret->{$name} = { id => $id, value => $value};
        }
    }
    return $ret;
}

=head2 settings_global

Returns the list of global settings as a hash

=cut

sub settings_global($self) {
    return $self->_get_settings();
}

=head2 setting

Sets or gets a global setting parameter

    $rvd_front->('debug')

Settings are defined and stored in the table settings in the database.

=cut

sub setting($self, $name, $new_value=undef) {

    confess "Error: wrong new value '$new_value' for $name"
    if ref($new_value);

    Ravada::Front->_check_features($name, $new_value);

    my $sth = _dbh->prepare(
        "SELECT id,value "
        ." FROM settings "
        ." WHERE id_parent=? AND name=?"
    );
    my ($id, $value);
    my $id_parent = 0;
    for my $item (split m{/},$name) {
        next if !$item;
        $sth->execute($id_parent, $item);
        ($id, $value) = $sth->fetchrow;
        confess "Error: I can't find setting $item inside id_parent: $id_parent"
        if !$id;

        $id_parent = $id;
    }

    if (defined $new_value && $new_value ne $value) {
        my $sth_update = _dbh->prepare(
            "UPDATE settings set value=? WHERE id=? "
        );
        $sth_update->execute($new_value,$id);
        return $new_value;
    }
    return $value;
}

sub _setting_data($self, $name) {

    my $sth = _dbh->prepare(
        "SELECT * "
        ." FROM settings "
        ." WHERE id_parent=? AND name=?"
    );
    my $row;
    my $id_parent = 0;
    for my $item (split m{/},$name) {
        next if !$item;
        $sth->execute($id_parent, $item);
        $row = $sth->fetchrow_hashref;
        confess "Error: I can't find setting $item inside id_parent: $id_parent"
        if !defined $row->{id};

        $id_parent = $row->{id};
    }
    return $row;
}

sub _check_features($self, $name, $new_value) {
    confess "Error: LDAP required for bookings."
    if $name eq '/backend/bookings' && $new_value && !$self->feature('ldap');

}

sub _settings_by_id($self) {
    my $orig_settings;
    my $sth = $self->_dbh->prepare("SELECT id,value FROM settings");
    $sth->execute();
    while (my ($id, $value) = $sth->fetchrow) {
        $orig_settings->{$id} = $value;
    }
    return $orig_settings;
}

sub _settings_by_parent($self,$parent) {
    my $data = $self->_setting_data($parent);
    my $sth = $self->_dbh->prepare("SELECT name,value FROM settings "
        ." WHERE id_parent = ? ");
    $sth->execute($data->{id});
    my $ret;
    while (my ($name, $value) = $sth->fetchrow) {
        $value = '' if !defined $value;
        $ret->{$name} = $value;
    }
    return $ret;
}

=head2 feature

Returns if a feature is available

  if ($rvd_front->$feature('ldap')) {
     ....

=cut

sub feature($self,$name=undef) {
    if (!defined $name) {
        my $feature;
        for my $cur_name ('ldap') {
            $feature->{$cur_name} = $self->feature($cur_name);
        }
        return $feature;
    }
    return 1 if exists $Ravada::CONFIG->{$name} && $Ravada::CONFIG->{$name};
    return 0;
}

=head2 update_settings_global

Updates the global settings

=cut

sub update_settings_global($self, $arg, $user, $reload, $orig_settings = $self->_settings_by_id) {
    confess if !ref($arg);
    if (exists $arg->{frontend}
        && exists $arg->{frontend}->{maintenance}
        && !$arg->{frontend}->{maintenance}->{value}) {
        delete $arg->{frontend}->{maintenance_end};
        delete $arg->{frontend}->{maintenance_start};
    }
    for my $field (sort keys %$arg) {
        next if $field =~ /^(id|value)$/;
        confess Dumper([$field,$arg->{$field}]) if !ref($arg->{$field});
        if ( scalar(keys %{$arg->{$field}})>2 ) {
            confess if !keys %{$arg->{$field}};
            my $field2 = dclone($arg->{$field});
            $self->update_settings_global($field2, $user, $reload, $orig_settings);
        }
        confess "Error: invalid field $field" if $field !~ /^\w[\w\-]+$/;
        my ( $value, $id )
                   = ($arg->{$field}->{value}
                    , $arg->{$field}->{id}
        );
        next if !defined $value || $orig_settings->{$id} eq $value;
        $$reload++ if $field eq 'bookings';
        my $sth = $self->_dbh->prepare(
            "UPDATE settings set value=?"
            ." WHERE id=? "
        );
        $sth->execute($value, $id);

        $user->send_message("Setting $field to $value");
    }
}

=head2 is_in_maintenance

Returns wether the service is in maintenance mode

=cut

sub is_in_maintenance($self) {
    my $settings = $self->settings_global();
    return 0 if ! $settings->{frontend}->{maintenance}->{value};

    my $start = DateTime::Format::DateParse->parse_datetime(
        $settings->{frontend}->{maintenance_start}->{value});
    my $end= DateTime::Format::DateParse->parse_datetime(
        $settings->{frontend}->{maintenance_end}->{value});
    my $now = DateTime->now();

    if ( $now >= $start && $now <= $end ) {
        return 1;
    }
    return 0 if $now <= $start;
    my $sth = $self->_dbh->prepare("UPDATE settings set value = 0 "
        ." WHERE id=? "
    );
    $sth->execute($settings->{frontend}->{maintenance}->{id});

    return 0;
}

=head2 update_host_device

Update the host device information, then it requests a list of the current available devices

    $rvd_front->update_host_device( field => 'value' );

=cut

sub update_host_device($self, $args) {
    my $id = delete $args->{id} or die "Error: missing id ".Dumper($args);
    Ravada::Utils::check_sql_valid_params(keys %$args);
    my $query = "UPDATE host_devices SET ".join(" , ", map { "$_=?" } sort keys %$args);
    $query .= " WHERE id=?";
    my $sth = $self->_dbh->prepare($query);
    my @values = map { $args->{$_} } sort keys %$args;
    $sth->execute(@values, $id);
    Ravada::Request->list_host_devices(
        uid => Ravada::Utils::user_daemon->id
        ,id_host_device => $id
        ,_force => 1
    );
    return 1;
}

=head2 list_machine_types

Returns a reference to a list of the architectures and its machine types

=cut

sub list_machine_types($self, $uid, $vm_type) {

    my $key="list_machine_types";
    my $cache = $self->_cache_get($key);
    return $cache if $cache;

    my $req = Ravada::Request->list_machine_types(
        vm_type => $vm_type
        ,uid => $uid
    );
    return {} if !$req;
    $self->wait_request($req);
    return {} if $req->status ne 'done';

    my $types = {};
    $types = decode_json($req->output()) if $req->output;

    $self->_cache_store($key,$types);

    return $types;
}

=head2 list_cpu_models

Returns a reference to a list of the CPU models

=cut

sub list_cpu_models($self, $uid, $id_domain) {

    my $key="list_cpu_models";
    my $dom = Ravada::Front::Domain->open($id_domain);
    $key.='#'.$dom->type;

    my $cache = $self->_cache_get($key);
    return $cache if $cache;

    my $req = Ravada::Request->list_cpu_models(
        id_domain => $id_domain
        ,uid => $uid
    );
    return {} if !$req;
    $self->wait_request($req);
    return {} if $req->status ne 'done';

    my $models= {};
    $models = decode_json($req->output()) if $req->output;

    $self->_cache_store($key,$models);

    return $models;
}

=head2 list_storage_pools

Returns a reference to a list of the storage pools

=cut

sub list_storage_pools($self, $uid, $id_vm, $active=undef) {

    my $key="list_storage_pools_$id_vm";

    my $req_active_sp;
    for my $command ( 'active_storage_pool','create_storage_pool') {
        $req_active_sp = Ravada::Request::done_recently(
            undef,60, $command
        );
        last if $req_active_sp;
    }
    my $cache = [];
    my $force = 0;
    if ($req_active_sp) {
        $force = 1;
    } else {
        $cache = ($self->_cache_get($key) or []);
    }

    my $req = Ravada::Request->list_storage_pools(
        id_vm => $id_vm
        ,uid => $uid
        ,data => 1
        ,_force => $force
    );
    return _filter_active($cache, $active) if !$req;

    $self->wait_request($req);
    return _filter_active($cache, $active) if $req->status ne 'done';

    my $pools = [];
    $pools = decode_json($req->output()) if $req->output;

    $self->_cache_store($key,$pools) if scalar(@$pools);

    return _filter_active($pools, $active);
}

=head2 list_networks

List the virtual networks for a Virtual Machine Manager

Arguments: id vm , id user

Returns: list ref of networks

=cut

sub list_networks($self, $id_vm ,$id_user) {
    my $query = "SELECT * FROM virtual_networks "
        ." WHERE id_vm=?";

    my $user = Ravada::Auth::SQL->search_by_id($id_user);
    my $owned = 0;
    unless ($user->is_admin || $user->can_manage_all_networks) {
        $query .= " AND ( id_owner=? or is_public=1) ";
        $owned = 1;
    }
    $query .= " ORDER BY name";
    my $sth = $CONNECTOR->dbh->prepare($query);
    if ($owned) {
        $sth->execute($id_vm, $id_user);
    } else {
        $sth->execute($id_vm);
    }
    my @networks;
    my %owner;
    while ( my $row = $sth->fetchrow_hashref ) {
        $self->_search_user($row->{id_owner},\%owner);
        $row->{_owner} = $owner{$row->{id_owner}};
        $row->{_can_change}=0;
        $row->{is_active}=0 if !defined $row->{is_active};

        $row->{_can_change}=1
        if $user->is_admin || $user->can_manage_all_networks
        || ($user->can_create_networks && $user->id == $row->{id_owner});

        push @networks,($row);
    }
    return \@networks;
}

sub _search_user($self,$id, $users) {
    return if $users->{$id};

    my $sth = $self->_dbh->prepare(
        "SELECT * FROM users WHERE id=?"
    );
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref();
    for my $field (keys %$row) {
        delete $row->{$field} if $field =~ /passw/;
    }
    $users->{$id}=$row;
}

sub _filter_active($pools, $active) {
    return $pools if !defined $active;

    my @pools2;
    for my $entry (@$pools) {
            next if $entry->{is_active} ne $active;
            push @pools2,($entry);
    }
    return \@pools2;

}

=head2 list_users_share

Returns a list of users to share

=cut

sub list_users_share($self, $name=undef,@skip) {
    my $users = $self->list_users();
    my @found = @$users;
    if ($name) {
        @found = grep { $_->{name} =~ /$name/ } @$users;
    }
    if (@skip) {
        my %skip = map { $_->id => 1} @skip;
        my @pre=@found;
        @found = ();
        for my $user (@pre) {
            next if $skip{$user->{id}};
            push @found,($user);
        }
    }
    return \@found;
}

=head2 upload_users

Upload a list of users to the database

=head3 Arguments

=over

=item * string with users and passwords in each line

=item * type: it can be SQL, LDAP or SSO

=item * create: optionally create the entries in LDAP

=back

=cut

sub upload_users($self, $users, $type, $create=0) {

    my @external;
    if ($type ne 'sql') {
        @external = ( is_external => 1, external_auth => $type );
    }

    my ($found,$count) = (0,0);
    my @error;
    for my $line (split /\n/,$users) {
        my ($name, $password) = split(/:/,$line);
        $found++;
        my $user = Ravada::Auth::SQL->new(name => $name);
        if ($user && $user->id) {
            push @error,("User $name already added");
            next;
        }
        if ($type ne 'sql' && $create) {
            if ($type eq 'ldap') {
                if (!$password) {
                    push @error,("Error: user $name , password empty");
                    next;
                }
                eval { $user = Ravada::Auth::LDAP::add_user($name,$password) };
                push @error, ($@) if $@;
            } else {
                push @error,("$type users can't be created from Ravada");
            }
        }
        if ($type eq 'sql' && !$password) {
            push @error,("Error: user $name requires password");
            next;
        }
        Ravada::Auth::SQL::add_user(name => $name, password => $password
            ,@external);
        $count++;
    }
    return ($found, $count, \@error);
}

=head2 upload_users_json

Upload a list of users to the database

=head3 Arguments

=over

=item * string with users and passwords in each line

=item * type: it can be SQL, LDAP or SSO

=back

=cut


sub upload_users_json($self, $data_json, $type='openid') {

    my ($found, $count, @error);
    my $data;
    eval {
        $data= decode_json($data_json);
    };
    if ( $@ ) {
        push @error,($@);
        $data={}
    }

    my $result = {
        users_found => 0
        ,users_added => 0
        ,groups_found => 0
        ,groups_added => 0
    };
    if (exists $data->{groups} &&
        (!ref($data->{groups}) || ref($data->{groups}) ne 'ARRAY')) {
        die "Expecting groups as an array , got ".ref($data->{groups});
    }
    $data->{groups} = [] if !exists $data->{groups};
    for my $g0 (@{$data->{groups}}) {
        $result->{groups_found}++;
        my $g = $g0;
        if (!ref($g)) {
            $g = { name => $g0 };
        }
        if (!exists $g->{name} or !defined $g->{name} || !length($g->{name})) {
                push @error, ("Missing group name in ".Dumper($g));
                next;
        }
        $found++;
        my $group = Ravada::Auth::Group->new(name => $g->{name});
        my $members = delete $g->{members};
        if (!$group || !$group->id) {
            unless (defined $members && !scalar(@$members) && $data->{options}->{flush} && $data->{options}->{remove_empty}) {
                $result->{groups_added}++;
                Ravada::Auth::Group::add_group(%$g);
            }
        } else {
            push @error,("Group $g->{name} already added");
        }
        $self->_add_users($members, $type, $result, \@error, 1);
        $group->remove_other_members($members) if $data->{options}->{flush};

        for my $m (@$members) {
            my $user = Ravada::Auth::SQL->new(name => $m);
            $user->add_to_group($g->{name}) unless $user->is_member($g->{name});
        }
        if ( $data->{options}->{remove_empty} && $group->id && !$group->members ) {
            $group->remove();
            $result->{groups_removed}++;
            push @error,("Group ".$group->name." empty removed");
        }
    }

    $self->_add_users($data->{users}, $type, $result, \@error)
    if $data->{users};

    return ($result, \@error);
}

sub _add_users($self,$users, $type, $result, $error, $ignore_already=0) {
    for my $u0 (@$users) {
        $result->{users_found}++;
        my $u = $u0;
        $u = dclone($u0) if ref($u0);
        if (!ref($u)) {
            $u = { name => $u0 };
        }
        if (!exists $u->{is_external}) {
            if ($type ne 'sql') {
                $u->{is_external} = 1;
                $u->{external_auth} = $type ;
            }
        }
        my $user = Ravada::Auth::SQL->new(name => $u->{name});
        if ($user && $user->id) {
            push @$error,("User $u->{name} already added")
                unless $ignore_already;
            next;
        }
        Ravada::Auth::SQL::add_user(%$u);
        $result->{users_added}++;
    }
}

=head2 create_bundle

Creates a new bundle

Arguments: name

=cut

sub create_bundle($self,$name) {
    my $sth = $self->_dbh->prepare(
        "INSERT INTO bundles (name) values (?)"
    );
    $sth->execute($name);

    $sth = $self->_dbh->prepare(
        "SELECT id FROM bundles WHERE name=?"
    );
    $sth->execute($name);
    my ($id)= $sth->fetchrow;
    return $id;
}

=head2 bundle_private_network

Sets the bundle network to private

Arguments : id_bundle, value ( defaults 1 )

=cut

sub bundle_private_network($self, $id_bundle, $value=1){
    my $sth = $self->_dbh->prepare(
        "UPDATE bundles set private_network=? WHERE id=?");
    $sth->execute($value, $id_bundle);
}

=head2 bundle_isolated

Sets the bundle network isolated

Arguments : id_bundle, value ( defaults 1 )

=cut

sub bundle_isolated($self, $id_bundle, $value=1){
    my $sth = $self->_dbh->prepare(
        "UPDATE bundles set isolated=? WHERE id=?");
    $sth->execute($value, $id_bundle);
}


=head2 add_to_bundle

Adds a domain to a bundle

Arguments : id_bundle, id_domain

=cut

sub add_to_bundle ($self, $id_bundle, $id_domain){
    my $sth = $self->_dbh->prepare(
        "INSERT INTO domains_bundle (id_bundle, id_domain ) VALUES(?,?)"
    );
    $sth->execute($id_bundle, $id_domain);

}

=head2 upload_group_members

Upload a list of users to be added to a group

=head3 Arguments

=over

=item * string with users

=item * exclusive: remove all other users not uploaded here

=back

=cut

sub upload_group_members($self, $group_name, $users, $exclusive=0) {
    my $group = Ravada::Auth::Group->new(name => $group_name);
    $group = Ravada::Auth::Group::add_group(name => $group_name) if !$group->id;
    my ($found,$count) = (0,0);
    my @error;
    my @external = ( is_external => 1, external_auth => 'sso');
    my %members;
    for my $line (split /\n/,$users) {
        my ($name) = split(/:/,$line);
        $found++;
        my $user = Ravada::Auth::SQL->new(name => $name);
        if (!$user || !$user->id) {
            $user = Ravada::Auth::SQL::add_user(name => $name,
            ,@external);
        }
        $members{$name}++;
        if (!$user->is_member($group_name)) {
            $user->add_to_group($group_name);
            $count++;
        } else {
            push @error,("User $name already a member");
        }
    }
    if ($exclusive) {
        for my $name ($group->members) {
            $group->remove_member($name) unless $members{$name};
        }
    }
    return ($found, $count, \@error);
}

=head2 version

Returns the version of the main module

=cut

sub version {
    return Ravada::version();
}

1;
