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

####################################################################

sub _set_hd_nvidia($hd) {
    $hd->_data( list_command => 'lspci -Dnn');
    $hd->_data( list_filter => 'VGA.*NVIDIA');
}

sub _set_hd_usb($hd) {
    $hd->_data( list_filter => '(disk|flash|audio|smartcard|cam|bluetoo)');
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
    ok(exists $config->{hardware}->{host_devices}) or return;
    ok(scalar(@{ $config->{hardware}->{host_devices}})) or die "Expecting host_devices"
        ." in ".Dumper($config->{hardware});
}

sub test_hostdev_in_domain_kvm($domain, $expect_feat_kvm=1) {
    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);

    if ($expect_feat_kvm) {
        my ($feat) = $xml->findnodes("/domain/features");
        my ($feat_kvm) = $xml->findnodes("/domain/features/kvm");
        ok($feat_kvm) or die "Error, no /domain/features/kvm in ".$domain->name
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
}

sub _create_domain_hd($vm, $hd) {
    my $domain = create_domain($vm);
    $domain->add_host_device($hd);

    return $domain if $vm->type ne 'KVM';

   return $domain;
}

sub test_hd_in_domain($vm , $hd) {

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
            _set_hd_usb($hd);
        }
    }
    diag("Testing HD ".$hd->{name}." ".$hd->list_filter." in ".$vm->type);
    $domain->add_host_device($hd);

    if ($hd->list_devices) {
        $domain->start(user_admin);
        $domain->shutdown_now(user_admin);
    }

    $domain->prepare_base(user_admin);
    my $n_locked = _count_locked();
    for my $count (reverse 0 .. $hd->list_devices ) {
        my $clone = $domain->clone(name => new_domain_name() ,user => user_admin);
        test_hostdev_not_in_domain_config($clone);
        _compare_hds($domain, $clone);

        test_device_unlocked($clone);
        if ($hd->list_devices) {
            eval { $clone->start(user_admin) };
            if (!$count) {
                like($@,qr/No available devices/);
                diag($@);
                last;
            }
            is(_count_locked(),++$n_locked) or exit;
            test_device_locked($clone);
            test_hostdev_in_domain_config($clone, ($hd->name =~ /PCI/ && $vm->type eq 'KVM'));
        }

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
    test_grab_free_device($domain) if $hd->list_devices();

    remove_domain($domain);

}

sub test_grab_free_device($base) {
    diag("grab free device in ".$base->type);
    wait_request();
    rvd_back->_cmd_refresh_vms();
    my @clones = $base->clones();

    die "Error: I need 3 clones . I can't try to grab only ".scalar(@clones)
    if scalar(@clones)<3;

    my ($up) = grep { $_->{status} eq 'active' } @clones;
    my ($down) = grep { $_->{status} ne 'active' } @clones;
    ok($down && exists $down->{id}) or die Dumper(\@clones);
    $up = Ravada::Domain->open($up->{id});
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
    ($up_dev) = $up->list_host_devices_attached();
    is($up_dev->{is_locked},0);

    eval { $down->start(user_admin) };
    is(''.$@,'') or die "Error starting ".$down->name;
    ($down_dev) = $down->list_host_devices_attached();
    ok($down_dev->{name});
    ($up_dev) = $up->list_host_devices_attached();
    is($up_dev->{is_locked},0);
    test_hostdev_in_domain_config($up, $expect_feat_kvm);
    test_hostdev_in_domain_config($down, $expect_feat_kvm);

    diag("trying to start ".$up->id." ".$up->name);
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
    diag("just released [".$third->id."] ".$third->name);
    diag($third_dev->{name});

    eval { $up->start(user_admin) };
    is(''.$@,'') or die "Error starting ".$up->name;

    is($up->is_active,1);
    my ($up_dev2) = $up->list_host_devices_attached();
    is($up_dev2->{is_locked},1);
    is($up_dev2->{name}, $third_dev->{name});

    my ($third_dev_down) = $third->list_host_devices_attached();
    is($third_dev_down->{is_locked},0) or die Dumper($third_dev_down);
    test_hostdev_in_domain_config($up, $expect_feat_kvm);
    test_hostdev_in_domain_config($third, $expect_feat_kvm);

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
    my $sth = connector->dbh->prepare("SELECT count(*) FROM host_devices_domain_locked ");
    $sth->execute();
    my ($n) = $sth->fetchrow;
    return $n;
}
sub test_templates_start_nohd($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        $vm->add_host_device(template => $first->{name});
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];

        _fix_host_device($hd) if $vm->type eq 'KVM';

        next if !$hd->list_devices;

        my $domain = _create_domain_hd($vm, $hd);
        $domain->start(user_admin);
        my $info = $domain->info(user_admin);
        is($info->{host_devices}->[0]->{is_locked},1);
        $domain->shutdown_now(user_admin);

        my $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $domain->id
            ,enable_host_devices => 0
        );
        wait_request();
        is($req->error, '');
        test_hostdev_not_in_domain_config($domain);
        $domain->shutdown_now(user_admin);

        $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $domain->id
            ,enable_host_devices => 1
        );
        wait_request();
        is($req->error, '');
        test_hostdev_in_domain_config($domain,1);
        $domain->shutdown_now(user_admin);

        $domain->remove(user_admin);
    }
    for my $hd ( $vm->list_host_devices ) {
        test_hd_remove($vm, $hd);
    }
}

