use warnings;
use strict;

package Ravada::HostDevice::Templates;

=head1 NAME

Ravada::HostDevice - Host Device basic library for Ravada

=cut

use Data::Dumper;
use Hash::Util qw(lock_hash);
use Mojo::JSON qw(encode_json);
use Moose;
use Ravada::Utils;
use YAML qw(Dump);

no warnings "experimental::signatures";
use feature qw(signatures);

our $CONNECTOR = \$Ravada::CONNECTOR;
$CONNECTOR = \$Ravada::Front::CONNECTOR if ! $$CONNECTOR;

our @TEMPLATES_KVM  = (
    {
        name => "USB device"
        ,list_command => "lsusb"
        ,list_filter => "ID "
        ,template_args =>  encode_json ({
                vendor_id => 'ID ([a-f0-9]+)'
                ,product_id => 'ID .*?:([a-f0-9]+)'
                ,bus => 'Bus (\d+)'
                ,device => 'Device (\d+)'
            })
        ,templates => [
            {
                path => "/domain/devices/hostdev"
                ,type => 'node'
                ,template => "<hostdev mode='subsystem' type='usb' managed='yes'>
                <source>
                <vendor id='0x<%= \$vendor_id %>'/>
                <product id='0x<%= \$product_id %>'/>
                <address bus='<%= \$bus %>' device='<%= \$device %>'/>
                </source>
                </hostdev>"
            }
        ]
    }
    ,{
        name => 'PCI'
        ,list_command => 'lspci -Dnn'
        ,list_filter => ''
        ,template_args => encode_json({
                pci => '([0-9a-f:\.]+) '
                ,domain =>'(^[0-9a-f]{4})'
                ,bus => '....:([0-9a-f]+):'
                ,slot => '^....:..:([0-9a-f]+)\.'
                ,function => '^....:..:[0-9a-f]+\.([0-9a-f])'

            })
        ,templates => [
            {
            path => '/domain/features/kvm'
            ,type => 'unique_node'
            ,template => "<kvm>
                <hidden state='on'/>
                </kvm>"
            },
            {
            path => '/domain/devices/hostdev'
            ,template => "<hostdev mode='subsystem' type='pci' managed='yes'>
                <driver name='vfio'/>
                <source>
                <address domain='0x<%= \$domain %>' bus='0x<%= \$bus %>' slot='0x<%= \$slot %>' function='0x<%= \$function %>'/>
                </source>
                <rom bar='on'/>
                <address type='pci' domain='0x0000' bus='0x01' slot='0x01' function='0x<%= \$function %>'/>
            </hostdev>"
            }
        ]
    }

#    ,{
#        name => "GPU dri"
#        ,list_command => "find /dev/dri/by-path/ -type f"
#        ,list_filter => ""
#        ,template_args => encode_json({
#                pci => "0000:([a-f0-9:\.]+)"
#                ,uuid => "_DEVICE_CONTENT_"
#            })
#        ,templates => [
#            {path => "/domain"
#                ,type => "namespace"
#                ,template => "qemu='http://libvirt.org/schemas/domain/qemu/1.0'"
#            }
#            ,
#            {path => "/domain/metadata/libosinfo:libosinfo"
#                ,template => "<libosinfo:libosinfo xmlns:libosinfo='http://libosinfo.org/xmlns/libvirt/domain/1.0'>
#                <libosinfo:os id='http://microsoft.com/win/10'/>
#                </libosinfo:libosinfo>"
#            }
#            ,
#            {path => "/domain/devices/graphics[\@type='spice']"
#                ,template =>  "<graphics type='spice' autoport='yes'>
#                <listen type='address'/>
#                <image compression='auto_glz'/>
#                <jpeg compression='auto'/>
#                <zlib compression='auto'/>
#                <playback compression='on'/>
#                <streaming mode='filter'/>
#                <gl enable='no' rendernode='/dev/dri/by-path/pci-<%= \$pci %> render'/>
#                </graphics>"
#            }
#            ,
#            {path => "/domain/devices/graphics[\@type='egl-headless']"
#                ,template =>  "<graphics type='egl-headless'/>"
#            }
#            ,
#            {
#                path => "/domain/devices/hostdev"
#                ,template =>
#                "<hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci' display='off'>
#                <source>
#                <address uuid='<%= \$uuid %>'/>
#                </source>
#                <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x0'/>
#                </hostdev>"
#            }
#
#        ]
#    }
#
);

our @TEMPLATES_VOID = (
    {
        name => "USB device"
        ,list_command => "lsusb"
        ,list_filter => "ID "
        ,template_args =>  encode_json ({
                vendor_id => 'ID ([a-f0-9]+)'
                ,product_id => 'ID .*?:([a-f0-9]+)'
            })
        ,templates => [{path => "/hardware/host_devices"
                ,type => 'node'
                ,template => Dump( device => {
                        vendor_id => '<%= $vendor_id %>'
                        , product_id => '<%= $product_id %>'
                    })
            }
        ]
    }
);

my %TEMPLATES = (
    'KVM' => \@TEMPLATES_KVM
    ,'Void' => \@TEMPLATES_VOID
);

sub _vm_name($id) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT vm_type FROM vms WHERE id=?"
    );
    $sth->execute($id);
    my ($type) = $sth->fetchrow;

    die "Error: id '$id' not found in VMS " if !defined $type;
    return $type;
}

sub list_templates($vm_name) {
    $vm_name = _vm_name($vm_name) if $vm_name =~ /^\d+$/;
    my $list = $TEMPLATES{$vm_name};
    return [] if !$list;
    return $list;
}

sub template($vm_name, $name) {
    my $list = list_templates($vm_name);
    for my $template (@$list) {
        next if $template->{name} ne $name;
        my %copy = %$template;
        return \%copy;
    }
    die "Error: Missing template $vm_name - $name";
}

1;
