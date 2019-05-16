package Ravada::Front::Domain::KVM;

use Moose;

use XML::LibXML;

extends 'Ravada::Front::Domain';

no warnings "experimental::signatures";
use feature qw(signatures);

our %GET_CONTROLLER_SUB = (
    usb => \&_get_controller_usb
    ,disk => \&_get_controller_disk
    ,network => \&_get_controller_network
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
     ,disk => \&_get_driver_disk
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

sub _get_controller_disk($self) {
    return $self->list_volumes_info();
}

sub _get_controller_network($self) {
    $self->xml_description if !$self->readonly();
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    my @ret;

    my $count = 0;
    for my $interface ($doc->findnodes('/domain/devices/interface')) {
        next if $interface->getAttribute('type') !~ /^(bridge|network)/;

        my ($model) = $interface->findnodes('model') or die "No model";
        my ($source) = $interface->findnodes('source') or die "No source";
        my $type = 'NAT';
        $type = 'bridge' if $source->getAttribute('bridge');
        my ($address) = $interface->findnodes('address');
        my $name = "en";
        if ($address->getAttribute('type') eq 'pci') {
            my $slot = $address->getAttribute('slot');
            $name .="s".hex($slot);
        } else {
            $name .="o$count";
        }
        $count++;
        push @ret,({
                     type => $type
                    ,name => $name
                  ,driver => $model->getAttribute('type')
                  ,bridge => $source->getAttribute('bridge')
                 ,network => $source->getAttribute('network')
        });
    }

    return @ret;
}

=head2 get_driver

Gets the value of a driver

Argument: name

    my $driver = $domain->get_driver('video');

=cut

sub get_driver {
    my $self = shift;
    my $name = shift;

    my $sub = $GET_DRIVER_SUB{$name};

    die "I can't get driver $name for domain ".$self->name
        if !$sub;

    $self->xml_description if ref($self) !~ /Front/;

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

sub _get_driver_disk {
    my $self = shift;
    my @volumes = $self->list_volumes_info();
    return $volumes[0]->{driver};
}
1;
