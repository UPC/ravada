use warnings;
use strict;

package Ravada::HostDevice;

=head1 NAME

Ravada::HostDevice - Host Device basic library for Ravada

=cut

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

has 'devices' => (
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
    $row->{devices} = '' if !defined $row->{devices};

    return Ravada::HostDevice->new(%$row);
}

sub list_devices($self) {
    my $vm = Ravada::VM->open($self->id_vm);

    die "Error: No list_command in host_device ".$self->id_vm
    if !$self->list_command;

    my @command = split /\s+/, $self->list_command;

    my ($out, $err) = $vm->run_command(@command);
    die $err if $err;
    my $filter = $self->list_filter();

    my @device;
    for my $line (split /\n/, $out ) {
        push @device,($line) if !defined $filter || $line =~ qr($filter)i;
    }
    my $encoded = encode_json(\@device);
    $self->_data( devices => $encoded );
    return @device;
}

sub is_device($self, $device) {
    return grep m{^$device$},$self->list_devices;
}

sub _device_locked($self, $name) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM host_devices_domain_locked "
        ." WHERE id_vm=? AND name=? "
    );
    $sth->execute($self->id_vm, $name);
    my ($is_locked) = $sth->fetchrow;
    $is_locked = 0 if !defined $is_locked;
    return 1 if $is_locked;
}

sub list_available_devices($self) {
    my @device;
    for my $dev_entry ( $self->list_devices ) {
        next if $self->_device_locked($dev_entry);
        push @device, ($dev_entry);
    }
    return @device;
}

sub remove($self) {
    _init_connector();

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id_domain FROM host_devices_domain "
        ." WHERE id_host_device=?"
    );
    $sth->execute($self->id);
    while ( my ( $id_domain ) = $sth->fetchrow) {
        my $domain = Ravada::Domain->open($id_domain);
        $domain->remove_host_device($self);
    }
    $sth = $$CONNECTOR->dbh->prepare("DELETE FROM host_devices WHERE id=?");
    $sth->execute($self->id);
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
        $self->_dettach_in_domains() if $field =~ /^(devices|list_)/;
        return $value;
    } else {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM host_devices"
            ." WHERE id=? "
        );
        $sth->execute($self->id);
        my $row = $sth->fetchrow_hashref();
        die "Error: No field '$field' in host_devices" if !exists $row->{$field};
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
        $domain->_dettach_host_device($self);
    }
}

sub add_host_device($self, %args ) {
    my $template = delete $args{template} or confess "Error: missing template name";
    my $info = Ravada::HostDevice::Templates::template($self->type, $template);
}

1;
