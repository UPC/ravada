use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json);
use Ravada::Request;
use Ravada::WebSocket;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada::HostDevice::Templates');

$Ravada::Domain::TTL_REMOVE_VOLATILE=3;

####################################################################

sub _set_hd_nvidia($hd) {
    $hd->_data( list_command => 'lspci -Dnn');
    $hd->_data( list_filter => config_host_devices('pci') );
}

sub _set_hd_usb($hd) {
    $hd->_data( list_filter => config_host_devices('usb'));
}

sub test_hostdev_not_in_domain_void($domain) {
    my $config = $domain->_load();
    if (exists $config->{hardware}->{host_devices}) {
        is_deeply( $config->{hardware}->{host_devices}, []) or confess Dumper($domain->name, $config->{hardware}->{host_devices});
    } else {
        ok(1); # ok if it doesn't exist
    }
}

sub test_hostdev_not_in_domain_kvm($domain) {
    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);

    my ($feat_kvm) = $xml->findnodes("/demain/features/kvm");
    ok(!$feat_kvm) or die $feat_kvm->toString();

    my ($hostdev) = $xml->findnodes("/domain/devices/hostdev");
    ok(!$hostdev,"Expecting no <hostdev> in ".$domain->name) or confess;

}

sub test_hostdev_not_in_domain_config($domain) {
    if ($domain->type eq 'Void') {
        test_hostdev_not_in_domain_void($domain);
    } elsif ($domain->type eq 'KVM') {
        test_hostdev_not_in_domain_kvm($domain);
    } else {
        confess "TODO";
    }
}

sub test_hostdev_in_domain_void($domain) {
    my $config = $domain->_load();
    ok(exists $config->{hardware}->{host_devices}) or confess $domain->name;
    ok(scalar(@{ $config->{hardware}->{host_devices}})) or die "Expecting host_devices"
        ." in ".Dumper($config->{hardware});
}

sub test_hostdev_in_domain_kvm($domain, $expect_feat_kvm=1) {
    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);

    if ($expect_feat_kvm) {
        my ($feat) = $xml->findnodes("/domain/features");
        my ($feat_kvm) = $xml->findnodes("/domain/features/kvm");
        ok($feat_kvm) or confess "Error, no /domain/features/kvm in ".$domain->name
        .$feat->toString;
    }

    my ($hostdev) = $xml->findnodes("/domain/devices/hostdev");
    ok($hostdev,"Expecting no <hostdev> in ".$domain->name) or confess;
}

sub test_hostdev_in_domain_config($domain, $expect_feat_kvm) {
    if ($domain->type eq 'Void') {
        test_hostdev_in_domain_void($domain);
    } elsif ($domain->type eq 'KVM') {
        test_hostdev_in_domain_kvm($domain, $expect_feat_kvm);
    } else {
        confess "TODO";
    }
}

sub _fix_host_device($hd) {
    if ($hd->{name} =~ /PCI/) {
        _set_hd_nvidia($hd);
    } elsif ($hd->{name} =~ /USB/ ) {
        _set_hd_usb($hd);
    }
    _purge_hd($hd);
}

sub _purge_hd($hd) {
    my $sth = connector->dbh->prepare(
        "DELETE FROM host_devices_domain WHERE id_host_device=? AND id_domain NOT IN (select id FROM domains)"
    );
    $sth->execute($hd->{id});

    $sth = connector->dbh->prepare(
        "DELETE FROM host_devices_domain WHERE id_host_device=? AND id_domain NOT IN (select id FROM domains WHERE status='active')"
    );
    $sth->execute($hd->{id});

    $sth = connector->dbh->prepare(
        "DELETE FROM host_devices_domain_locked WHERE id_domain NOT IN (select id FROM domains WHERE status='active')"
    );
    $sth->execute();

}

sub _create_domain_hd($vm, $hd) {
    my $domain = create_domain($vm);
    $domain->add_host_device($hd);

    return $domain if $vm->type ne 'KVM';

    if ($domain->type eq 'KVM' && $hd->{name} =~ /USB/) {
        _req_add_usb($domain);
    }
   return $domain;
}

