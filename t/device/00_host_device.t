use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Path qw(make_path);
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json encode_json);
use Ravada::Request;
use Test::More;
use YAML qw( Dump );

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada::HostDevice');
use_ok('Ravada::HostDevice::Templates');

my $N_DEVICE = 0;
my $USB_DEVICE;
load_usb_device();
#########################################################

# we will try to find an unused bluetooth usb dongle

sub load_usb_device() {
    open my $in,"<","t/etc/usb_device.conf" or return;
    $USB_DEVICE = <$in>;
    chomp $USB_DEVICE;
}

sub _search_unused_device {
    my @cmd =("lsusb");
    my ($in, $out, $err);
    run3(["lsusb"], \$in, \$out, \$err);
    for my $line ( split /\n/, $out ) {
        next if $line !~ /Bluetooth|flash|disk|cam/i;
        next unless (defined $USB_DEVICE && $line =~ $USB_DEVICE) 
        || $line =~ /Bluetooth|flash|disk|cam/i;

        my ($filter) = $line =~ /(ID [a-f0-9]+):/;
        die "ID \\d+ not found in $line" if !$filter;
        return ("lsusb",$filter);
    }
}

sub _template_usb($vm) {
    if ( $vm->type eq 'KVM' ) {
    return (
        { path => "/domain/devices/hostdev"
        ,type => 'node'
        ,template => "<hostdev mode='subsystem' type='usb' managed='no'>
            <source>
                <vendor id='0x<%= \$vendor_id %>'/>
                <product id='0x<%= \$product_id %>'/>
                <address bus='<%= \$bus %>' device='<%= \$device %>'/>
            </source>
        </hostdev>"
        })
    } elsif ($vm->type eq 'Void') {
        return (
            {path => "/hardware/host_devices"
            ,type => 'node'
            ,template => Dump( device => { device => 'hostdev'
                    , vendor_id => '<%= $vendor_id %>'
                    , product_id => '<%= $product_id %>'
            })
        });
    }
}

sub _template_xmlns($vm) {
    return (
        {path => "/domain"
            ,type => "namespace"
            ,template => "qemu='http://libvirt.org/schemas/domain/qemu/1.0'"
        }
        ,
        { path => "/domain/qemu:commandline"
                ,template => "
                <qemu:commandline>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.hostdev0.x-igd-opregion=on'/>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.hostdev0.display=on'/>
    <qemu:arg value='-display'/>
    <qemu:arg value='egl-headless'/>
  </qemu:commandline>"
    }
    );
}

sub _template_gpu($vm) {
    if ($vm->type eq 'KVM') {
        return (
                {path => "/domain"
                    ,type => "namespace"
                    ,template => "qemu='http://libvirt.org/schemas/domain/qemu/1.0'"
                }
                ,
                {path => "/domain/metadata/libosinfo:libosinfo"
                ,template => "<libosinfo:libosinfo xmlns:libosinfo='http://libosinfo.org/xmlns/libvirt/domain/1.0'>
      <libosinfo:os id='http://microsoft.com/win/10'/>
    </libosinfo:libosinfo>"
                }
                ,
                {path => "/domain/devices/graphics[\@type='spice']"
                 ,type => 'unique_node'
                 ,template =>  "<graphics type='spice' autoport='yes'>
                    <listen type='address'/>
                    <image compression='auto_glz'/>
                    <jpeg compression='auto'/>
                    <zlib compression='auto'/>
                    <playback compression='on'/>
                    <streaming mode='filter'/>
                    <gl enable='no' rendernode='/dev/dri/by-path/pci-<%= \$pci %> render'/>
                    </graphics>"
                }
                ,
                {path => "/domain/devices/graphics[\@type='egl-headless']"
                 ,type => 'unique_node'
                 ,template =>  "<graphics type='egl-headless'/>"
                }
                ,
                {
                    path => "/domain/devices/hostdev"
                 ,type => 'unique_node'
                 ,template =>
"<hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci' display='off'>
    <source>
        <address uuid='<%= \$uuid %>'/>
    </source>
    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x0'/>
</hostdev>"
                }
                ,
                { path => "/domain/qemu:commandline"
                 ,type => 'unique_node'
                ,template => "
                <qemu:commandline>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.hostdev0.x-igd-opregion=on'/>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.hostdev0.display=on'/>
    <qemu:arg value='-display'/>
    <qemu:arg value='egl-headless'/>
  </qemu:commandline>"
  }
            )
    } else {
        return (
                {path => "/hardware/host_devices"
                 ,type => 'unique_node'
                 ,template => Dump(
                     { 'device' => 'graphics'
                       ,"rendernode" => 'pci-<%= $pci %>'
                     }
                 )
                }
            );
    }
}

