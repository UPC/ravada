use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Path qw(make_path);
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json encode_json);
use Ravada::HostDevice::Templates;
use Test::More;
use YAML qw( Dump );

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $N_DEVICE = 0;

my $PATH = "/var/tmp/$</ravada/dev";

#########################################################

sub _create_mock_devices_void($vm, $n_devices, $type, $value="fff:fff") {
    $vm->run_command("mkdir","-p",$PATH) if !$vm->file_exists($PATH);

    my $name = base_domain_name()."_${type} ID";

    for my $n ( 1 .. $n_devices ) {
        my $file= "$PATH/${name} $N_DEVICE$value${n} Foobar "
            .$vm->name;
        $vm->write_file($file,"fff6f017-3417-4ad3-b05e-17ae3e1a461".int(rand(10)));
    }
    $N_DEVICE ++;

    return ("find $PATH/",$name);
}

sub _number($value, $length=3) {
    my $dev = $value;
    for ( length($dev) .. $length-1) {
        $dev .= int(rand(10));
    }
    return $dev;
}

sub _hex($value, $length=4) {
    my $hex=$value;
    for ( length($hex) .. $length-1) {
        $hex .= chr(ord('a')+int(rand(7)));
    }
    return $hex;
}
sub _create_mock_devices_kvm($vm, $n_devices, $type, $value="fff:fff") {
    $vm->run_command("mkdir","-p",$PATH) if !$vm->file_exists($PATH);

    my $name = base_domain_name()."_${type}_KVM ";
    for my $n ( 1 .. $n_devices ) {
        my $dev = _number($N_DEVICE.$n);
        my $bus = _number($N_DEVICE.$n);
        my $vendor = _hex($N_DEVICE.$n);
        my $id = _hex($N_DEVICE.$n);

        my $file= "$PATH/${name} ".$vm->name
        ." Bus $bus Device $dev: ID $vendor:$id";

        diag($file);
        $vm->write_file($file,"fff6f017-3417-4ad3-b05e-17ae3e1a461".int(rand(10)));
    }
    $N_DEVICE ++;

    return ("find $PATH/",$name);


}

sub _create_mock_devices($vm, $n_devices, $type, $value="fff:fff") {
    if ($vm->type eq 'KVM') {
       return _create_mock_devices_kvm($vm, $n_devices, $type, $value );
    } elsif ($vm->type eq 'Void') {
       return _create_mock_devices_void($vm, $n_devices, $type, $value );
    }
}

sub test_devices($vm, $node, $n_local=3, $n_node=3) {

    _clean_devices($vm, $node);
    my ($list_command,$list_filter) = _create_mock_devices($vm, $n_local , "USB" );
    my ($list_command2,$list_filter2) = _create_mock_devices($node, $n_node , "USB" );

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    my ($first) = $templates->[0];

    $vm->add_host_device(template => $first->{name});
    my @list_hostdev = $vm->list_host_devices();
    my ($hd) = $list_hostdev[-1];
    $hd->_data('list_command',$list_command);
    $hd->_data('list_filter',$list_filter);

    my $vm_name = $vm->name;
    my $node_name = $node->name;

    my @devices = $hd->list_devices;
    ok(grep /$vm_name/,@devices);
    ok(!grep /$node_name/,@devices);

    test_assign($vm, $node, $hd);

    _clean_devices($vm, $node);
}