sub _req_add_usb($domain) {
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'usb controller'
    );
    wait_request(debug => 0);
}

sub _shutdown_all($vm) {
    for my $dom ($vm->list_domains) {
        $dom->shutdown_now(user_admin);
        $dom->_unlock_host_devices(0);
    }
    my $sth = connector->dbh->prepare("DELETE FROM host_devices_domain_locked");
    $sth->execute();
}

sub test_hd_in_domain($vm , $hd) {

    _shutdown_all($vm);
    my $domain = create_domain($vm);
    if ($vm->type eq 'KVM') {
        if ($hd->{name} =~ /PCI/) {
            _set_hd_nvidia($hd);
            if (!$hd->list_devices) {
                diag("SKIPPED: No devices found ".join(" ",$hd->list_command)." | ".$hd->list_filter);
                remove_domain($domain);
                return;
            }
        } elsif ($hd->{name} =~ /USB/ ) {
            _fix_usb_ports($domain) if $hd->{name} =~ /usb/i && $vm->type =~ /KVM/;
            _set_hd_usb($hd);
        }
    }
    $domain->add_host_device($hd);

    if ($hd->list_devices) {
        $domain->start(user_admin);
        $domain->shutdown_now(user_admin);
    }

    $domain->prepare_base(user_admin);
    _shutdown_all($vm);
    my $n_locked = _count_locked();
    for my $count (reverse 0 .. $hd->list_devices ) {
        my $clone = $domain->clone(name => new_domain_name() ,user => user_admin);
        test_hostdev_not_in_domain_config($clone);
        _compare_hds($domain, $clone);

        test_device_unlocked($clone);
        my $t0 = time;
        if ($hd->list_devices) {
            eval { $clone->start(user_admin) };
            if (!$count) {
                like($@,qr/No available devices/);
                diag($@);
                last;
            }
            is(_count_locked(),++$n_locked) or exit;
            next;
            test_device_locked($clone);
            test_hostdev_in_domain_config($clone, ($hd->name =~ /PCI/ && $vm->type eq 'KVM'));
        }
        sleep(3) if time-$t0<3;

        $clone->shutdown_now(user_admin);
        test_device_unlocked($clone);
        if ($hd->list_devices) {
            eval { $clone->start(user_admin) };
            is(''.$@,'') or exit;
            is(_count_locked(),$n_locked) or exit;
        }
        wait_request();
        $clone->check_status();
        $clone->is_active();

    }
    if ( scalar ($hd->list_devices)<2 ) {
        my $msg
        ="Error: I can't find 2 free devices "
        ." in ".$hd->name
        .Dumper([$hd->list_devices()])
    } else {
        test_grab_free_device($domain) if $hd->list_devices();
    }

    remove_domain($domain);

}

sub _select_clone_up($base) {

    my $sth = connector->dbh->prepare("SELECT id FROM host_devices_domain_locked ");
    $sth->execute();
    while ( my ($id) = $sth->fetchrow) {
        my $clone = Ravada::Domain->open($id);
        next if !$clone->is_active;

        return $clone;
    }

    die "Error: no clone active with host devices locked";
}

