use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user('foo','bar');
my $TIMEOUT_SHUTDOWN = 10;

################################################################


sub test_create_domain_xml {
    my $vm_name = shift;
    my $file_xml = shift;

    my $name = new_domain_name();

    die "Missing '$file_xml'" if !-e $file_xml;
    my $vm = rvd_back->search_vm($vm_name);

    my $device_disk = $vm->create_volume(
        name => $name
        ,size => 1024 * 1024
        ,xml => "etc/xml/dsl-volume.xml");
    ok($device_disk,"Expecting a device disk") or return;
    ok(-e $device_disk);


    my $xml = $vm->_define_xml($name, $file_xml);
    my @nodes;
    for my $device ( qw(image jpeg zlib playback streaming)) {
        my $path = "/domain/devices/graphics/$device";
        my ($node) = $xml->findnodes($path);
        is($node,undef,"Expecting no node $path");
        push @nodes, ( $node ) if $node;
    }
    return if @nodes;
    Ravada::VM::KVM::_xml_modify_disk($xml,[$device_disk]);
    my $dom;
    eval { $dom = $vm->vm->define_domain($xml) };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'") or return
    ok($dom,"Expecting a VM defined from $file_xml") or return;

    my $domain = Ravada::Domain::KVM->new(domain => $dom, _vm => $vm);
    $domain->_insert_db(name=> $name, id_owner => $USER->id);
    $domain->xml_description;

    return $domain;
}

sub test_drivers_type {
    my $vm_name = shift;
    my $file_xml = shift;
    my $type = shift;

    my $domain = test_create_domain_xml($vm_name, $file_xml) or return;

    my $vm = rvd_back->search_vm($vm_name);

    my @drivers = $domain->drivers();
    ok(scalar @drivers,"Expecting defined drivers");
    isa_ok(\@drivers,'ARRAY');

    my $driver_type = $domain->drivers($type);
    ok($driver_type,"[$vm_name] Expecting a driver type $type") or return;
    isa_ok($driver_type, "Ravada::Domain::Driver") or return;

    my $value = $driver_type->get_value();
    is($value,undef,"Expecting no value for $type");

    $value = $domain->get_driver($type);
    is($value,undef,"Expecting no value for $type");

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    for my $option (@options) {
        _domain_shutdown($domain);

#        diag("Setting $type $option->{value}");

        die "No value for driver ".Dumper($option)  if !$option->{value};
        eval { $domain->set_driver($type => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));
        is($domain->get_driver($type), $option->{value}) or next;

        _domain_shutdown($domain),
        is($domain->get_driver($type), $option->{value}) or next;

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});
        }
        $domain->start($USER)   if !$domain->is_active;

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});

        }

    }
    $domain->remove($USER);
}

sub _domain_shutdown {
    my $domain = shift;
    $domain->shutdown_now($USER) if $domain->is_active;
    for ( 1 .. $TIMEOUT_SHUTDOWN) {
        last if !$domain->is_active;
        sleep 1;
    }
}

sub test_settings {
    my ($vm_name, $file_xml) = @_;
    for my $driver (qw(image jpeg zlib playback streaming)) {
        test_drivers_type($vm_name, $file_xml, $driver);
    }
}

################################################################

remove_old_domains();
remove_old_disks();

my $vm_name = 'KVM';
my $vm;
eval { $vm =rvd_back->search_vm($vm_name) } if !$<;
SKIP: {
    my $msg = "SKIPPED test: No $vm_name backend found"
                ." error: (".($@ or '').")";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok('Ravada::Domain::KVM');
    test_settings($vm_name, qemu_fix_xml_file("t/kvm/etc/winxp.xml"));
};

end();
done_testing();

