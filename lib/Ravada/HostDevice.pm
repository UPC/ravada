use warnings;
use strict;

package Ravada::HostDevice;

=head1 NAME

Ravada::HostDevice - Host Device basic library for Ravada

=cut

use Carp qw(croak cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use Mojo::Template;
use Mojo::JSON qw(encode_json decode_json);
use Moose;

use Ravada::Utils;

no warnings "experimental::signatures";
use feature qw(signatures);

our $CONNECTOR = \$Ravada::CONNECTOR;

has 'id' => (
    isa => 'Int'
    ,is => 'ro'
);

has 'id_vm' => (
    isa => 'Int'
    ,is => 'ro'
    ,required => 'true'
);

has 'list_command' => (
    isa => 'Str'
    ,is => 'ro'
    ,required => 'true'
);

has 'list_filter' => (
    isa => 'Str'
    ,is => 'ro'
);

has 'template_args' => (
    isa => 'Str'
    ,is => 'ro'
);

has 'name' => (
    isa => 'Str'
    ,is => 'ro'
);

has 'enabled' => (
    isa => 'Int'
    ,is => 'rw'
);

has 'devices_node' => (
    isa => 'Str'
    ,is => 'rw'
    ,default => ''
);

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

sub search_by_id($self, $id) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM host_devices WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    die "Error: device id='$id' not found" if !exists $row->{id};
    $row->{devices_node} = encode_json({}) if !defined $row->{devices_node};

    return Ravada::HostDevice->new(%$row);
}

sub list_devices_nodes($self) {
    my $vm = Ravada::VM->open($self->id_vm);
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,name,is_active,enabled FROM vms WHERE id <> ? AND vm_type=?");
    $sth->execute($vm->id, $vm->type);

    my @nodes = ([$vm->id,$vm->name,1,1]);

    while ( my ($id,$name, $is_active,$enabled) = $sth->fetchrow) {
        push @nodes,([$id, $name, $is_active, $enabled]);
    }

    my %devices;
    for my $ndata (@nodes) {
        if (!$ndata->[2] || !$ndata->[3]) {
            $devices{$ndata->[0]}=[];
            next;
        }
        my $node = Ravada::VM->open($ndata->[0]);
        my @current_devs;
        eval {
            @current_devs = $self->list_devices($node->id)
                if $node && $node->is_active;
        };
        warn $@ if $@;
        #        push @devices, @current_devs;
        $devices{$ndata->[0]}=\@current_devs;
    }

    $self->_data( devices_node => \%devices );
    return %devices;
}

sub refresh_devices_node($self, $id_vm) {
    my $data_json = $self->_data('devices_node');
    my $data = {};
    if ($data_json) {
        $data = $data_json;
        eval {
        $data = decode_json($data_json) if !ref($data_json);
        };
        warn $@ if $@;
    }

    my $node = Ravada::VM->open($id_vm);

    my @current_devs;
    eval {
            @current_devs = $self->list_devices($node->id)
                if $node && $node->is_active;
    };
    warn $@ if $@;
    $data->{$id_vm}=\@current_devs;

    $self->_data( devices_node => $data );

}

sub list_devices($self, $id_vm=$self->id_vm) {
    my $vm = Ravada::VM->open($id_vm);
    return [] unless $vm->is_active;
    die "Error: No list_command in host_device ".$self->id
    if !$self->list_command;

    my @command = split /\s+/, $self->list_command;

    my ($out, $err) = $vm->run_command(@command);
    die $err if $err;
    my $filter = $self->list_filter();

    my @device;
    for my $line (split /\n/, $out ) {
        push @device,($line) if !defined $filter || $line =~ qr($filter)i;
    }
    return @device;
}

sub is_device($self, $device, $id_vm) {
    return if !defined $device;
    for my $dev ( $self->list_devices($id_vm) ) {
       return 1 if $dev eq $device;
    }
    return 0;

}

sub _ttl_remove_volatile() {
    return $Ravada::Domain::TTL_REMOVE_VOLATILE;
}

sub _device_locked($self, $name, $id_vm=$self->id_vm) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,id_domain,time_changed "
        ." FROM host_devices_domain_locked "
        ." WHERE id_vm=? AND name=? "
    );
    $sth->execute($id_vm, $name);
    my $sth_status = $$CONNECTOR->dbh->prepare(
        "SELECT status FROM domains WHERE id=?"
    );

    my $sth_unlock = $$CONNECTOR->dbh->prepare(
        "DELETE FROM host_devices_domain_locked "
        ." WHERE id=?"
    );
    while ( my ($id_lock, $id_domain,$time_changed)= $sth->fetchrow ) {
        return $id_lock if time - $time_changed < _ttl_remove_volatile() ;
        $sth_status->execute($id_domain);
        my ($status) = $sth_status->fetchrow;
        return $id_domain if $status && $status ne 'shutdown';
        $sth_unlock->execute($id_lock);
    }
    return 0;
}

sub list_available_devices($self, $id_vm=$self->id_vm) {
    my @device;
    for my $dev_entry ( $self->list_devices($id_vm) ) {
        next if $self->_device_locked($dev_entry, $id_vm);
        push @device, ($dev_entry);
    }
    return @device;
}