sub test_grab_free_device($base) {
    wait_request();
    rvd_back->_cmd_refresh_vms();
    my @clones = $base->clones();

    die "Error: I need 3 clones . I can't try to grab only ".scalar(@clones)
    if scalar(@clones)<3;

    my $up = _select_clone_up($base);
    my ($down) = grep { $_->{status} ne 'active' } @clones;
    ok($down && exists $down->{id}) or die Dumper(\@clones);
    $down = Ravada::Domain->open($down->{id});

    my ($up_dev) = $up->list_host_devices_attached();
    die "Error: no host devices attached to ".$up->name
    if !$up_dev;

    my ($down_dev) = $down->list_host_devices_attached();
    ok($up_dev->{name});
    is($up_dev->{is_locked},1);
    is($down_dev->{name},undef);
    my $expect_feat_kvm = $up_dev->{host_device_name} =~ /PCI/ && $base->type eq 'KVM';
    test_hostdev_in_domain_config($up, $expect_feat_kvm);
    test_hostdev_not_in_domain_config($down);

    $up->shutdown_now(user_admin);
    wait_request();
    sleep 3;
    is($up->is_active,0);
    $up->shutdown_now(user_admin);
    ($up_dev) = $up->list_host_devices_attached();
    is($up_dev->{is_locked},0);

    eval { $down->start(user_admin) };
    is(''.$@,'') or die "Error starting ".$down->name;
    ($down_dev) = $down->list_host_devices_attached();
    ok($down_dev->{name});
    ($up_dev) = $up->list_host_devices_attached();
    is($up_dev->{is_locked},0);
    test_hostdev_not_in_domain_config($up);
    test_hostdev_in_domain_config($down, $expect_feat_kvm);

    eval { $up->start(user_admin) };
    my $err = $@;
    is($up->is_active,0);
    ($up_dev) = $up->list_host_devices_attached();
    is($up_dev->{is_locked},0);
    like($err,qr(.)) or exit;

    #pick a fre device from a third domain we shut it down now
    my ($third) = grep { $_->{status} eq 'active' && $_->{name} ne $up->name } @clones;
    $third = Ravada::Domain->open($third->{id});
    my ($third_dev) = $third->list_host_devices_attached();
    $third->shutdown_now(user_admin);

    eval { $up->start(user_admin) };
    is(''.$@,'') or die "Error starting ".$up->name;

    is($up->is_active,1);
    my ($up_dev2) = $up->list_host_devices_attached();
    is($up_dev2->{is_locked},1);
    is($up_dev2->{name}, $third_dev->{name});

    my ($third_dev_down) = $third->list_host_devices_attached();
    is($third_dev_down->{is_locked},0) or die Dumper($third_dev_down);
    test_hostdev_in_domain_config($up, $expect_feat_kvm);
    test_hostdev_not_in_domain_config($third);

}

sub test_device_locked($clone) {
    my $sth = connector->dbh->prepare("SELECT id_host_device,name FROM host_devices_domain WHERE id_domain=?");
    $sth->execute($clone->id);

    my $sth_locked= connector->dbh->prepare("SELECT * FROM host_devices_domain_locked "
        ." WHERE id_domain=? AND name=?");
    while ( my ($id_hd, $name) = $sth->fetchrow ) {
        ok($name,"Expecting host device name in host_devices_domain for id_domain=".$clone->id)
            or next;

        $sth_locked->execute($clone->id, $name);
        my $row_locked = $sth_locked->fetchrow_hashref();

        ok($row_locked->{id},"Expecting locked=1 $name") or exit;
        my $hd = Ravada::HostDevice->search_by_id($id_hd);
        my @available= $hd->list_available_devices();
        my ($found) = grep { $_ eq $name } @available;
        ok(!$found) or die Dumper($name,\@available);
    }
}

sub test_device_unlocked($clone) {
    my $sth = connector->dbh->prepare("SELECT id_host_device,id_domain,name FROM host_devices_domain WHERE id_domain=?");
    $sth->execute($clone->id);

    my $sth_locked= connector->dbh->prepare("SELECT * FROM host_devices_domain_locked "
        ." WHERE id_domain=? AND name=?");
    while ( my ($id_hd, $id_domain, $name) = $sth->fetchrow ) {
        next if !$name;

        $sth_locked->execute($id_domain, $name);
        my $row = $sth_locked->fetchrow_hashref;
        ok(!$row) or die Dumper($row);

        my $hd = Ravada::HostDevice->search_by_id($id_hd);
        my @available= $hd->list_available_devices();
        my ($found) = grep { $_ eq $name } @available;
        ok($found) or die Dumper($name,\@available);
    }
}


sub _compare_hds($base, $clone) {
    my @hds_base;
    my $sth = connector->dbh->prepare("SELECT id_host_device FROM host_devices_domain WHERE id_domain=?");
    $sth->execute($base->id);
    while ( my ($name) = $sth->fetchrow ) {
        push @hds_base,($name);
    }
    is(scalar(@hds_base),1);
    my @hds_clone;
    $sth = connector->dbh->prepare("SELECT id_host_device FROM host_devices_domain WHERE id_domain=?");
    $sth->execute($clone->id);
    while ( my ($name) = $sth->fetchrow ) {
        push @hds_clone,($name);
    }
    is_deeply(\@hds_clone,\@hds_base) or exit;

}