sub _template_args_usb {
    return encode_json ({
        vendor_id => 'ID ([a-f0-9]+)'
        ,product_id => 'ID .*?:([a-f0-9]+)'
        ,bus => 'Bus (\d+)'
        ,device => 'Device (\d+)'
    });
}

sub _template_args_gpu {
    return encode_json({
            pci => "0000:([a-f0-9:\.]+)"
            ,uuid => "_DEVICE_CONTENT_"
    });
}

sub _insert_hostdev_data_usb($vm, $name, $list_command, $list_filter) {
    my $sth = connector->dbh->prepare("INSERT INTO host_devices "
    ."(name, id_vm, list_command, list_filter, template_args ) "
    ." VALUES (?, ?, ?, ?, ? )"
    );
    $sth->execute(
        $name
        ,$vm->id,
        ,$list_command, $list_filter
        ,_template_args_usb()
    );
    _insert_hostdev_data_template(_template_usb($vm));
}

sub _insert_hostdev_data_gpu($vm, $name, $list_command, $list_filter) {
    my $sth = connector->dbh->prepare("INSERT INTO host_devices "
    ."(name, id_vm, list_command, list_filter, template_args ) "
    ." VALUES (?, ?, ?, ?, ? )"
    );
    $sth->execute(
        $name
        ,$vm->id,
        ,$list_command, $list_filter
        ,_template_args_gpu()
    );
    _insert_hostdev_data_template(_template_gpu($vm));
}

sub _insert_hostdev_data_xmlns($vm, $name, $list_command, $list_filter) {
    my $sth = connector->dbh->prepare("INSERT INTO host_devices "
    ."(name, id_vm, list_command, list_filter, template_args ) "
    ." VALUES (?, ?, ?, ?, ? )"
    );
    $sth->execute(
        $name
        ,$vm->id,
        ,$list_command, $list_filter
        ,_template_args_gpu()
    );
    _insert_hostdev_data_template(_template_xmlns($vm));
}


sub _insert_hostdev_data_template(@template) {
    my $id = Ravada::Request->_last_insert_id(connector());

    my $sth = connector->dbh->prepare("INSERT INTO host_device_templates "
        ." ( id_host_device, path, template , type ) "
        ." VALUES ( ?, ? , ? , ?)"
    );
    for my $template(@template) {
        $template->{type} = 'node' if !$template->{type};
        $sth->execute($id, $template->{path}, $template->{template}, $template->{type});
    }
}


sub _check_hostdev_kvm($domain, $expected=0) {
    my $doc = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);
    my @hostdev = $doc->findnodes("/domain/devices/hostdev");
    is(scalar @hostdev, $expected, $domain->name) or confess ;
}

sub _check_hostdev_void($domain, $expected=0) {
    my $doc = $domain->_load();
    my @hostdev;
    for my $dev ( @{ $doc->{hardware}->{host_devices} } ) {
        push @hostdev,($dev);
        for my $item ( keys %$dev ) {
            like($item,qr/^\w+$/);
            like($dev->{$item}, qr(^[0-9a-z]+$)) or die Dumper($dev);
        }
    }
    is(scalar @hostdev, $expected) or confess Dumper($domain->name, $doc->{hardware});

}

sub _check_hostdev($domain, $expected=0) {
    if ($domain->type eq 'KVM') {
        _check_hostdev_kvm($domain, $expected);
    } elsif ($domain->type eq 'Void') {
        _check_hostdev_void($domain, $expected);
    }
}

sub test_devices($host_device, $expected_available, $match = undef) {
    my @devices = $host_device->list_devices();
    ok(scalar(@devices));

    my @devices_available = $host_device->list_available_devices();
    ok(scalar(@devices_available) >= $expected_available,Dumper(\@devices)) or confess;

    return if !$match;

    for (@devices) {
        next if defined $USB_DEVICE && $_ =~ qr($USB_DEVICE);
        like($_,qr($match));
    }
}