sub list_available_devices_cached($self, $id_vm=$self->id_vm) {
    my @device;
    my $dn = {};
    my $data_dn = $self->_data('devices_node');
    if (!$data_dn) {
        my %data_dn = $self->list_devices_nodes();
        $dn = \%data_dn;
    } else {
        eval { $dn = decode_json($data_dn) };
        if ($@) {
            warn "$@ ".($data_dn or '<NULL>');
            return $self->list_available_devices($id_vm);
        }
    }
    my $dnn = $dn->{$id_vm};
    for my $dev_entry ( @$dnn ) {
        next if $self->_device_locked($dev_entry, $id_vm);
        push @device, ($dev_entry);
    }
    return @device;
}


sub remove($self) {
    _init_connector();
    my $id = $self->id;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id_domain FROM host_devices_domain "
        ." WHERE id_host_device=?"
    );
    $sth->execute($id);
    while ( my ( $id_domain ) = $sth->fetchrow) {
        my $domain = Ravada::Domain->open($id_domain);
        $domain->remove_host_device($self);
    }

    $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices WHERE id=?");
    $sth->execute($id);

    Ravada::Request::remove('requested', id_host_device => $id );
}

sub _fetch_template_args($self, $device) {
    confess "Error: missing device " if !defined $device;

    my $tp_args = decode_json($self->template_args());
    my $ret = {};
    while (my ($name, $re) = each %$tp_args) {
        if ($re eq '_DEVICE_CONTENT_') {
            open my $in,"<", $device or die "$! $device";
            $ret->{$name} = join("",<$in>);
            close $in;
        } else {
            my ($value) = $device =~ qr($re);
            confess "Error: $re not found in '$device'" if !defined $value;
            # we do have to remove leading 0 or those numbers
            # will be converted from Octal !
            $value =~ s/^0+([0-9a-f]+)/$1/ if $value =~ /^0*[0-9a-f]*$/;
            $ret->{$name} = ''.$value;
        }
    }
    return $ret;
}

sub list_templates($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM host_device_templates "
        ." WHERE id_host_device=?"
    );
    $sth->execute($self->id);
    my @list;
    while ( my $row = $sth->fetchrow_hashref) {
        push @list,($row);
    }
    return @list;
}

sub render_template($self, $device) {
    my $mt = Mojo::Template->new();
    my @ret;
    for my $entry ($self->list_templates) {
        if ($entry->{type} eq 'namespace') {
            $entry->{content} = $entry->{template};
        } else {
            $entry->{content} = $mt->vars(1)->render($entry->{template}
                , $self->_fetch_template_args($device));
            $entry->{type} = '' if !defined $entry->{type};
        }
        lock_hash(%$entry);
        push @ret,($entry);
    }
    return @ret;
}

sub _data($self, $field, $value=undef) {
    if (defined $value ) {

        die "Error: invalid value '$value' in $field"
        if $field eq 'list_command' &&(
            $value =~ m{["'`$()\[\];]}
            || $value !~ /^(ls|find)/);

        $value = encode_json($value) if ref($value);

        my $old_value = $self->_data($field);
        return if defined $old_value && $old_value eq $value;

        my $sth = $$CONNECTOR->dbh->prepare("UPDATE host_devices SET $field=?"
            ." WHERE id=? "
        );
        $sth->execute($value, $self->id);
        $self->meta->get_attribute($field)->set_value($self, $value);
        if ( $field =~ /^(devices|list_)/ ) {
            $self->_dettach_in_domains();
            if ($field =~ /^list_/) {
                Ravada::Request->list_host_devices(
                    uid => Ravada::Utils::user_daemon->id
                    ,id_host_device => $self->id
                );
                $self->_data('devices_node' => '');
            }
        }
        return $value;
    } else {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM host_devices"
            ." WHERE id=? "
        );
        $sth->execute($self->id);
        my $row = $sth->fetchrow_hashref();
        croak "Error: No field '$field' in host_devices" if !exists $row->{$field};
        return $row->{$field};
    }
}

sub list_domains_with_device($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id_domain FROM host_devices_domain "
        ." WHERE id_host_device=?");
    $sth->execute($self->id);
    my @domains;
    while (my ($id_domain) = $sth->fetchrow ) {
        push @domains,($id_domain);
    }
    return @domains;
}

sub _dettach_in_domains($self) {
    for my $id_domain ( $self->list_domains_with_device() ) {
        my $domain = Ravada::Domain->open($id_domain);
        if (!$domain) {
            warn "unlocking from domain $id_domain";
            my $sth = $$CONNECTOR->dbh->prepare(
                "DELETE FROM host_devices_domain_locked "
                ." WHERE id_domain=?"
            );
            $sth->execute($id_domain);

            $sth = $$CONNECTOR->dbh->prepare(
                "DELETE FROM host_devices_domain "
                ." WHERE id_host_device=?"
                ."   AND id_domain=?"
            );
            $sth->execute($self->id, $id_domain);
            next;
        }
        $domain->_dettach_host_device($self) if !$domain->is_active();
    }
}

sub add_host_device($self, %args ) {
    my $template = delete $args{template} or confess "Error: missing template name";
    my $info = Ravada::HostDevice::Templates::template($self->type, $template);
}

1;