sub _count_locked() {
    my $n=0;
    my $sth = connector->dbh->prepare("SELECT * FROM host_devices_domain_locked ORDER BY id_domain, name");
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        $n++;
    }
    return $n;
}

sub _fix_usb_ports($domain) {
    my $info = $domain->info(user_admin);

    return if !exists $info->{hardware}->{usb};

    my @usb_ports = @{$info->{hardware}->{usb}};
    return if scalar(@usb_ports)<4;

    my $req = Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'usb'
        ,index => 3
    );
    wait_request(debug => 0);
}

sub test_templates_start_nohd($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        $vm->add_host_device(template => $first->{name});
        my $expect_feat_kvm = $first->{name} =~ /PCI/i;
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];

        next if !config_host_devices($hd->name,0);

        _fix_host_device($hd) if $vm->type eq 'KVM';

        next if !$hd->list_devices;

        my $domain = _create_domain_hd($vm, $hd);
        _fix_usb_ports($domain) if $first->{name} =~ /usb/i && $vm->type =~ /KVM/;
        $domain->start(user_admin);
        test_hostdev_in_domain_config($domain,$expect_feat_kvm);
        my $info = $domain->info(user_admin);
        is($info->{host_devices}->[0]->{is_locked},1);
        $domain->shutdown_now(user_admin);

        my $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $domain->id
            ,enable_host_devices => 0
        );
        wait_request();
        is($req->error, '') or exit;
        test_hostdev_not_in_domain_config($domain);
        $domain->shutdown_now(user_admin);

        $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $domain->id
            ,enable_host_devices => 1
        );
        wait_request();
        is($req->error, '');
        test_hostdev_in_domain_config($domain, $expect_feat_kvm);
        $domain->shutdown_now(user_admin);

        $domain->remove(user_admin);
        $hd->remove();
    }
    for my $hd ( $vm->list_host_devices ) {
        test_hd_remove($vm, $hd);
    }
}

sub test_templates_changed_usb($vm) {
    return if $vm->type ne 'KVM';
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        next if $first->{name} !~ 'USB';
        $vm->add_host_device(template => $first->{name});
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];

        _fix_host_device($hd) if $vm->type eq 'KVM';

        next if !$hd->list_devices;

        my $domain = _create_domain_hd($vm, $hd);
        _fix_usb_ports($domain);
        $domain->start(user_admin);

        is(scalar($hd->list_domains_with_device()),1);
        $domain->shutdown_now(user_admin);
        _mangle_dom_hd($domain);
        my $req = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(check_error => 0, debug => 0);
        my $req2 = Ravada::Request->open($req->id);
        is($req2->status,'done');
        is($req2->error,'');

        $domain->remove(user_admin);
    }

    for my $hd ( $vm->list_host_devices ) {
        test_hd_remove($vm, $hd);
    }

}

sub test_templates_gone_usb_2($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        next if $first->{name} !~ 'USB';
        $vm->add_host_device(template => $first->{name});
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];

        _fix_host_device($hd);

        next if !$hd->list_devices;

        my $domain = _create_domain_hd($vm, $hd);
        _fix_usb_ports($domain);
        my $t0=time;
        $domain->start(user_admin);

        my $dev_config = $domain->_device_already_configured($hd);
        ok($dev_config) or exit;

        is(scalar($hd->list_domains_with_device()),1);
        sleep(3) if time-$t0<3;

        $domain->shutdown_now(user_admin);
        $hd->_data('list_filter',"no match");
        Ravada::Request->list_host_devices(
            uid => user_admin->id
            ,id_host_device => $hd->id
        );
        wait_request();
        my $req = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(check_error => 0, debug => 0);
        my $req2 = Ravada::Request->open($req->id);
        like($req2->error,qr/No available devices/) or exit;

        my $req_no_hd = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $domain->id
            ,enable_host_devices => 0
        );
        wait_request(check_error => 0, debug => 0);
        my $req_no_hd2 = Ravada::Request->open($req_no_hd->id);
        is($req_no_hd2->error,'');
        is($domain->is_active,1);

        test_hostdev_not_in_domain_config($domain);

        $domain->remove(user_admin);
    }

    for my $hd ( $vm->list_host_devices ) {
        test_hd_remove($vm, $hd);
    }
}


