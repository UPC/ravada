package Ravada::Front::Domain::Void;

use Data::Dumper;
use Moose;
use YAML qw(LoadFile);

no warnings "experimental::signatures";
use feature qw(signatures);

extends 'Ravada::Front::Domain';

our %GET_CONTROLLER_SUB = (
    'mock' => \&_get_controller_mock
    ,'disk' => \&_get_controller_disk
    ,'display' => \&_get_controller_display
    ,'network' => \&_get_controller_network

);

sub _driver_field($self, $hardware) {
    my $field = 'driver';
    $field = 'bus' if $hardware eq 'device';

    return $field;
}

sub get_driver {
    my $self = shift;
    my $name = shift;

    my $drivers = $self->_value('drivers');
    return $drivers->{$name} if exists $drivers->{$name};

    my $hardware = $self->_value('hardware');

    $name = 'device' if $name eq 'disk';
    my $field = $self->_driver_field($name);

    return $hardware->{$name}->[0]->{$field}
        if $hardware->{$name} && $hardware->{$name}->[0];
}

sub _value{
    my $self = shift;

    my ($var) = @_;

    my ($disk) = $self->_config_file();

    my $data = {} ;
    $data = LoadFile($disk) if -e $disk;

    return $data->{$var};

}

sub _config_file {
    my $self = shift;
    return "/var/tmp/rvd_void/".getpwuid($>)."/".$self->name.".yml";
}

sub _config_dir {
    return "/var/tmp/rvd_void/".getpwuid($>);
}

sub list_controllers {
    return %GET_CONTROLLER_SUB;
}

sub get_controller_by_name {
    my ($self, $name) = @_;
    return $GET_CONTROLLER_SUB{$name};
}

sub _get_controller_mock {
    my $self = shift;
    my $hardware = $self->_value('hardware');
    return if !exists $hardware->{mock};
    return @{$hardware->{mock}};
}

sub _get_controller_disk {
    return Ravada::Front::Domain::_get_controller_disk(@_);
}

sub _get_controller_display(@args) {
    return Ravada::Front::Domain::_get_controller_display(@args);
}

sub _get_controller_generic($self, $item) {
    my $hardware = $self->_value('hardware');
    return () if !exists $hardware->{$item};
    return @{$hardware->{$item}};
}

sub _get_controller_network($self) {
    return $self->_get_controller_generic('network');
}

1;
