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

sub test_devices_v2($node, $number) {
    _clean_devices(@$node);
    my $vm = $node->[0];
    my ($list_command,$list_filter) = _create_mock_devices($node->[0], $number->[0], "USB" );
    for my $i (1..scalar(@$node)-1) {
        die "Error, missing number[$i] ".Dumper($number) unless defined $number->[$i];
        _create_mock_devices($node->[$i], $number->[$i], "USB" );
    }
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    my ($first) = $templates->[0];

    $vm->add_host_device(template => $first->{name});
    my @list_hostdev = $vm->list_host_devices();
    my ($hd) = $list_hostdev[-1];
    $hd->_data('list_command',$list_command);
    $hd->_data('list_filter',$list_filter);

    my %devices_nodes = $hd->list_devices_nodes();

    test_assign_v2($hd,$node,$number);

    _clean_devices(@$node);
    $hd->remove();
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

    my %devices_nodes = $hd->list_devices_nodes();
    warn Dumper(\%devices_nodes);
    my %dupe;
    for my $node (keys %devices_nodes) {
        for my $dev (@{$devices_nodes{$node}}) {
            $dupe{$dev}++;
        }
    }
    warn Dumper(\%dupe);
    is(scalar(keys %dupe), $n_local+ $n_node);
    for my $dev (keys %dupe) {
        is($dupe{$dev},1);
    }

    test_assign($vm, $node, $hd, $n_local, $n_node);

    _clean_devices($vm, $node);

    $hd->remove();
}

sub test_assign_v2($hd, $node, $number) {
    my $vm = $node->[0];
    my $base = create_domain($vm);
    $base->add_host_device($hd);
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $base->id
        ,name => 'usb controller'
    );
    $base->prepare_base(user_admin);
    for my $curr_node (@$node) {
        $base->set_base_vm(id_vm => $curr_node->id, user => user_admin);
    }

    wait_request();
    my %found;
    my %dupe;
    my $n_expected = 0;
    map { $n_expected+= $_ } @$number;

    my %devices_nodes = $hd->list_devices_nodes();
    for my $n (1 .. $n_expected) {
        my $name = new_domain_name;
        my $domain = _req_clone($base, $name);
        $domain->_data('status','active');
        is($domain->is_active,1) if $vm->type eq 'Void';
        check_hd_from_node($domain,\%devices_nodes);
        my $hd = check_host_device($domain);
        push(@{$dupe{$hd}},($base->name." ".$base->id));
        is(scalar(@{$dupe{$hd}}),1) or die Dumper(\%dupe);
        $found{$domain->_data('id_vm')}++;
    }
    test_clone_nohd($hd, $base);
    test_start_in_another_node($hd, $base);

    remove_domain($base);
}

sub test_start_in_another_node($hd, $base) {
    my ($clone1, $clone2);
    for my $clone ($base->clones) {
        next if $clone->{status} ne 'active';
        if (!defined $clone1) {
            $clone1 = $clone;
            next;
        }
        if ($clone->{id_vm} != $clone1->{id_vm}) {
            $clone2 = $clone;
            last;
        }
    }
    die "Error. I couldn't find a clone in each node" unless $clone1 && $clone2;

    _req_shutdown($clone1->{id});
    _req_clone($base);
    _req_shutdown($clone2->{id});

    _list_locked($clone1->{id});
    _force_wrong_lock($clone1->{id_vm},$clone1->{id});
    _req_start($clone1->{id});

    my $clone1b = Ravada::Domain->open($clone1->{id});
    is($clone1b->_data('id_vm'), $clone2->{id_vm});

    my %devices_nodes = $hd->list_devices_nodes();
    check_hd_from_node($clone1b,\%devices_nodes);

    check_host_device($clone1b);
}

sub _force_wrong_lock($id_vm, $id_domain) {
    my $sth = connector->dbh->prepare(
        "INSERT INTO host_devices_domain_locked "
        ." ( id_vm, id_domain, name, time_changed )"
        ." values (?, ?, ?, 0) "
    );
    $sth->execute($id_vm, $id_domain, 'fake');
}

sub _list_locked($id_domain) {
    my $sth = connector->dbh->prepare("SELECT * FROM host_devices_domain_locked WHERE id_domain=?");
    $sth->execute($id_domain);
    while ( my $row = $sth->fetchrow_hashref ) {
        warn Dumper($row);
    }
}