sub test_templates_gone_usb($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        next if $first->{name} !~ 'USB';
        $vm->add_host_device(template => $first->{name});
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];

        _fix_host_device($hd) if $vm->type eq 'KVM';

        next if !$hd->list_devices;

        my $domain = _create_domain_hd($vm, $hd);
        _fix_usb_ports($domain);
        $domain->start(user_admin);

        my $dev_config = $domain->_device_already_configured($hd);
        ok($dev_config) or exit;

        is(scalar($hd->list_domains_with_device()),1);
        sleep 3;
        $domain->shutdown_now(user_admin);
        is($domain->_device_already_configured($hd), $dev_config) or exit;

        _mangle_dom_hd($domain);
        $hd->_data('list_filter',"no match");
        my $req = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(check_error => 0, debug => 0);
        my $req2 = Ravada::Request->open($req->id);
        like($req2->error,qr/No available devices/);

        my $req_no_hd = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $domain->id
            ,enable_host_devices => 0
        );
        wait_request(check_error => 0, debug => 0);
        my $req_no_hd2 = Ravada::Request->open($req_no_hd->id);
        is($req_no_hd2->error,'');
        is($domain->is_active,1);

        test_hostdev_not_in_domain_config($domain);

        $domain->remove(user_admin);
    }

    for my $hd ( $vm->list_host_devices ) {
        test_hd_remove($vm, $hd);
    }

}


sub _mangle_dom_hd($domain) {
    if ($domain->type eq 'KVM') {
        _mangle_dom_hd_kvm($domain);
    } elsif ($domain->type eq 'Void') {
        _mangle_dom_hd_void($domain);
    } else {
        confess "I don't know how to mangle ".$domain->type." ".$domain->name;
    }
}

sub _mangle_dom_hd_void($domain) {
    my $config = $domain->_load();
    my $sth = connector->dbh->prepare("SELECT id,name FROM host_devices_domain "
        ." WHERE id_domain=?");
    $sth->execute($domain->id);
    my $new_id = "aaaa";
    my ($id_hd, $device_name) = $sth->fetchrow;
    $device_name =~ s/(.* ID ).*?(:.*)/${1}$new_id$2/;

    $sth = connector->dbh->prepare("UPDATE host_devices_domain set name=?"
        ." WHERE id=?");
    $sth->execute($device_name, $id_hd);

}

sub _mangle_dom_hd_kvm($domain) {
    my ($in, $out,$err);
    run3(['lsusb'], \$in, \$out, \$err);
    my $device=0;
    for my $line (split /\n/, $out) {
        my ($current) = $line =~ /Device (\d+)/;
        $device = $current if $current>$device;
    }
    my $sth = connector->dbh->prepare("SELECT id,name FROM host_devices_domain "
        ." WHERE id_domain=?");
    $sth->execute($domain->id);
    my ($id_hd, $device_name) = $sth->fetchrow;
    $device++;
    $device_name =~ s/(.*Device )\d+(.*)/$1$device$2/;
    $sth = connector->dbh->prepare("UPDATE host_devices_domain set name=?"
        ." WHERE id=?");
    $sth->execute($device_name, $id_hd);
}

sub _create_host_devices($vm, $n) {
    my @hd;
    if ($vm->type eq 'Void') {
        @hd = _create_host_devices_void($vm,$n);
    } elsif ($vm->type eq 'KVM') {
        @hd = _create_host_devices_kvm($vm,$n);
    } else {
        die "Error: I don't know how to create host devices for ".$vm->type;
    }
    wait_request(debug => 0);
    for my $hd (@hd) {
        my $devices_node = $hd->_data('devices_node');
        die unless $devices_node;
        my $data = decode_json($devices_node);
        die unless keys %$data;
    }
    return @hd;
}