sub test_host_device_usb($vm) {

    diag("Test host device USB in ".$vm->type);

    my ($list_command,$list_filter) = _search_unused_device();
    unless ( $list_command ) {
        diag("SKIPPED: install a USB device to test");
        return;
    }
    _insert_hostdev_data_usb($vm, "USB Test", $list_command, $list_filter);

    my @list_hostdev = $vm->list_host_devices();
    is(scalar @list_hostdev, 1);

    isa_ok($list_hostdev[0],'Ravada::HostDevice');

    my $base = create_domain($vm);
    if ($base->type eq 'KVM') {
        my $req = Ravada::Request->remove_hardware(
            name => 'usb'
            ,id_domain => $base->id
            ,uid => user_admin->id
            ,index => 2
        );
        wait_request();
        #    $base->_set_controller_usb(5) if $base->type eq 'KVM';
    }

    $base->add_host_device($list_hostdev[0]);
    my @list_hostdev_b = $base->list_host_devices();
    is(scalar @list_hostdev_b, 1);

    test_devices($list_hostdev[0],1, qr/Bluetooth|flash|disk|cam/i);

    $base->prepare_base(user_admin);
    my $clone = $base->clone(name => new_domain_name
        ,user => user_admin
    );
    my @list_hostdev_c = $clone->list_host_devices();
    is(scalar @list_hostdev_c, 1) or exit;
    my $device = $list_hostdev_c[0]->{devices};

    test_kvm_usb_template_args($device, $list_hostdev_c[0]);

    _check_hostdev($clone);
    diag($clone->name);
    $clone->start(user_admin);
    _check_hostdev($clone, 1);

    shutdown_domain_internal($clone);
    eval { $clone->start(user_admin) };
    is(''.$@, '') or exit;
    _check_hostdev($clone, 1) or exit;

    #### it will fail in another clone

    for ( 1 .. 10 ) {
        my $clone2 = $base->clone( name => new_domain_name
            ,user => user_admin
        );
        eval { $clone2->start(user_admin) };
        last if $@;
    }
    like ($@ , qr(No available devices));

    $list_hostdev[0]->remove();
    my @list_hostdev2 = $vm->list_host_devices();
    is(scalar @list_hostdev2, 0);

    remove_domain($base);
    test_db_host_devices_removed($base, $clone);

    $list_hostdev[0]->remove();
}

sub test_kvm_usb_template_args($device_usb, $hostdev) {
    my ($bus, $device, $vendor_id, $product_id)
    = $device_usb =~ /Bus 0*(\d+) Device 0*(\d+).*ID (.*?):(.*?) /;
    my $args = $hostdev->_fetch_template_args($device_usb);
    is($args->{device}, $device);
    is($args->{bus}, $bus);
    is($args->{vendor_id}, $vendor_id);
    is($args->{product_id}, $product_id);
}

sub _create_mock_devices($n_devices, $type, $value="fff:fff") {
    my $path  = "/var/tmp/$</ravada/dev";
    make_path($path) if !-e $path;

    my $name = base_domain_name()." $type Mock_device ID";

    opendir my $dir,$path or die "$! $path";
    while ( my $file = readdir $dir ) {
        next if $file !~ /^$name/;
        unlink "$path/$file" or die "$! $path/$file";
    }
    closedir $dir;

    for ( 1 .. $n_devices ) {
        open my $out,">","$path/${name} $N_DEVICE$value$_ Foo bar"
            or die $!;
        print $out "fff6f017-3417-4ad3-b05e-17ae3e1a461".int(rand(10));
        close $out;
    }
    $N_DEVICE ++;

    return ("find $path/",$name);
}

