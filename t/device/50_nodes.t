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

    test_assign($vm, $node, $hd, $n_local, $n_node);

    _clean_devices($vm, $node);
}

sub test_assign($vm, $node, $hd, $n_expected_in_vm, $n_expected_in_node) {
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

    wait_request();
    my $found_in_node=0;
    my $found_in_vm=0;
    my %dupe;
    for ($hd->list_devices_nodes) {
        my $name = new_domain_name;
        my $req = Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $base->id
            ,name => $name
            ,start => 1
        );
        wait_request( check_error => 0);
        my $domain = rvd_back->search_domain($name);
        $domain->_data('status','active');
        is($domain->is_active,1) if $vm->type eq 'Void';
        my $hd = check_host_device($domain);
        push(@{$dupe{$hd}},($base->name." ".$base->id));
        is(scalar(@{$dupe{$hd}}),1) or die Dumper(\%dupe);
        $found_in_node++ if $domain->_data('id_vm')==$node->id;
        $found_in_vm++ if $domain->_data('id_vm')==$vm->id;
    }
    ok($found_in_node,"Expecting in node, found $found_in_node");
    ok($found_in_vm,"Expecting in node, found $found_in_vm");
    diag("In node: $found_in_node, in vm: $found_in_vm");
    is($found_in_node, $n_expected_in_node);
    is($found_in_vm, $n_expected_in_vm);

    test_clone_nohd($base);

    remove_domain($base2, $base);
}

sub test_clone_nohd($base) {
    my $name = new_domain_name();
    my $req0 = Ravada::Request->clone(
        uid => user_admin->id
        ,id_domain => $base->id
        ,name => $name
        ,start => 0
    );
    wait_request();
    my $domain0 = rvd_back->search_domain($name);
    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain0->id
    );

    wait_request( check_error => 0);
    like($req->error,qr/host devices/i) or exit;
    Ravada::Request->refresh_machine(uid => user_admin->id, id_domain => $domain0->id);

    my $domain = rvd_back->search_domain($name);
    is($domain->is_active,0);

    my $req2 = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain0->id
        ,enable_host_devices => 0
    );

    wait_request( check_error => 0);

    my $domain2 = rvd_back->search_domain($name);
    is($domain2->is_active,1);

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
    my $ret='';
    for my $key (sort keys %{$hostdev[0]}) {
        $ret .= "$key: ".$hostdev[0]->{$key};
    }
    return $ret;
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

for my $vm_name (reverse vm_names() ) {
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

        test_devices($vm, $node,2,2);
        test_devices($vm, $node,3,1);
        test_devices($vm, $node,1,3);

        clean_remote_node($node);

    }
}

end();
done_testing();