sub _create_host_devices_void($vm, $n) {
    my $path  = "/var/tmp/$</ravada/dev";
    my @hds;
    for my $count ( 1 .. $n ) {
        my $hd = _mock_hd($vm , $path);
        push @hds,($hd);
    }
    return @hds;
}

sub _create_host_devices_kvm($vm,$n) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    my ($template) = grep { $_->{list_command} =~ /lspci/ } @$templates;

    if (!config_host_devices($template->{name},0)) {
        ($template) = grep { $_->{list_command} =~ /lsusb/ } @$templates;
    }

    my @hds;
    for ( 1 .. $n ) {
        my $id_hd = $vm->add_host_device(template => $template->{name});
        my $hd = Ravada::HostDevice->search_by_id($id_hd);

        my $config = config_host_devices($template->{name});
        $hd->_data('list_filter' => $config);
        push @hds,($hd);
    }

    return @hds;

}

sub test_frontend_list($vm) {

    my ($hd1, $hd2) = _create_host_devices($vm, 2);

    if (scalar($hd1->list_devices) != scalar($hd2->list_devices)) {
        die "Error: expecting the same count of devices in both mock hds";
    }

    my $domain = _create_domain_hd($vm, $hd1);
    $domain->start(user_admin);

    my $ws_args = {
            channel => '/'.$vm->id
            ,login => user_admin->name
    };
    my $front_devices = Ravada::WebSocket::_list_host_devices(undef,rvd_front(), $ws_args);
    is(scalar(@$front_devices),2) or exit;

    my ($dev_attached) = ($domain->list_host_devices_attached);

    my $found=0;
    my $fd_found;
    for my $fd ( @$front_devices ) {
        next unless $fd->{name} eq $hd1->name;
        $fd_found = $fd;
        my $dn = $fd->{devices_node};
        for my $node (keys %$dn) {
            for my $dev ( @{$dn->{$node}} ) {
                next if !$dev->{domain};
                is($dev->{domain}->{id}, $domain->id,"Expecting ".$domain->name." attached in ".$dev->{name});
                is($dev->{domain}->{device},$dev_attached->{name});
                $found++ if $dev->{domain}->{id} == $domain->id;
            }
        }
    }
    is($found,1,"Expected device '".$hd1->name."' in "
        .$domain->id) or die Dumper($fd_found);

    remove_domain($domain);

    _remove_host_devices($vm);
}

sub _mock_hd($vm, $path) {

    my ($template, $name) = _mock_devices($vm , $path);

    my $id_hd = $vm->add_host_device(template => $template->{name});
    my $hd = Ravada::HostDevice->search_by_id($id_hd);

    $hd->_data(list_command => "ls $path");
    $hd->_data(list_filter => $name);

    return $hd;
}

sub _mock_devices($vm, $path) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    my ($template) = grep { $_->{list_command} eq 'lsusb' } @$templates;

    make_path($path) if !-e $path;

    my $name = base_domain_name()." Mock_device ID";

    opendir my $dir,$path or die "$! $path";
    while ( my $file = readdir $dir ) {
        next if $file !~ /^$name/;
        unlink "$path/$file" or die "$! $path/$file";
    }
    closedir $dir;

    my $n_devices = 3;
    for ( 1 .. $n_devices ) {
        open my $out,">","$path/${name} $_:$_ Foo bar"
            or die $!;
        print $out "fff6f017-3417-4ad3-b05e-17ae3e1a461".int(rand(10));
        close $out;
    }

    return ($template, $name);
}

