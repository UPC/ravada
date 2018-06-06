package Ravada::Front::Domain::KVM;

use Moose;

use XML::LibXML;

extends 'Ravada::Front::Domain';

our %GET_CONTROLLER_SUB = (
    usb => \&_get_controller_usb
    );

=head2 get_controller

Calls the method to get the specified controller info

Attributes:
    name -> name of the controller type

=cut
sub get_controller {
	my $self = shift;
	my $name = shift;
    my $sub = $GET_CONTROLLER_SUB{$name};
    
    die "I can't get controller $name for domain ".$self->name
        if !$sub;

    return $sub->($self);
}

sub _get_controller_usb {
	my $self = shift;
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));
    
    my @ret;
    
    for my $controller ($doc->findnodes('/domain/devices/redirdev')) {
        next if $controller->getAttribute('bus') ne 'usb';
        
        push @ret,('type="'.$controller->getAttribute('type').'"');
    } 

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

1;