sub test_templates_gone_usb($vm) {
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
        $domain->start(user_admin);

        is(scalar($hd->list_domains_with_device()),1);
        $domain->shutdown_now(user_admin);
        _mangle_dom_hd($domain);
        my $req = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(check_error => 0, debug => 0);
        my $req2 = Ravada::Request->open($req->id);
        like($req2->error,qr/Did not find USB device/);

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
    my ($in, $out,$err);
    run3(['lsusb'], \$in, \$out, \$err);
    my $device=0;
    for my $line (split /\n/, $out) {
        my ($current) = $line =~ /Device (\d+)/;
        $device = $current if $current>$device;
    }
    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);

    my ($address) = $xml->findnodes("/domain/devices/hostdev/source/address");
    my ($old_device) = $address->getAttribute('device');
    my $sth = connector->dbh->prepare("SELECT id,name FROM host_devices_domain "
        ." WHERE id_domain=?");
    $sth->execute($domain->id);
    my ($id_hd, $device_name) = $sth->fetchrow;
    $address->setAttribute(device => ++$device);
    $device_name =~ s/(.*Device )\d+(.*)/$1$device$2/;
    $sth = connector->dbh->prepare("UPDATE host_devices_domain set name=?"
        ." WHERE id=?");
    $sth->execute($device_name, $id_hd);
    $domain->reload_config($xml);
}

