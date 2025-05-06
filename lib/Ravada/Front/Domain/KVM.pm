package Ravada::Front::Domain::KVM;

use Carp qw(confess);
use Data::Dumper;
use Moose;
use Hash::Util qw(lock_hash unlock_hash);

use XML::LibXML;

extends 'Ravada::Front::Domain';

no warnings "experimental::signatures";
use feature qw(signatures);

our %GET_HW_SUB = (
    usb => \&_get_hw_usb
    ,'cpu' => \&_get_controller_cpu
    ,disk => \&_get_controller_disk
    ,display => \&_get_controller_display
    ,filesystem => \&_get_controller_filesystem
    ,'features' => \&_get_controller_features
    ,'memory' => \&_get_hw_memory
    ,network => \&_get_controller_network
    ,video => \&_get_controller_video
    ,sound => \&_get_controller_sound
    ,'usb controller' => \&_get_hw_usb_controller
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
     ,display => \&_get_driver_display
     ,cpu => \&_get_driver_cpu
     ,'usb controller'=> \&_get_driver_usb_controller
);


sub get_controller_by_name($self, $name) {
    if ( $GET_HW_SUB{filesystem}
        && $self->vm_version() < 6200000) {
        delete $GET_HW_SUB{filesystem};
    }

    return $GET_HW_SUB{$name};
}

sub list_controllers($self) {
    if ( $GET_HW_SUB{filesystem}
        && $self->vm_version() < 6200000) {
        delete $GET_HW_SUB{filesystem};
    }
    return %GET_HW_SUB;
}

sub _get_hw_usb {
	my $self = shift;
    $self->xml_description if !$self->readonly();
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));
    
    my @ret;
    
    for my $controller ($doc->findnodes('/domain/devices/redirdev')) {
        next if $controller->getAttribute('bus') ne 'usb';
        push @ret,({ type => $controller->getAttribute('type')
                ,_can_remove => 1
            });
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

sub _get_hw_usb_controller {
	my $self = shift;
    $self->xml_description if !$self->readonly();
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    my @ret;
    my %dupe;
    my $n = 1;
    for my $controller ($doc->findnodes('/domain/devices/controller')) {
        next if $controller->getAttribute('type') ne 'usb';
        my $model = $controller->getAttribute('model');
        my $dev = { model => $model, _can_edit => 1, _can_remove => 1 };
        my $name;
        for ( ;; ) {
            $name = "$model-$n";
            last if !$dupe{$name}++;
            $n++;
        }
        $dev->{_name} = $name;
        push @ret,($dev);
    }

    if (scalar(@ret) == 1) {
        $ret[0]->{_can_remove} = 0;
    }
    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}


sub _get_controller_video($self) {
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    my @ret;

    my $count = 0;
    my %dupe_name;
    for my $dev ($doc->findnodes('/domain/devices/video')) {
        my ($model) = $dev->findnodes("model");
        my $type = $model->getAttribute('type');
        my $item = { type => $type, _can_edit => 1, _can_remove => 1
        };
        my $name = $type;
        for my $n (0..10) {
            $name = "$type-$n";
            last if !$dupe_name{$name}++;
        }
        $item->{_name} = $name;
        _xml_elements($model,$item);
        $item->{_primary} = $item->{primary} if exists $item->{primary} && $item->{primary};
        lock_hash(%$item);
        push @ret,($item);
    }
    return @ret;

}

sub _get_controller_filesystem($self) {
    my @fs = $self->_get_controller_generic('filesystem');
    for my $fs ( @fs ) {
        my $name = $fs->{target}->{dir};
        unlock_hash(%$fs);
        $fs->{_name} = $name;
        delete $fs->{accessmode};
        delete $fs->{driver};
        delete $fs->{type};
        $fs->{_can_edit} = 1;
        $fs->{_can_remove} = 1;

        lock_hash(%$fs);
    }

    $self->_load_info_filesystem(\@fs);

    return @fs;
}

sub _get_controller_sound($self) {
    return $self->_get_controller_generic('sound');
}

sub _get_controller_generic($self,$type) {
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    my @ret;

    my $count = 0;
    for my $dev ($doc->findnodes('/domain/devices/'.$type)) {
        my $item = { _can_edit => 1, _can_remove => 1 };
        _xml_elements($dev,$item);
        delete $item->{address};
        lock_hash(%$item);
        push @ret,($item);
    }
    return @ret;

}

sub _get_controller_cpu($self) {
    my $xml = $self->_data_extra('xml');
    return if !$xml;
    my $doc = XML::LibXML->load_xml(string => $xml);
    my $item = {
        _name => 'cpu'
        ,_order => 0
        ,cpu => {}
        ,vcpu => {}
        ,_can_edit => 1
        ,_cat_remove => 0
    };

    my ($xml_cpu) = $doc->findnodes("/domain/cpu");
    _xml_elements($xml_cpu, $item->{cpu});

    my ($xml_vcpu) = $doc->findnodes("/domain/vcpu");
    _xml_elements($xml_vcpu, $item->{vcpu});

    $item->{vcpu}->{current} = $item->{vcpu}->{'#text'}
    if exists $item->{vcpu}->{'#text'} && ! defined $item->{vcpu}->{'current'};

    if (exists $item->{cpu}->{feature} && ref($item->{cpu}->{feature}) ne 'ARRAY') {
        $item->{cpu}->{feature} = [ $item->{cpu}->{feature} ];
    }

    $item->{cpu}->{feature} = []
    if !exists $item->{cpu}->{feature};

    $item->{cpu}->{feature}
    = _sort_xml_list($item->{cpu}->{feature},'name');


    lock_hash(%$item);
    return ($item);
}

sub _get_hw_memory($self) {

    my $info = $self->get_info();
    my ($memory, $current) = ($info->{max_mem}, $info->{memory});
    $memory = 0 if !defined $memory;
    $current = 0 if !defined $current;

    my $item = {
        max_mem => int($memory/1024)
        ,memory=> int($current/1024)
        ,_can_remove => 0
        ,_can_edit => 1
        ,_name => 'memory'
    };
    return $item;
}

sub _get_controller_features($self) {

    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    die "Error: no xml found for ".$self->name
    if !$doc;

    my $item = {
        _name => 'features'
        ,_order => 1
        ,_can_edit => 1
    };

    my ($xml) = $doc->findnodes("/domain/features");

    _xml_elements($xml, $item) if $xml;

    for my $feat (sort qw(acpi pae apic hap kvm vmport)) {
        $item->{$feat} = 0 if !exists $item->{$feat};
    }

    lock_hash(%$item);
    return ($item);
}

sub _sort_xml_list($list, $field) {
    my @sorted = sort {
        my ($name_a) = ($a->{$field} or '');
        my ($name_b) = ($b->{$field} or '');
        $name_a cmp $name_b
    }@$list;

    return \@sorted;
}

sub _xml_elements($xml, $item) {
    return {} if !defined $xml;
    my $text = $xml->textContent;
    $text = 0+$text if $text =~ /^\d+$/;
    $item->{'#text'} = $text if $text && $text !~ /\n/m;

    for my $attribute ( $xml->attributes ) {
        my $value = $attribute->value;
        $value = 0+$value if $value=~ /^\d+$/;
        $item->{$attribute->name} = $value;
    }

    for my $node ( $xml->findnodes('*') ) {
        my $h_node = {};
        _xml_elements($node, $h_node);
        $h_node = 1 if !keys %$h_node;
        my $name = $node->nodeName;
        if (!exists $item->{$name}) {
            $item->{$node->nodeName} = $h_node;
        } else {
            my $entry = $item->{$name};
            if (ref($entry) eq 'HASH') {
                $item->{$name} = [ $entry , $h_node ];
            } else {
                push @{$item->{$name}},($h_node);
            }
        }
    }
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
                    ,_name => $name
                  ,driver => $model->getAttribute('type')
                  ,bridge => $source->getAttribute('bridge')
                 ,network => $source->getAttribute('network')
                 ,_can_edit => 1
                 ,_can_remove => 1
        });
    }

    return @ret;
}