sub test_host_device_usb_mock($vm, $n_hd=1) {
    return if ($vm->type eq 'KVM');

    my $n_devices = 3;

    my ($list_command,$list_filter) = _create_mock_devices( $n_devices*$n_hd , "USB" , " Device 1 Bus 1 aaa:aaa" );

    for ( 1 .. $n_hd ) {
        _insert_hostdev_data_usb($vm, "USB Mock $_", $list_command, $list_filter);
    }

    my @list_hostdev = $vm->list_host_devices();
    is(scalar @list_hostdev, $n_hd) or die Dumper(\@list_hostdev);

    isa_ok($list_hostdev[0],'Ravada::HostDevice');

    my $base = create_domain($vm);
    $base->_set_controller_usb(5) if $base->type eq 'KVM';

    for my $hd ( @list_hostdev ) {
        $base->add_host_device($hd);
    }
    my @list_hostdev_b = $base->list_host_devices();
    is(scalar @list_hostdev_b, $n_hd) or die Dumper(\@list_hostdev_b);

    $base->prepare_base(user_admin);

    my @clones;
    for my $n ( 1 .. $n_devices+1 ) {
        my $clone = $base->clone(name => new_domain_name
            ,user => user_admin
        );

        _check_hostdev($clone, 0 );
        eval { $clone->start(user_admin) };
        # the last one should fail
        if ($n > $n_devices) {
            like( ''.$@,qr(No available devices));
            _check_hostdev($clone, 0);
        } else {
            like( ''.$@,qr(Did not find USB device)) if $vm->type eq 'KVM';
            is( ''.$@, '' ) if $vm->type eq 'Void';
            _check_hostdev($clone, $n_hd);
        }
        is(scalar($clone->list_host_devices_attached()), $n_hd, $clone->name);
        push @clones,($clone);
    }
    $clones[0]->shutdown_now(user_admin);
    _check_hostdev($clones[0], $n_hd);
    my @devs_attached = $clones[0]->list_host_devices_attached();
    is(scalar(@devs_attached), $n_hd);
    is($devs_attached[0]->{is_locked},0);

    for (@list_hostdev) {
        $_->_data('enabled' => 0 );
    }
    is( scalar($vm->list_host_devices()) , $n_hd );
    is( scalar($base->list_host_devices()), 0);
    is( scalar($clones[0]->list_host_devices()), 0);
    is( scalar($clones[0]->list_host_devices_attached()), 0);

    my $clone_nhd = $base->clone(name => new_domain_name, user => user_admin);
    eval { $clone_nhd->start( user_admin ) };

    is( scalar($clone_nhd->list_host_devices()), 0);
    is( scalar($clone_nhd->list_host_devices_attached()), 0);

    remove_domain($base);
    for ( @list_hostdev ) {
        $_->remove();
    }
    test_db_host_devices_removed($base, @clones);
}

sub test_db_host_devices_removed(@domains) {
    my $sth = connector->dbh->prepare("SELECT count(*) from host_devices_domain "
        ." WHERE id_domain=?"
    );
    for my $domain ( @domains ) {
        $sth->execute($domain->id);
        my ($count) = $sth->fetchrow;
        is($count,0,"Expecting host_device_domain removed from db ".$domain->name) or confess;
    }

    $sth = connector->dbh->prepare("SELECT count(*) FROM host_devices ");
    $sth->execute();
    my ($count) = $sth->fetchrow;
    is($count, 0, "Expecting no host devices") or confess;
}

sub test_domain_path_kvm($domain, $path) {
    my $doc = XML::LibXML->load_xml(string
            => $domain->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE))
        or die "ERROR: $!\n";

    confess if !$path;

    my @nodes = $doc->findnodes($path);
    is(scalar @nodes, 1, "Expecting $path in ".$domain->name) or exit;

}

sub test_domain_path_void($domain, $path) {
    my $data = $domain->_load();
    my $found_parent;

    my ($parent, $entry) = $path =~ m{/(.*)/(.*)};
    confess "Error: $path hauria de ser parent/entry" if !$entry;
    for my $entry ( split m{/},$parent ) {
        $found_parent = $data->{$entry} or last;
        $data = $found_parent;
    }
    ok($found_parent, "Expecting $parent in ".$domain->name) or die Dumper($domain->name, $data);
    my $found;
    if (ref($found_parent) eq 'ARRAY') {
        for my $item (@$found_parent) {
            confess "Error: item has no device field ".Dumper($found_parent, $entry)
            if !exists $item->{device} || !defined $item->{device};
            $found = $item->{device} if $item->{device} eq $entry;
        }
    }
    ok($found,"Expecting $entry in ".Dumper($parent)) or exit;
}


sub test_hostdev_gpu_kvm($domain) {
    for my $path (
        # the next one returns XPath error : Undefined namespace prefix
        #"/domain/metadata/libosinfo:libosinfo"
        #,
         "/domain/devices/graphics[\@type='spice']"
        ,"/domain/devices/graphics[\@type='spice']/gl"
        ,"/domain/devices/graphics[\@type='egl-headless']"
        ,"/domain/devices/hostdev[\@model='vfio-pci']"
        ,"/domain/qemu:commandline"
    ) {
        test_domain_path_kvm($domain, $path);
    }
}