sub _req_shutdown($id) {
    my $sth_locked = connector->dbh->prepare(
        "SELECT * FROM host_devices_domain_locked "
        ." WHERE id_domain=?"
    );
    $sth_locked->execute($id);
    my ($locked) = $sth_locked->fetchrow;
    my $req = Ravada::Request->force_shutdown_domain(
        uid => user_admin->id
        ,id_domain => $id
    );
    wait_request();
    return if !$locked;
    sleep 4;
    $req->status('requested');
    wait_request(debug => 0);
}

sub _req_start($id) {
    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $id
    );
    wait_request();
}


sub _req_clone($base, $name=undef) {
    $name = new_domain_name() if !defined $name;
    my $req = Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $base->id
            ,name => $name
            ,start => 1
    );
    wait_request();

    my $domain = rvd_back->search_domain($name);

    die "Error: $name not created" if !$domain;
    return $domain;
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

    my %devices_nodes = $hd->list_devices_nodes();
    for my $n (1 .. $n_expected_in_vm+$n_expected_in_node) {
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
        check_hd_from_node($domain,\%devices_nodes);
        my $hd = check_host_device($domain);
        push(@{$dupe{$hd}},($base->name." ".$base->id));
        is(scalar(@{$dupe{$hd}}),1) or die Dumper(\%dupe);
        $found_in_node++ if $domain->_data('id_vm')==$node->id;
        $found_in_vm++ if $domain->_data('id_vm')==$vm->id;
    }
    ok($found_in_node,"Expecting in node, found $found_in_node");
    ok($found_in_vm,"Expecting in node, found $found_in_vm");
    is($found_in_node, $n_expected_in_node);
    is($found_in_vm, $n_expected_in_vm);

    test_clone_nohd($hd, $base);

    remove_domain($base2, $base);
}

sub check_hd_from_node($domain, $devices_node) {
    my $id_vm = $domain->_data('id_vm');
    is($domain->_vm->id,$id_vm);

    my @devices = $domain->list_host_devices_attached();
    my @locked = grep { $_->{is_locked} } @devices;

    ok(@locked) or return;
    is(scalar(@locked),1) or die Dumper(\@locked);
    my ($locked) = @locked;

    my $vm = Ravada::VM->open($id_vm);
    diag("Checking ".$domain->name." in node "
        ." [ ".$vm->id." ] ".$vm->name);
    my $devices = $devices_node->{$vm->id};

    my ($match) = grep { $_ eq $locked->{name} } @$devices;
    ok($match,"Expecting $locked->{name} in ".Dumper($devices)) or confess;
}

sub test_clone_nohd($hd, $base) {

    my ($clone_hd) = $base->clones;

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

    _req_shutdown($domain2->id);
    _req_shutdown($clone_hd->{id});

    _check_no_hd_locked($domain2->id);
    _check_no_hd_locked($clone_hd->{id});

    wait_request();

    _req_start($domain0->id);

    my $domain2b = rvd_back->search_domain($name);
    is($domain2b->is_active,1);
    check_host_device($domain2b);

    my %devices_nodes = $hd->list_devices_nodes();
    check_hd_from_node($domain2b,\%devices_nodes);
}

sub _check_no_hd_locked($id_domain) {
    my $sth = connector->dbh->prepare(
        "SELECT * FROM host_devices_domain_locked "
        ." WHERE id_domain=?"
    );
    $sth->execute($id_domain);
    my $row = $sth->fetchrow_hashref;
    ok(!$row) or die Dumper($row);
}

sub check_host_device($domain) {
    my $sth = connector->dbh->prepare("SELECT * FROM host_devices_domain_locked "
        ." WHERE id_domain=?");
    $sth->execute($domain->id);
    my @found;
    while ( my $row = $sth->fetchrow_hashref) {
        push @found,($row);
    }
    is(scalar(@found),1) or confess "Domain ".$domain->name." should have 1 HD locked\n".Dumper(\@found);
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

        my ($node1, $node2) = remote_node_2($vm_name);
        test_devices_v2([$vm,$node1,$node2],[1,1,1]);
        test_devices_v2([$vm,$node1,$node2],[2,2,2]);
        test_devices_v2([$vm,$node1,$node2],[6,6,6]);
        test_devices_v2([$vm,$node1,$node2],[6,1,1]);
        test_devices_v2([$vm,$node1,$node2],[1,6,1]);
        test_devices_v2([$vm,$node1,$node2],[1,1,6]);

        test_devices($vm, $node,2,2);
        test_devices($vm, $node,3,1);
        test_devices($vm, $node,1,3);
        test_devices($vm, $node,6,5);
        test_devices($vm, $node,8,7);
        test_devices($vm, $node,1,7);
        test_devices($vm, $node,7,1);

        clean_remote_node($node);

    }
}

end();
done_testing();