sub _get_controller_disk($self) {
    return Ravada::Front::Domain::_get_controller_disk($self);
}

sub _get_controller_display {
    return Ravada::Front::Domain::_get_controller_display(@_);
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

sub _get_driver_generic($self,$xml_path,$attribute=undef) {

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->_data_extra('xml'));

    for my $driver ($doc->findnodes($xml_path)) {
        if (defined $attribute) {
            my $value = $driver->getAttribute($attribute);
            confess "Error: attribute $attribute not in "
            .$driver->toString() if !defined $value;
            push @ret,($value);
        } else {
            my $str = $driver->toString;
            $str =~ s{^<$tag (.*)/>}{$1};
            push @ret,($str);
        }
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

sub _get_driver_cpu($self) {
    return $self->_get_driver_generic('/domain/cpu','mode');
}

sub _get_driver_usb_controller($self) {
    return $self->_get_driver_generic('/domain/devices/controller[@type="usb"]','model');
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

sub _get_driver_video($self) {
    return $self->_get_driver_generic('/domain/devices/video/model','type');
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

sub _get_driver_disk($self) {
    my @volumes = $self->list_volumes_info();
    return $volumes[0]->info()->{bus};
}

sub vm_version($self) {
    my $sth = $self->_dbh->prepare(
        "SELECT v.version FROM vms v, domains d"
        ." WHERE v.id=d.id_vm "
        ."    AND d.id=?"
    );
    $sth->execute($self->id);
    my ($version) = $sth->fetchrow;
    return ($version or 0);
}

sub _get_driver_display($self) {
    my $sth = $self->_dbh->prepare("SELECT driver FROM domain_displays "
        ." WHERE id_domain=? "
        ." ORDER BY n_order "
    );
    $sth->execute($self->id);
    my ($driver) = $sth->fetchrow;
    return $driver;
}

sub _os_type_machine($self) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description());
    my ($os_type) = $doc->findnodes('/domain/os/type');
    return $os_type->getAttribute('machine');
}

sub xml_description($self) {
        return $self->_data_extra('xml');
}

1;