sub test_hostdev_gpu_void($domain) {
    for my $path (
        "/hardware/host_devices/graphics" ) {
        test_domain_path_void($domain, $path);
    }
}

sub test_hostdev_gpu($domain) {
    if ($domain->type eq 'KVM') {
        test_hostdev_gpu_kvm($domain);
    } elsif ($domain->type eq 'Void') {
        test_hostdev_gpu_void($domain);
    }
}

sub test_host_device_gpu($vm) {
    return if $vm->type eq 'KVM' && ! -e "/dev/dri";
    my $n_devices = 3;
    my ($list_command,$list_filter) = _create_mock_devices( $n_devices, "GPU" , "0000:00:02." );

    _insert_hostdev_data_gpu($vm, "GPU Mock", $list_command, $list_filter);

    my @list_hostdev = $vm->list_host_devices();

    my $base = create_domain($vm);
    $base->add_host_device($list_hostdev[0]);
    eval { $base->start(user_admin) };
    if ($@ =~ /No DRM render nodes available/) {
        diag("skip: ".$vm->type." GPU : $@");

        $list_hostdev[0]->remove();
        remove_domain($base);
        return
    }
    like ($@,qr{^($|.*Unable to stat|.*device not found.*mediated)} , $base->name) or exit;

    test_hostdev_gpu($base);

    diag("Remove host device ".$list_hostdev[0]->name);
    $list_hostdev[0]->remove();
    remove_domain($base);
}

sub test_xmlns($vm) {
    return if $vm->type ne 'KVM';
    my ($list_command,$list_filter) = _create_mock_devices( 1, "GPU" , "0000:00:02." );

    _insert_hostdev_data_xmlns($vm, "GPU Mock", $list_command, $list_filter);

    my @list_hostdev = $vm->list_host_devices();

    my $base = create_domain($vm);
    $base->add_host_device($list_hostdev[0]);
    eval { $base->start(user_admin) };
    like ($@,qr{^($|.*Unable to stat|.*device not found.*mediated|.*there is no device "hostdev)} , $base->name) or exit;

    my $doc = XML::LibXML->load_xml( string => $base->domain->get_xml_description);
    my ($domain_xml) = $doc->findnodes("/domain");

    my ($xmlns) = $domain_xml =~ m{xmlns:qemu=["'](.*?)["']}m;
    my ($line1) = $domain_xml =~ m{(<domain.*)}m;
    ok($xmlns,"Expecting xmlns:qemu namespace in ".$line1) or exit;
    is($xmlns, "http://libvirt.org/schemas/domain/qemu/1.0") or exit;

    $list_hostdev[0]->remove();
    remove_domain($base);

}

sub test_check_list_command($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    $vm->add_host_device(template => $templates->[0]->{name});

    my ($hdev) = $vm->list_host_devices();
    my $lc_orig = $hdev->list_command();
    is($hdev->_data('list_command'), $lc_orig) or exit;

    for my $before ('','before ') {
        for my $char (qw(" ' ` $ ( ) [ ] ; )) {
            eval { $hdev->_data('list_command' => $before.$char) };
            like($@, qr'.');
            is($hdev->list_command, $lc_orig);
            is($hdev->_data('list_command'), $lc_orig);
        }
    }

    for my $something ('lssomething' , 'findsomething') {
        $hdev->_data('list_command' => $something);
        is($hdev->list_command, $something);
        is($hdev->_data('list_command'), $something);
    }

    $hdev->remove();
}

sub test_invalid_param {
    eval {
        rvd_front->update_host_device({ id => 1, 'list_command' => 'a' });
    };
    is($@,'');
    for my $wrong ( qr(` ' % ; ) ) {
        eval {
            rvd_front->update_host_device({id => 1, 'list_command'.$wrong => 'a'});
        };
        like($@,qr/invalid/);
    }
    wait_request(check_error => 0);
}

#########################################################

init();
clean();

test_invalid_param();
for my $vm_name (vm_names()) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        test_check_list_command($vm);

        test_host_device_usb($vm);

        test_xmlns($vm);
        test_host_device_gpu($vm);

        test_host_device_usb_mock($vm);
        test_host_device_usb_mock($vm,2);

    }
}

end();
done_testing();
