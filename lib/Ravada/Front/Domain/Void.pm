package Ravada::Front::Domain::Void;

use Moose;
use YAML qw(LoadFile);

extends 'Ravada::Front::Domain';

my $DIR_TMP = "/var/tmp/rvd_void";

sub get_driver {
    my $self = shift;
    my $name = shift;

    my $drivers = $self->_value('drivers');
    return $drivers->{$name};
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
    return "$DIR_TMP/".$self->name.".yml";
}

1;
