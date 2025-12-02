use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user('foo','bar');

sub test_create_domain_xml {
    my $name = new_domain_name();
    my $file_xml = shift;

    die "Missing '$file_xml'" if !-e $file_xml;
    my $vm = rvd_back->search_vm('KVM');

    my $device_disk = $vm->create_volume(
        name => $name
        ,size => 1024 * 1024
        ,xml => "etc/xml/dsl-volume.xml");
    ok($device_disk,"Expecting a device disk") or return;
    ok(-e $device_disk);

    open my $fh,'<', $file_xml or die "$! $file_xml";
    binmode $fh;
    my $xml_origin = XML::LibXML->load_xml( IO => $fh);
    close $fh;

    my @controller = $xml_origin->findnodes('/domain/devices/controller');
    is(scalar @controller,7,$file_xml) or exit;

    my $xml = $vm->_define_xml($name, $file_xml);
    my @controller2 = $xml->findnodes('/domain/devices/controller');
    is (scalar @controller, scalar @controller2) or exit;

    Ravada::VM::KVM::_xml_modify_disk($xml,[$device_disk]);
#    $vm->_xml_modify_usb($xml);
#    $vm->_fix_pci_slots($xml);

    my $dom;
    eval { $dom = $vm->vm->define_domain($xml) };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'") or return
    ok($dom,"Expecting a VM defined from $file_xml") or return;

    eval{ $dom->create };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'");

    my $domain = Ravada::Domain::KVM->new(domain => $dom
                , storage => $vm->storage_pool
                , _vm => $vm
    );

    $domain->_insert_db(name => $name, id_owner => $USER->id);

    my $xml_base  = XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my @controller_base = $xml_base->findnodes('/domain/devices/controller');

    is (scalar @controller, scalar @controller_base) or exit;
    return $name;
}

sub dump_controllers {
    my ($controller1, $controller2) = @_;

    my (%controller1, %controller2);
    for (@$controller1)  {
        my $type = $_->getAttribute('type');
        my $model = ($_->getAttribute('model') or '');
        $controller1{"$type-$model"} = $_->toString();
    }
    for (@$controller2)  {
        my $type = $_->getAttribute('type');
        my $model = ($_->getAttribute('model') or '');
        $controller2{"$type-$model"} = $_->toString();
    }
    for (keys %controller1) {
        warn $controller1{$_}
            if !exists $controller2{$_};
    }

    for (keys %controller2) {
        warn $controller2{$_}
            if !exists $controller1{$_};
    }


    exit;
}

sub test_clone_domain {
    my $name = shift;
    my $file_xml = shift;

    my $vm = rvd_back->search_vm('KVM');
    my $domain = $vm->search_domain($name);

    my $clone_name = new_domain_name();
    my $clone;
    $domain->shutdown_now($USER)    if $domain->is_active;
    $domain->is_public(1);
    eval {$clone = $domain->clone(name => $clone_name, user => user_admin ) };

    ok(!$@,"Expecting error:'' , got '".($@ or '')."'") or exit;


    open my $fh,'<', $file_xml or die "$! $file_xml";
    binmode $fh;
    my $xml = XML::LibXML->load_xml( IO => $fh);
    close $fh;

    my $xml_base  = XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my $xml_clone = XML::LibXML->load_xml(string => $clone->domain->get_xml_description());

    my @controller = $xml->findnodes('/domain/devices/controller');
    my @controller_base = $xml_base->findnodes('/domain/devices/controller');
    my @controller_clone = $xml_clone->findnodes('/domain/devices/controller');

    is (scalar @controller_base, scalar @controller)
        or dump_controllers(\@controller, \@controller_base);
    is (scalar @controller_base, scalar @controller_clone) or exit;

    for my $n ( 0 .. scalar @controller_base - 1) {
        ok(defined $controller_base[$n],"Expecting device controller $n") or next;
        ok(defined $controller_clone[$n],"Expecting device controller in clone $n "
            .$controller_base[$n]->toString) or exit;
        is($controller_clone[$n]->toString, $controller_base[$n]->toString) or last;
    }

    eval {$clone->start(user_admin) };
    ok(!$@,"Expecting error:'' , got '".($@ or '')."'") or exit;

}

################################################################

remove_old_domains();
remove_old_disks();

my $vm;
eval { $vm = rvd_back->search_vm('KVM') } if !$<;
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    if ($vm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    for my $xml ('t/kvm/etc/winxp.xml') {
        my $fixed_xml = qemu_fix_xml_file($xml);
        my $name = test_create_domain_xml($fixed_xml);
        next if !$name;
        test_clone_domain($name, $fixed_xml);
    }


};
end();
done_testing();
