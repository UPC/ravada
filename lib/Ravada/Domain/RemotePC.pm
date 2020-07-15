package Ravada::Domain::RemotePC;

use warnings;
use strict;

=head2 NAME

Ravada::Domain::RemotePC - RemotePC Machines library for Ravada

=cut

use Carp qw(cluck confess croak);
use Data::Dumper;
use File::Path qw( make_path );
use JSON::XS;
use Moose;
use Net::OpenSSH;

no warnings "experimental::signatures";
use feature qw(signatures);

extends 'Ravada::Front::Domain::RemotePC';
with 'Ravada::Domain';

around 'is_active' => \&_around_is_active;

my $RDP_PORT =  3390;
my $TIMEOUT_SHUTDOWN = 60;

my %HELPER = (
    ssh => {
        shutdown => \&_shutdown_ssh
    }
);

sub list_disks {
}

sub start($self, @args) {
    my $mac = $self->mac_address()
    or die "Error: Unknown MAC address for ".$self->name;

    return $self->_vm->wake_on_lan($mac);
}

sub _shutdown_ssh($self,@args) {
    $self->_execute_ssh('/sbin/poweroff');
}

sub _execute_ssh($self,$command) {
    my $ssh = $self->_connect_ssh();
    $ssh->system($command);
}

sub _add_key($self, $ip) {
    my @cmd = ( '/usr/bin/ssh-keygen', '-F', $ip);
    my ($out, $err) = $self->_vm->run_command(@cmd);
    return if $out;

    @cmd =  ( '/usr/bin/ssh-keyscan','-H',$ip);
    ($out, $err) = $self->_vm->run_command(@cmd);

    my @user = getpwuid($>);
    my $home  = $user[7];
    my $dir = $home."/.ssh";

    make_path($dir) or die "$! $dir"
    if ! -e $dir;

    open my $file_hosts,">>","$dir/known_hosts" or die $1;
    print $file_hosts $out;
    close $file_hosts;

}

sub _connect_ssh($self) {
    $self->_add_key($self->ip);
    my $ssh = Net::OpenSSH->new($self->ip);
    $ssh->error and
        die "Couldn't establish SSH connection to ".$self->ip." : ". $ssh->error;

    return $ssh;
}

sub shutdown($self,@args) {
    my $info = $self->get_info();
    my $access = $info->{admin_access};
    my $helper_type = $HELPER{$access} or die "Error: Unsupported admin helper $access";
    my $sub = $helper_type->{'shutdown'} or die "Error: Unsupported shutdown for $access";
    $sub->($self,@args);
}

sub force_shutdown($self, $user) {
    my $ret = $self->shutdown( user => $user);
    for ( 1 .. $TIMEOUT_SHUTDOWN ) {
        last if !$self->is_active;
        sleep 1;
    }
    return $ret;
}

sub shutdown_now { return force_shutdown(@_) }

sub remove($self, $user) {
    return;
}

sub mac_address($self) {
    my $mac = $self->_data_extra('mac');
    return $mac if $mac;

    my $ip = $self->ip or confess "Error: Unknown ip for machine ". $self->name;

    $mac = $self->_vm->find_mac_address($ip) or return;

    $self->_data_extra(mac => $mac);
    return $mac;
}

sub ip($self) {
    my $info = $self->_get_info_internal();
    confess if !defined $info;
    return $info->{ip};
}

sub autostart($self,$value=undef) {
    return $self->_data_extra('autostart', $value);
}

sub is_active($self) {
    return 0 if !$self->ip;
    return $self->_vm->_do_ping($self->ip);
}

sub display_info($self, $user) {
    my $port = $RDP_PORT;
    return {
        type => 'RDP'
        ,port => $port
        ,ip => $self->ip
        ,display => "rdp://".$self->ip.":$port"
    };
}

sub _get_info_internal($self) {
    my $info_json = $self->_data_extra('info');
    my $info = {};
    $info = decode_json($info_json) if length($info_json) && $info_json ne 'null';
    return $info;
}

sub get_info($self) {
    return $self->_get_info_internal();
}

sub _around_is_active($orig,$self,@args) {
    confess $self->{PASS} if $self->{PASS}++ > 1;
    my $is_active = $self->$orig(@args);

    $self->mac_address() if $is_active;
    $self->{PASS} = 0;

    return $is_active;
}

1;
