use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

my $VOL_NAME = new_domain_name();
my $XML_VOL =
"<volume>
  <name>$VOL_NAME.raw</name>
  <capacity>10485760</capacity>
  <target>
    <format type='raw'/>
  </target>
</volume>";

use_ok('Ravada');

init();

#####################################################################

sub test_domain_raw {
    my $vm = shift;


    my $domain = create_domain($vm->type);
    _set_raw_volume($domain);

    my $clone = $domain->clone(
         user => user_admin
        ,name => new_domain_name
    );

    {
    my $disk = _search_disk($clone);
    ok($disk) or return;

    my ($driver) = $disk->findnodes('./driver');
    ok($driver->getAttribute('type') eq 'qcow2');

    my ($source) = $disk->findnodes('./source');
    my $file = $source->getAttribute('file');
    like($file , qr(qcow2)) or exit;

    my $file_type = `file $file`;
    chomp $file_type;
    like($file_type, qr(.*: QEMU QCOW)i);
    }

    $clone->remove(user_admin);

    $domain->remove_base(user_admin);

    {
    my $disk = _search_disk($domain);
    ok($disk) or return;

    my ($driver) = $disk->findnodes('./driver');
    is($driver->getAttribute('type'),'qcow2');

    my ($source) = $disk->findnodes('./source');
    my $file = $source->getAttribute('file');
    like($file , qr(raw$)) or exit;

    my $file_type = `file $file`;
    chomp $file_type;
    like($file_type, qr(.*: QEMU QCOW)i);
    }
}

sub _search_disk {
    my $clone = shift;

    my $doc_clone = XML::LibXML->load_xml(string => $clone->domain->get_xml_description());
    for my $disk ( $doc_clone->findnodes("/domain/devices/disk") ) {
        return $disk if $disk->getAttribute('device') eq 'disk';
    }
    return;
}

sub _set_raw_volume {
    my $domain = shift;

    my ($pool) = $domain->_vm->vm->list_storage_pools();
    my $vol = $pool->create_volume($XML_VOL);

    my $file = $vol->get_path;
    my $file_type = `file $file`;
    chomp $file_type;
    like($file_type, qr(.*: data)i);


    my $doc = XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my $disk_found = 0;

    for my $device ( $doc->findnodes("/domain/devices") ) {
        for my $disk ($device->findnodes("./disk")) {
            if ($disk->getAttribute('device') eq 'disk') {
                my ($driver) = $disk->findnodes("./driver");
                $driver->setAttribute(type => 'raw');
                my ($source) = $disk->findnodes("./source");
                $source->setAttribute(file => $vol->get_path);
                $disk_found++;
                next;
            }
            $device->removeChild($disk) if $disk->getAttribute('device') eq 'cdrom';
        }
    }

    is($disk_found,1);

    my $new_domain = $domain->_vm->vm->define_domain($doc->toString);
    $domain->domain($new_domain);

    ok(grep /\.raw$/,$domain->list_volumes) or exit;
}

#####################################################################

clean();

for my $vm_name ('KVM') {
    SKIP: {

        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        test_domain_raw($vm);
    }
}

end();

done_testing();