sub test_assign($vm, $node, $hd) {
    my $base = create_domain($vm);
    $base->add_host_device($hd);
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $base->id
        ,name => 'usb controller'
    );
    $base->prepare_base(user_admin);
    $base->set_base_vm(id_vm => $node->id, user => user_admin);

    my $base2 = create_domain($vm);
    $base2->add_host_device($hd);
    $base2->prepare_base(user_admin);
    $base2->set_base_vm(id_vm => $node->id, user => user_admin);

    my $req = Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $base->id
            ,number => scalar($hd->list_devices_nodes)
    );
    wait_request();
    is(scalar($base->clones),scalar($hd->list_devices_nodes));
    my $found_in_node=0;
    my $found_in_vm=0;
    my %dupe;
    for my $clone0 ($base->clones) {
        diag($clone0->{id}." ".$clone0->{name});
        my $req = Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $clone0->{id}
        );
        wait_request( check_error => 0);
        my $domain = Ravada::Domain->open($clone0->{id});
        $domain->_data('status','active');
        diag($req->error);
        is($domain->is_active,1) if $vm->type eq 'Void';
        my $hd = check_host_device($domain);
        push(@{$dupe{$hd}},($clone0->{name}." ".$clone0->{id}));
        is(scalar(@{$dupe{$hd}}),1) or die Dumper(\%dupe);
        $found_in_node++ if $domain->_data('id_vm')==$node->id;
        $found_in_vm++ if $domain->_data('id_vm')==$vm->id;
    }
    ok($found_in_node,"Expecting in node, found $found_in_node");
    ok($found_in_vm,"Expecting in node, found $found_in_vm");
    diag("In node: $found_in_node, in vm: $found_in_vm");

    remove_domain($base2, $base);
}

sub check_host_device($domain) {
    my $sth = connector->dbh->prepare("SELECT * FROM host_devices_domain_locked "
        ." WHERE id_domain=?");
    $sth->execute($domain->id);
    my $found = $sth->fetchrow_hashref;
    ok($found);
    if ($domain->type eq 'Void') {
        return check_host_device_void($domain);
    } else {
        return check_host_device_kvm($domain);
    }
}

sub check_host_device_void($domain) {
    my $doc = $domain->_load();
    my @hostdev;
    for my $dev ( @{ $doc->{hardware}->{host_devices} } ) {
        push @hostdev,($dev);
        for my $item ( keys %$dev ) {
            like($item,qr/^\w+$/);
            like($dev->{$item}, qr(^[0-9a-z]+$)) or die Dumper($dev);
        }
    }

    is(scalar(@hostdev),1) or do {
        my $vm = Ravada::VM->open($domain->_data('id_vm'));
        die $domain->name." ".$vm->name;
    };
    return ($hostdev[1] or undef);
}

sub check_host_device_kvm($domain) {
    my $doc = $domain->xml_description();
    my $xml = XML::LibXML->load_xml(string => $doc);
    my ($hd_source) = $xml->findnodes("/domain/devices/hostdev/source");
    ok($hd_source) or return;
    my ($vendor) = $hd_source->findnodes("vendor");
    my $vendor_id=$vendor->getAttribute('id');
    my ($product) = $hd_source->findnodes("product");
    my $product_id=$product->getAttribute('id');
    my ($address) = $hd_source->findnodes("address");

    return "$vendor_id-$product_id-".$address->getAttribute('bus')."-"
    .$address->getAttribute('device');

}

sub _clean_devices(@nodes) {
    my $base = base_domain_name();
    for my $vm (@nodes) {
        next if !defined $vm;
        $vm->run_command("mkdir","-p",$PATH) if !$vm->file_exists($PATH);
        my ($out, $err) = $vm->run_command("ls",$PATH);
        for my $line ( split /\n/,$out ) {
            next if $line !~ /$base/;
            diag($line);
            if ($vm->is_local) {
                unlink "$PATH/$line" or die "$! $PATH/$line";
                next;
            }
            my ($out, $err) = $vm->run_command("rm","'$PATH/$line'");
            die $err if $err;
        }
    }
}
#########################################################

init();
clean();

for my $vm_name ( vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        my $node = remote_node($vm_name)  or next;
        clean_remote_node($node);

        test_devices($vm, $node);
        test_devices($vm, $node, 5,1);
        test_devices($vm, $node, 1,5);
        exit;
    }
}

end();
done_testing();