sub test_templates_change_devices($vm) {
    return if $vm->type ne 'Void';

    my $path  = "/var/tmp/$</ravada/dev";
    my ($template, $name) = _mock_devices($vm, $path);

    $vm->add_host_device(template => $template->{name});
    my ($hostdev) = $vm->list_host_devices();
    $hostdev->_data(list_command => "ls $path");
    $hostdev->_data(list_filter => $name);

    my $domain = _create_domain_hd($vm, $hostdev);
    $domain->start(user_admin);

    is(scalar($hostdev->list_domains_with_device()),1);
    my ($dev_attached) = ($domain->list_host_devices_attached);
    $domain->shutdown_now(user_admin);

    is($hostdev->is_device($dev_attached->{name},$vm->id),1) or exit;

    my $file = "$path/".$dev_attached->{name};
    unlink $file or die "$! $file";

    is($hostdev->is_device($dev_attached->{name}, $vm->id),0) or exit;

    $domain->start(user_admin);
    my ($dev_attached2) = ($domain->list_host_devices_attached);
    isnt($dev_attached2->{name}, $dev_attached->{name}) or die $domain->name;

    remove_domain($domain);
}

sub test_templates_change_filter($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        $vm->add_host_device(template => $first->{name});
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];
        next if $vm->type eq 'KVM' && !config_host_devices($first->{name},0);

        _fix_host_device($hd) if $vm->type eq 'KVM';

        next if !$hd->list_devices;

        is(scalar($hd->list_domains_with_device()),0);

        my $domain = _create_domain_hd($vm, $hd);
        _fix_usb_ports($domain) if $first->{name} =~ /USB/i;
        $domain->start(user_admin);

        is(scalar($hd->list_domains_with_device()),1);
        $domain->shutdown_now(user_admin);

        $hd->_data('list_filter','AAAA AAAA');
        die "Error: list filter not enough restrictive" if $hd->list_devices();

        test_hostdev_not_in_domain_config($domain);

        $domain->remove(user_admin);
    }
    _remove_host_devices($vm);

}

sub _remove_host_devices($vm) {
    for my $hd ( $vm->list_host_devices ) {
        my $req = Ravada::Request->remove_host_device(
            uid => user_admin->id
            ,id_host_device => $hd->id
        );
        wait_request();
        is($req->status,'done');
        is($req->error, '') or exit;
    }
}

sub _get_frontend_devices($vm, $id_hd) {

    my $ws_args = {
        channel => '/'.$vm->id
        ,login => user_admin->name
    };
    my $front_devs = Ravada::WebSocket::_list_host_devices(undef, rvd_front(), $ws_args);
    my @devices;
    my $n_hds = scalar(@$front_devs);
    for my $curr_hd ( @$front_devs ) {
        next unless $curr_hd->{id} == $id_hd;
        for my $node ( keys %{$curr_hd->{devices_node}} ) {
            my $dn = $curr_hd->{devices_node}->{$node};
            for my $dev (@$dn) {
                push @devices, ($dev->{name})
            }
        }
    }
    return ($n_hds, \@devices);
}

sub test_templates($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    my $templates2 = Ravada::HostDevice::Templates::list_templates($vm->id);
    is_deeply($templates2,$templates);

    for my $first  (@$templates) {

        next if $first->{name } =~ /^GPU dri/ && $vm->type eq 'KVM';

        my $n=scalar($vm->list_host_devices);
        $vm->add_host_device(template => $first->{name});

        my @list_hostdev = $vm->list_host_devices();
        is(scalar @list_hostdev, $n+1, Dumper(\@list_hostdev)) or exit;

        $vm->add_host_device(template => $first->{name});
        @list_hostdev = $vm->list_host_devices();
        is(scalar @list_hostdev , $n+2);
        like ($list_hostdev[-1]->{name} , qr/[a-zA-Z\)\(] \d+$/) or exit;

        my $host_device = $list_hostdev[-1];

        next if $vm->type eq 'KVM' && !config_host_devices($host_device->{name},0);
        _fix_host_device($host_device) if $vm->type eq 'KVM';

        test_hd_in_domain($vm, $host_device);
        test_hd_dettach($vm, $host_device);

        my $req = Ravada::Request->list_host_devices(
            uid => user_admin->id
            ,id_host_device => $host_device->id
            ,_force => 1
        );
        wait_request( debug => 0);
        is($req->status, 'done');
        my ($n_hd,$devices) = _get_frontend_devices($vm, $host_device->id);
        is($n_hd, 2+$n) or die Dumper($devices, $host_device);
        $n+=2;

        my $list_filter = $host_device->_data('list_filter');
        $host_device->_data('list_filter' => 'fail match');
        wait_request(debug => 0);
        my ($n_hd2, $devices2) = _get_frontend_devices($vm, $host_device->id);
        my $equal;
        $equal = scalar(@$devices) == scalar (@$devices2);
        if ($equal ) {
            for ( 0 .. scalar(@$devices)-1) {
                if ($devices->[$_] ne $devices2->[$_]) {
                    $equal = 0;
                    last;
                }
            }
        }
        ok(!$equal) or die Dumper($devices, $devices2);
        $host_device->_data('list_filter' => $list_filter);
    }

    my $n = $vm->list_host_devices;
    for my $hd ( $vm->list_host_devices ) {
        _fix_host_device($hd) unless $vm->type eq 'KVM' && !config_host_devices($hd->{name},0);
        test_hd_remove($vm, $hd);
        is($vm->list_host_devices,--$n, $hd->name) or die Dumper([$vm->list_host_devices]);
    }
}