sub test_templates_change_filter($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    for my $first  (@$templates) {
        diag("Testing $first->{name} Hostdev on ".$vm->type);
        $vm->add_host_device(template => $first->{name});
        my @list_hostdev = $vm->list_host_devices();
        my ($hd) = $list_hostdev[-1];

        _fix_host_device($hd) if $vm->type eq 'KVM';

        next if !$hd->list_devices;

        is(scalar($hd->list_domains_with_device()),0);

        my $domain = _create_domain_hd($vm, $hd);
        $domain->start(user_admin);

        is(scalar($hd->list_domains_with_device()),1);
        $domain->shutdown_now(user_admin);

        $hd->_data('list_filter','AAAA AAAA');
        die "Error: list filter not enough restrictive" if $hd->list_devices();

        test_hostdev_not_in_domain_config($domain);

        $domain->remove(user_admin);
    }

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

sub test_templates($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    my $templates2 = Ravada::HostDevice::Templates::list_templates($vm->id);
    is_deeply($templates2,$templates);


    for my $first  (@$templates) {

        next if $first->{name } =~ /^GPU dri/ && $vm->type eq 'KVM';

        my $n=scalar($vm->list_host_devices);
        diag("Testing add '$first->{name}' Hostdev on ".$vm->type. " n=$n" );
        $vm->add_host_device(template => $first->{name});

        my @list_hostdev = $vm->list_host_devices();
        is(scalar @list_hostdev, $n+1, Dumper(\@list_hostdev)) or exit;

        $vm->add_host_device(template => $first->{name});
        @list_hostdev = $vm->list_host_devices();
        is(scalar @list_hostdev , $n+2);
        like ($list_hostdev[-1]->{name} , qr/[a-zA-Z] \d+$/) or exit;

        test_hd_in_domain($vm, $list_hostdev[-1]);
        test_hd_dettach($vm, $list_hostdev[-1]);

        my $req = Ravada::Request->list_host_devices(
            uid => user_admin->id
            ,id_host_device => $list_hostdev[-1]->id
            ,_force => 1
        );
        wait_request( debug => 0);
        is($req->status, 'done');
        my $ws_args = {
            channel => '/'.$vm->id
            ,login => user_admin->name
        };
        my $devices = Ravada::WebSocket::_list_host_devices(rvd_front(), $ws_args);
        is(scalar(@$devices), 2+$n) or die Dumper($devices, $list_hostdev[-1]);
        $n+=2;
        next if !(scalar(@{$devices->[-1]->{devices}})>1);

        my $list_filter = $list_hostdev[-1]->_data('list_filter');
        $list_hostdev[-1]->_data('list_filter' => '002');
        my $req2 = Ravada::Request->list_host_devices(
            uid => user_admin->id
            ,id_host_device => $list_hostdev[-1]->id
            ,_force => 1
        );
        wait_request();
        is($req2->status, 'done');
        is($req2->error, '');
        my $devices2 = Ravada::WebSocket::_list_host_devices(rvd_front(), $ws_args);
        my $equal;
        my $dev0 = $devices->[-1]->{devices};
        my $dev2 = $devices2->[-1]->{devices};
        $equal = scalar(@$dev0) == scalar (@$dev2);
        if ($equal ) {
            for ( 0 .. scalar(@$dev0)) {
                if ($dev0->[$_] ne $dev2->[$_]) {
                    $equal = 0;
                    last;
                }
            }
        }
        ok(!$equal) or die Dumper($dev0, $dev2);
        $list_hostdev[-1]->_data('list_filter' => $list_filter);
    }

    my $n = $vm->list_host_devices;
    for my $hd ( $vm->list_host_devices ) {
        test_hd_remove($vm, $hd);
        is($vm->list_host_devices,--$n, $hd->name) or die Dumper([$vm->list_host_devices]);
    }
}

sub test_hd_dettach($vm, $host_device) {
    my $start_fails = 0;
    if (!$host_device->list_devices && $host_device->name =~ /^PCI/ && $vm->type eq 'KVM' ) {
        $host_device->_data('list_filter' => 'VGA');
        $start_fails = 1;
    }
    $start_fails = 1 if !$start_fails && !$host_device->list_devices;

    my $domain = create_domain($vm);
    $domain->add_host_device($host_device);

    eval { $domain->start(user_admin) };
    is(''.$@, '') unless $start_fails;
    $domain->shutdown_now(user_admin);
    $domain->remove_host_device($host_device);

    test_hostdev_not_in_domain_config($domain);
    $domain->remove(user_admin);
}

sub test_hd_remove($vm, $host_device) {
    my $start_fails;
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
    $domain->add_host_device($host_device);

    eval { $domain->start(user_admin) };
    is(''.$@, '') unless $start_fails;
    $domain->shutdown_now(user_admin);

    my $req = Ravada::Request->remove_host_device(
        uid => user_admin->id
        ,id_host_device => $host_device->id
    );
    wait_request();
    is($req->status,'done');
    is($req->error, '') or exit;

    my $sth = connector->dbh->prepare(
        "SELECT * FROM host_devices WHERE id=?"
    );
    $sth->execute($host_device->id);
    my ($found) = $sth->fetchrow;
    ok(!$found);
}

####################################################################

clean();

for my $vm_name ( vm_names()) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        test_templates_start_nohd($vm);
        test_templates_gone_usb($vm) if $vm_name eq 'KVM';
        test_templates_change_filter($vm);
        test_templates($vm);

    }
}

end();
done_testing();

