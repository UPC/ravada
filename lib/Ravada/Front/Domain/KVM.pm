package Ravada::Front::Domain::KVM;

use Moose;

use XML::LibXML;

extends 'Ravada::Front::Domain';

no warnings "experimental::signatures";
use feature qw(signatures);

our %GET_CONTROLLER_SUB = (
    usb => \&_get_controller_usb
    );

our %GET_DRIVER_SUB = (
    network => \&_get_driver_network
     ,sound => \&_get_driver_sound
     ,video => \&_get_driver_video
     ,image => \&_get_driver_image
     ,jpeg => \&_get_driver_jpeg
     ,zlib => \&_get_driver_zlib
     ,playback => \&_get_driver_playback
     ,streaming => \&_get_driver_streaming
);


sub get_controller_by_name($self, $name) {
    return $GET_CONTROLLER_SUB{$name};
}

sub list_controllers($self) {
    return %GET_CONTROLLER_SUB;
}

sub _get_controller_usb {
	my $self = shift;
    $self->xml_description if !$self->readonly();
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));
    
    my @ret;
    
    for my $controller ($doc->findnodes('/domain/devices/redirdev')) {
        next if $controller->getAttribute('bus') ne 'usb';
        
        push @ret,('type="'.$controller->getAttribute('type').'"');
    } 

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

=head2 get_driver

Gets the value of a driver

Argument: name

    my $driver = $domain->get_driver('video');

=cut

sub get_driver($self, $name) {

    my $sub = $GET_DRIVER_SUB{$name};

    confess "I can't get driver $name for domain ".$self->name
        if !$sub;

    $self->xml_description_inactive if ref($self) !~ /Front/;

    return $sub->($self);
}

sub _get_driver_generic {
    my $self = shift;
    my $xml_path = shift;

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    for my $driver ($doc->findnodes($xml_path)) {
        my $str = $driver->toString;
        $str =~ s{^<$tag (.*)/>}{$1};
        push @ret,($str);
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

sub _get_driver_graphics {
    my $self = shift;
    my $xml_path = shift;

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    for my $tags (qw(image jpeg zlib playback streaming)){
        for my $driver ($doc->findnodes($xml_path)) {
            my $str = $driver->toString;
            $str =~ s{^<$tag (.*)/>}{$1};
            push @ret,($str);
        }
    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
    }
}

sub _get_driver_image {
    my $self = shift;

    my $image = $self->_get_driver_graphics('/domain/devices/graphics/image',@_);
#
#    if ( !defined $image ) {
#        my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);
#        Ravada::VM::KVM::xml_add_graphics_image($doc);
#    }
    return $image;
}

sub _get_driver_jpeg {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/jpeg',@_);
}

sub _get_driver_zlib {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/zlib',@_);
}

sub _get_driver_playback {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/playback',@_);
}

sub _get_driver_streaming {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/streaming',@_);
}

sub _get_driver_video {
    my $self = shift;
    return $self->_get_driver_generic('/domain/devices/video/model',@_);
}

sub _get_driver_network {
    my $self = shift;
    return $self->_get_driver_generic('/domain/devices/interface/model',@_);
}

sub _get_driver_sound {
    my $self = shift;
    my $xml_path ="/domain/devices/sound";

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    for my $driver ($doc->findnodes($xml_path)) {
        push @ret,('model="'.$driver->getAttribute('model').'"');
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;

}

sub get_info {
    my $self = shift;

    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));
    my $info;
    $info->{max_mem} = ($doc->findnodes('/domain/memory'))[0]->textContent;
    $info->{memory} = ($doc->findnodes('/domain/currentMemory'))[0]->textContent;

    return $info;
}

1;