sub test_hd_dettach($vm, $host_device) {
    my $start_fails = 0;
    if (!$host_device->list_devices && $host_device->name =~ /^PCI/ && $vm->type eq 'KVM' ) {
        $host_device->_data('list_filter' => config_host_devices('pci'));
        $start_fails = 1;
    }
    $start_fails = 1 if !$start_fails && !$host_device->list_devices;

    my $domain = create_domain($vm);
    _fix_usb_ports($domain);
    $domain->add_host_device($host_device);

    eval { $domain->start(user_admin) };
    is(''.$@, '') unless $start_fails;
    $domain->shutdown_now(user_admin);
    $domain->remove_host_device($host_device);

    test_hostdev_not_in_domain_config($domain);
    $domain->remove(user_admin);
}

sub _req_remove($host_device) {

    my $req = Ravada::Request->remove_host_device(
        uid => user_admin->id
        ,id_host_device => $host_device->id
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error, '') or exit;

}

sub test_hd_remove($vm, $host_device) {
    my $start_fails;
    my $type = $host_device->{name};
    $type = 'usb' if $type =~ /usb/i;
    if ( $vm->type eq 'KVM' && !config_host_devices($type,0)) {
        _req_remove($host_device);
        return;
    }
    if ($host_device->name =~ /^PCI/ && $vm->type eq 'KVM' ) {
        _set_hd_nvidia($host_device);
        if (!$host_device->list_devices) {
            $host_device->_data('list_filter' => 'VGA');
            $start_fails = 1;
        }
    } else {
        $start_fails = 1 if !$host_device->list_devices();
    }
    my $domain = create_domain($vm);
    _fix_usb_ports($domain);
    _fix_host_device($host_device) if $vm->type eq 'KVM';
    $domain->add_host_device($host_device);
    _count_locked();
    eval { $domain->start(user_admin) };
    if (!$start_fails) {
        is(''.$@, '') or confess "Error starting ".$domain->name." "
        ."[ ".$domain->id."]";
    }
    $domain->shutdown_now(user_admin);

    my $req = _req_remove($host_device);

    my $sth = connector->dbh->prepare(
        "SELECT * FROM host_devices WHERE id=?"
    );
    $sth->execute($host_device->id);
    my ($found) = $sth->fetchrow;
    ok(!$found);

    $sth = connector->dbh->prepare(
        "SELECT * FROM host_devices_domain WHERE id_host_device=?"
    );
    $sth->execute($host_device->id);
    ($found) = $sth->fetchrow;
    ok(!$found);

}

####################################################################

clean();

for my $vm_name (vm_names()) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        test_templates($vm);

        test_frontend_list($vm);

        test_templates_gone_usb_2($vm);

        test_templates_gone_usb($vm);
        test_templates_changed_usb($vm);

        test_templates_start_nohd($vm);
        test_templates_change_filter($vm);

        test_templates_change_devices($vm);

    }
}

end();
done_testing();
