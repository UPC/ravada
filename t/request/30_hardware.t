use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Sys::Virt;
use Test::More;
use YAML qw(Dump);

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user("foo","bar", 1);

rvd_back();
$Ravada::CAN_FORK = 1;
my $BASE;

my $TEST_TIMESTAMP = 0;
my $TLS;

########################################################################
#
sub _download_alpine64 {
    my $id_iso = search_id_iso('Alpine%64');

    my $req = Ravada::Request->download(
             id_iso => $id_iso
    );
    wait_request();
    is($req->error, '');
    is($req->status,'done') or exit;
}

sub test_add_hardware_request_drivers {
	my $vm = shift;
	my $domain = shift;
	my $hardware = shift;

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info0 = $domain->info(user_admin);

    my $options = $info0->{drivers}->{$hardware};

    for my $remove ( 1,0 ) {
        test_remove_almost_all_hardware($vm, $domain, $hardware);
        for my $driver (@$options) {
            diag("Testing new $hardware $driver remove=$remove");

            my $info0 = $domain->info(user_admin);
            my @dev0 = sort map { $_->{driver} }
                        grep { !$_->{is_secondary} }
                        @{$info0->{hardware}->{$hardware}};
            test_add_hardware_request($vm, $domain, $hardware, { driver => $driver} );

            my $info1 = $domain->info(user_admin);
            my @dev1 = sort map { $_->{driver} } @{$info1->{hardware}->{$hardware}};

            if ( scalar @dev1 == scalar(@dev0)) {
                my $different = 0;
                for ( 0 .. scalar(@dev1)-1) {
                    $different++ if $dev1[$_] ne $dev0[$_];
                }
                ok($different, "Expecting different $hardware ") or die Dumper(\@dev0, \@dev1);
            } else {
                ok(scalar(@dev1) > scalar(@dev0)) or die Dumper(\@dev1,\@dev0);
                # it is ok because number of devs increased
            }
            my $driver_short = _get_driver_short_name($domain, $hardware,$driver);

            is($info1->{hardware}->{$hardware}->[-1]->{driver}, $driver_short) or confess( $domain->name
                , Dumper($info1->{hardware}->{$hardware}));

            test_display_data($domain , $driver) if $hardware eq 'display';

            test_remove_hardware($vm, $domain, $hardware
                , scalar(@{$info1->{hardware}->{$hardware}})-1)
            if $remove || $hardware eq 'disk' && $driver eq 'usb';
        }
    }

    #    test_add_hardware_request($vm, $domain, $hardware) if $hardware =~ 'display';
}

sub _get_driver_short_name($domain,$hardware, $option) {

    return $option unless $hardware eq 'display';

    my $driver = $domain->drivers($hardware);
    my ($selected)
    = grep { $_->{name} eq $option|| $_->{value} eq $option}
    $driver->get_options;

    return $selected->{value};
}

sub test_display_data($domain, $driver) {

    $domain->start(user => user_admin);
    wait_request(debug => 0);
    my $hardware = $domain->info(user_admin)->{hardware};
    $driver = _get_driver_short_name($domain, 'display', $driver);
    my @displays = @{$hardware->{display}};

    my ($display) = grep { $_->{driver} eq $driver } @displays;
    ok($display) or die "Display $driver not found ".Dumper(\@displays);

    test_display_builtin_ports($domain, $display) if $display->{is_builtin};

    $domain->shutdown(user => user_admin, timeout => 20);
    wait_request(debug => 0);
}

sub test_display_builtin_ports_kvm($domain, $display) {
    my $driver = $display->{driver};
    my $xml = XML::LibXML->load_xml( string => $domain->xml_description);
    my $path = "/domain/devices/graphics\[\@type='$driver']";
    my ($graphic) = $xml->findnodes($path);
    die "Error: $path not found in ".$domain->name if !$graphic;

    my $port = $graphic->getAttribute('port');
    is($port, $display->{port});
}

sub test_display_builtin_ports_void($domain, $display) {
    my $hardware = $domain->_value('hardware');
    my ($graphic) = grep { $_->{driver} eq $display->{driver} } @{$hardware->{display}};
    die "Error: display not found in ".Dumper($hardware) if !$graphic;

    is($display->{port}, $graphic->{port});
}

sub test_display_builtin_ports($domain, $display){
    return test_display_builtin_ports_kvm($domain,$display) if $domain->type eq 'KVM';
    return test_display_builtin_ports_void($domain,$display) if $domain->type eq 'Void';
    confess "TODO";
}

sub test_display_db($domain, $n_expected) {
    my $sth = connector->dbh->prepare("SELECT * FROM domain_displays "
        ." WHERE id_domain = ?"
    );
    $sth->execute($domain->id);

    my @row;
    while ( my $row = $sth->fetchrow_hashref) {
        push @row,($row);
        is($domain->_is_display_builtin(undef,$row), $row->{is_builtin}) or
        die Dumper($domain->name, $row);
    }

    is(scalar(@row),$n_expected) or confess Dumper($domain->name, \@row);

    my @displays = $domain->_get_controller_display();
    is(scalar @displays, @row);

    my $n_expected_non_builtin = scalar(grep { $_->{is_builtin} == 0 } @displays);

    my @ports = $domain->list_ports();
    is(scalar(@ports),$n_expected_non_builtin) or die Dumper(\@displays,\@ports);
}

sub test_add_hardware_request($vm, $domain, $hardware, $data={}) {

    confess if !ref($data) || ref($data) ne 'HASH';

    my $date_changed = $domain->_data('date_changed');

    my @list_hardware1 = $domain->get_controller($hardware);
    @list_hardware1 = map { $_->{file} } @list_hardware1 if $hardware eq 'disk';
	my $numero = scalar(@list_hardware1);
    while (($hardware eq 'display' && $numero > 0 ) || ($hardware eq 'usb' && $numero > 3)) {
        test_remove_hardware($vm, $domain, $hardware, 0);
        @list_hardware1 = $domain->get_controller($hardware);
	    $numero = scalar(@list_hardware1);
    }
    test_display_db($domain,0) if $hardware eq 'display';

    $data = { driver => 'spice' } if !keys %$data && $hardware eq 'display';

	my $req;
	eval {
		$req = Ravada::Request->add_hardware(uid => $USER->id
                , id_domain => $domain->id
                , name => $hardware
                , number => $numero
                , data => $data
            );
	};
	is($@,'') or return;
    $USER->unread_messages();
	ok($req, 'Request');
    sleep 1 if !$TEST_TIMESTAMP;
    wait_request(debug => 0);
    is($req->status(),'done');
    is($req->error(),'') or exit;
    my $n = 1;
    $n++ if $TLS && $hardware eq 'display' && $data->{driver} =~ /spice|vnc/
    && $domain->is_active();
    test_display_db($domain,$n) if $hardware eq 'display';

    {
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my @list_hardware2 = $domain_f->get_controller($hardware);
    is(scalar @list_hardware2 , scalar(@list_hardware1) + $n
        ,"Adding hardware $hardware $numero\n"
            .Dumper($domain->name,$data,\@list_hardware2, \@list_hardware1))
            or exit;
    }

    {
        my $domain_2 = Ravada::Front::Domain->open($domain->id);
        my @list_hardware2 = $domain_2->get_controller($hardware);
        is(scalar @list_hardware2 , scalar(@list_hardware1) + $n
            ,"Adding hardware $numero\n"
                .Dumper(\@list_hardware2, \@list_hardware1)) or exit;
    }
    $domain = Ravada::Domain->open($domain->id);
    my $info = $domain->info(user_admin);
    is(scalar(@{$info->{hardware}->{$hardware}}), $numero+$n) or exit;
    my $new_hardware = $info->{hardware}->{$hardware}->[$numero-1];
    if ( $hardware eq 'disk' && $new_hardware->{name} !~ /\.iso$/) {
        my $name = $domain->name;
        like($new_hardware->{name}, qr/$name-.*vd[a-z].*\.\w+$/) or die Dumper($new_hardware);
    }
    if (!$TEST_TIMESTAMP++) {
        isnt($domain->_data('date_changed'), $date_changed);
    }
}

sub test_add_cdrom($domain) {
    my $n = 0;
    for my $device ( $domain->list_volumes_info ) {
        if ($device->info->{device} eq 'cdrom') {
            test_remove_hardware($domain->_vm, $domain, 'disk', $n);
        }
        $n++;
    }

    my $data = { device => 'cdrom' , boot => 2 };
    my $file_iso = "/var/tmp/test_30_hardware.iso";
    if ($domain->type eq 'KVM') {
        eval { $domain->_set_boot_hd(1) };
        is(''.$@,'') or exit;
        eval { $domain->_set_boot_hd(0) };
        is(''.$@,'') or exit;
        my $iso = $domain->_vm->_search_iso(search_id_iso('Alpine'));
        $data->{file} = $iso->{device};
    } else {
        $data->{boot} = 2;
    }
    $data->{file} = $file_iso if !$data->{file};
    my $found = 0;
    test_add_hardware_request($domain->_vm, $domain,'disk', $data);

    test_cdrom_kvm($domain) if $domain->type eq 'KVM';
    #############
    # test device cdrom just added
    for my $device ( $domain->list_volumes_info ) {
        if ($device->info->{device} eq 'cdrom') {
            $found++;
            like($device->info->{name}, qr/\.iso/,$domain->type." ".$domain->name) or exit;
            is($device->info->{boot}, 2, $domain->name) or die Dumper($device->info);
        }
    }
    unlink $file_iso;

}

sub test_cdrom_kvm($domain) {
    diag("Testing cdrom KVM ");
    #########
    # test XML without boot
    {
        my $xml = XML::LibXML->load_xml(
            string => $domain->domain->get_xml_description()
        );
        my ($boot) = $xml->findnodes('/os/boot');
        ok(!$boot) or do {
            my ($os) = $xml->findnodes('/os');
            die $os->toString();
        };
    }
    #########
    # test XML inactive without boot
    {
        my $xml = XML::LibXML->load_xml(
            string => $domain->domain->get_xml_description(Sys::Virt::Domain::XML_INACTIVE)
        );
        my ($boot) = $xml->findnodes('/os/boot');
        ok(!$boot) or do {
            my ($os) = $xml->findnodes('/os');
            die $os->toString();
        };
    }
}

sub test_add_disk($domain) {
    test_add_cdrom($domain);
}

sub test_add_hardware_custom($domain, $hardware) {
    my %sub = (
        disk => \&test_add_disk
        ,display => sub {}
        ,usb => sub {}
        ,mock => sub {}
        ,network => sub {}
    );

    my $exec = $sub{$hardware} or die "No custom add $hardware";
    return $exec->($domain);
}

sub test_remove_hardware($vm, $domain, $hardware, $index) {

    $domain->shutdown_now(user_admin)   if $domain->is_active;
    $domain = Ravada::Domain->open($domain->id);
    my @list_hardware1 = $domain->get_controller($hardware);

    confess "Error: I can't remove $hardware $index, only ".scalar(@list_hardware1)
        ."\n"
        .Dumper(\@list_hardware1)
            if $index > scalar @list_hardware1;

	my $req;
	{
		$req = Ravada::Request->remove_hardware(uid => $USER->id
				, id_domain => $domain->id
				, name => $hardware
				, index => $index
			);
	};
	is($@, '') or return;
	ok($req, 'Request');
	rvd_back->_process_all_requests_dont_fork();
	is($req->status(), 'done');
	is($req->error(), '') or exit;

    my $n = 1;
    $n++ if $hardware eq 'display' && grep({ $_->{driver} =~ /-tls/ } @list_hardware1);
    {
        my $domain2 = Ravada::Domain->open($domain->id);
        my @list_hardware2 = $domain2->get_controller($hardware);
        is(scalar @list_hardware2 , scalar(@list_hardware1) - $n
        ,"Removing hardware $hardware\[$index] ".$domain->name."\n"
            .Dumper(\@list_hardware2, \@list_hardware1)) or exit;
    }
    {
        my $domain_f = Ravada::Front::Domain->open($domain->id);
        my @list_hardware2 = $domain_f->get_controller($hardware);
        is(scalar @list_hardware2 , scalar(@list_hardware1) - $n
        ,"Removing hardware $index ".$domain->name."\n"
            .Dumper(\@list_hardware2, \@list_hardware1)) or exit;
    }
    test_volume_removed($list_hardware1[$index]) if $hardware eq 'disk';
    test_display_removed($domain, $list_hardware1[$index], $index)   if $hardware eq 'display';
}

sub test_volume_removed($disk) {
    my $file = $disk->{file};
    return if !$file;
    ok(! -e $file,"Expecting $file removed") unless $file =~ /\.iso$/;
}

sub test_display_removed($domain, $display, $index) {
    my $hardware = $domain->info(user_admin)->{hardware}->{display};
    ok(! grep({ $_->{driver} eq $display->{driver} } @$hardware),
        "Expecting no $display->{driver} in hardware ") or die Dumper($hardware);
    if ($display->{driver} eq 'spice' || $display->{is_builtin}) {
        # TODO check display removed from XML
    }
    my $display2;
    eval { $display2 = $domain->_get_display_by_index($index) };
    like($@,qr/not found/);
    ok(!$display2,"Expecting display $index removed from DB ".$domain->name) or exit;

}

sub test_remove_almost_all_hardware {
	my $vm = shift;
	my $domain = shift;
	my $hardware = shift;
    my $n_keep = 2;
    $n_keep = 0 if $hardware eq 'display' || $hardware eq 'disk';

    #TODO test remove hardware out of bounds
    my $total_hardware = scalar($domain->get_controller($hardware));
    return if !defined $total_hardware || $total_hardware <= $n_keep;
    for my $index ( reverse 0 .. $total_hardware-1) {
        diag("removing $hardware $index");
        test_remove_hardware($vm, $domain, $hardware, $index);
        $domain->list_volumes() if $hardware eq 'disk';
    }
}

sub test_front_hardware {
    my ($vm, $domain, $hardware ) = @_;

    $domain->list_volumes();
    my $domain_f = Ravada::Front::Domain->open($domain->id);

        my @controllers = $domain_f->get_controller($hardware);
        ok(scalar @controllers,"[".$vm->type."] Expecting $hardware controllers ".$domain->name
            .Dumper(\@controllers))
                or confess;

        my $info = $domain_f->info(user_admin);
        ok(exists $info->{hardware},"Expecting \$info->{hardware}") or next;
        ok(exists $info->{hardware}->{$hardware},"Expecting \$info->{hardware}->{$hardware}");
        is_deeply($info->{hardware}->{$hardware},[@controllers]);
}

sub test_change_disk_field($vm, $domain, $field='capacity') {
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info = $domain_f->info(user_admin);

    my $hardware = 'disk';

    my $index;
    for my $count ( 0 .. scalar(@{$info->{hardware}->{$hardware}}) -1 ) {
        if ( exists $info->{hardware}->{$hardware}->[$count]->{$field} ) {
            $index = $count;
            last;
        }
    }
    confess "Device without $field in ".$domain->name
        ."\n".Dumper($info->{hardware}->{$hardware})
        if !defined $index;

    my $device = $info->{hardware}->{$hardware}->[$index];
    confess "Device without $field in ".$domain->name."\n".Dumper($device)
        if !exists $device->{$field};
    my $capacity = Ravada::Utils::size_to_number(
        $info->{hardware}->{$hardware}->[$index]->{$field}
    );
    ok(defined $capacity,"Expecting some $field") or exit;
    my $new_capacity = int(( $capacity +1 ) * 2);
    isnt($new_capacity, $capacity) or exit;
    isnt( $info->{hardware}->{$hardware}->[$index]->{$field}, $new_capacity );

    my $file = $info->{hardware}->{$hardware}->[$index]->{file};
    ok($file) or die Dumper($info->{hardware}->{$hardware}->[$index]);

    my @volumes = $domain->list_volumes();
    is($volumes[$index], $file) or exit;

    my $req = Ravada::Request->change_hardware(
        id_domain => $domain->id
        ,hardware => 'disk'
           ,index => $index
            ,data => { $field=> $new_capacity }
             ,uid => user_admin->id
    );

    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error, '',"Changing $field from $capacity to $new_capacity") or exit;

    my $domain_b = Ravada::Domain->open($domain->id);
    my $info_b = $domain_b->info(user_admin);
    $domain_f = Ravada::Front::Domain->open($domain->id);
    $info = $domain_f->info(user_admin);

    my $found_capacity
    = Ravada::Utils::size_to_number($info->{hardware}->{$hardware}->[$index]->{$field});
    is( int($found_capacity/1024)
        ,int($new_capacity/1024), $domain_b->name." $field \n"
        .Dumper($info->{hardware}->{$hardware}->[$index]) ) or exit;
    is( $info->{hardware}->{$hardware}->[$index]->{file}, $file);
}

sub test_change_usb($vm, $domain) {
}

sub test_cdrom($domain, $index, $file_new) {
    my $req = Ravada::Request->change_hardware(
            id_domain => $domain->id
            ,hardware =>'disk'
            ,index => $index
            ,data => { file => $file_new }
            ,uid => user_admin->id
        );

    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error, '') or exit;

    my $domain2 = Ravada::Domain->open($domain->id);
    my $info = $domain2->info(user_admin);

    my $cdrom2 = $info->{hardware}->{disk}->[$index];
    if ($file_new) {
        is ($cdrom2->{file}, $file_new);
    } else {
        ok(!exists $cdrom2->{file},"[".$domain->type."] Expecting no file. ".Dumper($cdrom2));
    }

}
sub test_change_disk_cdrom($vm, $domain) {
    my ($index,$cdrom) = _search_cdrom($domain);
    ok($cdrom) or exit;
    ok(defined $cdrom->{file},"Expecting file field in ".Dumper($cdrom));

    my $file_old = $cdrom->{file};
    my $file_new = '/tmp/test-".base_domain_name.".iso';
    open my $out,'>',$file_new or die "$! $file_new";
    print $out Dump({ data => $$ });
    close $out;

    test_cdrom($domain, $index, $file_new);
    test_cdrom($domain, $index, '');
    test_cdrom($domain, $index, $file_old);
    unlink $file_new or die "$! $file_new";
}

sub _search_cdrom($domain) {
    my $count=0;
    for my $device ( $domain->list_volumes_info ) {
        return ($count,$device) if ($device->info()->{device} eq 'cdrom');
        $count++;
    }
}

sub _search_disk($domain) {
    my $count=0;
    for my $device ( $domain->list_volumes_info ) {
        return $count if ($device->info->{device} eq 'disk');
        $count++;
    }
    return 0;
}


sub test_change_disk($vm, $domain) {
    test_change_disk_field($vm, $domain, 'capacity');
    test_change_disk_cdrom($vm, $domain);
}

sub test_change_network_bridge($vm, $domain, $index) {
    SKIP: {
    my @bridges = $vm->list_network_interfaces('bridge');

    skip("No bridges found in this system",6) if !scalar @bridges;
    my $info = $domain->info(user_admin);
    is ($info->{hardware}->{network}->[$index]->{type}, 'NAT') or exit;

    ok(scalar @bridges,"No network bridges defined in this host") or return;

    diag("Testing network bridge ".$bridges[0]);
    my $req = Ravada::Request->change_hardware(
        id_domain => $domain->id
        ,hardware => 'network'
           ,index => $index
            ,data => { type => 'bridge', bridge => $bridges[0]}
             ,uid => user_admin->id
    );

    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error, '');

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    $info = $domain_f->info(user_admin);
    is ($info->{hardware}->{network}->[$index]->{type}, 'bridge', $domain->name)
        or die Dumper($info->{hardware}->{network});
    is ($info->{hardware}->{network}->[$index]->{bridge}, $bridges[0] );

    }
}

sub test_change_network_nat($vm, $domain, $index) {
    my $info = $domain->info(user_admin);

    my @nat = $vm->list_network_interfaces( 'nat');
    ok(scalar @nat,"No NAT network defined in this host") or return;

    diag("Testing network NAT ".$nat[0]);
    my $req = Ravada::Request->change_hardware(
        id_domain => $domain->id
        ,hardware => 'network'
           ,index => $index
            ,data => { type => 'NAT', network => $nat[0]}
             ,uid => user_admin->id
    );

    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error, '');

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    $info = $domain_f->info(user_admin);
    is ($info->{hardware}->{network}->[$index]->{type}, 'NAT');
    is ($info->{hardware}->{network}->[$index]->{network}, $nat[0] );

}

sub test_change_network($vm, $domain) {
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info = $domain_f->info(user_admin);

    my $hardware = 'network';

    my $index = int(scalar(@{$info->{hardware}->{$hardware}}) / 2);

    test_change_network_bridge($vm, $domain, $index);
    test_change_network_nat($vm, $domain, $index);
}

sub test_change_hardware($vm, $domain, $hardware) {
    my %sub = (
      network => \&test_change_network
        ,disk => \&test_change_disk
        ,mock => sub {}
         ,usb => sub {}
         ,display => sub {}
    );
    my $exec = $sub{$hardware} or die "I don't know how to test $hardware";
    $exec->($vm, $domain);
}

sub test_change_drivers($domain, $hardware) {

    my $info = $domain->info(user_admin);
    my $options = $info->{drivers}->{$hardware};
    ok(scalar @$options,"No driver options for $hardware") or exit;
    for my $option ( @$options ) {
        is(ref($option),'',"Invalid option for driver $hardware") or exit;
    }

    for my $option (@$options) {
        my $index = 0;
        $index = _search_disk($domain) if $hardware eq 'disk';
        diag("Testing $hardware type $option in $hardware $index");
        $option = lc($option);
        my $req = Ravada::Request->change_hardware(
            id_domain => $domain->id
            ,hardware => $hardware
            ,index => $index
            ,data => { driver => $option }
            ,uid => user_admin->id
        );

        wait_request(debug => 0);

        is($req->status,'done');
        is($req->error, '') or exit;

        my $domain_f = Ravada::Front::Domain->open($domain->id);
        $info = $domain_f->info(user_admin);
        is ($info->{hardware}->{$hardware}->[$index]->{driver}, $option
        ,Dumper($domain_f->name,$info->{hardware}->{$hardware}->[$index])) or exit;

        my $domain_b = Ravada::Domain->open($domain->id);
        my $info_b = $domain_b->info(user_admin);
        is ($info_b->{hardware}->{$hardware}->[$index]->{driver}, $option
        ,Dumper($info_b->{hardware}->{$hardware}->[$index])) or exit;

        $domain_b->start(user_admin);
        is($domain_b->is_active,1);
        $info_b = $domain_b->info(user_admin);
        is ($info_b->{hardware}->{$hardware}->[$index]->{driver}, $option
        ,Dumper($info_b->{hardware}->{$hardware}->[$index])) or exit;
        $domain_b->shutdown_now(user_admin);
    }
}

sub test_all_drivers($domain, $hardware) {
    my $info = $domain->info(user_admin);
    my $options = $info->{drivers}->{$hardware};
    ok(scalar @$options,"No driver options for $hardware") or exit;
    my $index = int(scalar(@{$info->{hardware}->{$hardware}}) / 2);

    my $domain_b = Ravada::Domain->open($domain->id);
    for my $option1 (@$options) {
        for my $option2 (@$options) {
            # diag("Testing $hardware type from $option1 to $option2");
            my $req = Ravada::Request->change_hardware(
                id_domain => $domain->id
                ,hardware => $hardware
                ,index => $index
                ,data => { driver => lc($option1) }
                ,uid => user_admin->id
            );
            rvd_back->_process_requests_dont_fork();

            is($req->status,'done');
            is($req->error, '') or exit;
            $req = Ravada::Request->change_hardware(
                id_domain => $domain->id
                ,hardware => $hardware
                ,index => $index
                ,data => { driver => lc($option2) }
                ,uid => user_admin->id
            );
            rvd_back->_process_requests_dont_fork();

            is($req->status,'done');
            is($req->error, '') or exit;

            $domain->start(user_admin);
            is($domain->is_active,1);
            $domain->shutdown_now(user_admin);
        }
    }
}

sub _create_base($vm) {
    if ($vm->type eq 'KVM') {
        my @base;
        push @base,(import_domain($vm, "zz-test-base-alpine-q35-uefi"));
        push @base,(import_domain($vm, "zz-test-base-alpine-q35"));
        push @base,(import_domain($vm, "zz-test-base-alpine"));
        return @base;
    }
    return (create_domain($vm));
}

sub test_remove_display($vm) {
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    if ($vm->type eq 'KVM') {
        my $req = Ravada::Request->add_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            , name => 'display'
            , data => { driver => 'vnc' }
        );
        wait_request();
        is($req->status,'done');
        is($req->error, '');
    }
    my @displays = $domain->display_info(user_admin);
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    for my $n ( reverse 0 .. $#displays ) {
        next if exists $displays[$n]->{is_secondary} && $displays[$n]->{is_secondary};
        my $driver = $displays[$n]->{driver};
        diag("Removing display $n $driver");
        my $req_remove = Ravada::Request->remove_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            , name => 'display'
            , index => $n
        );
        wait_request();
        is($req_remove->status,'done');
        is($req_remove->error,'');
        my $display_2 = $domain->_get_display($driver);
        ok(!$display_2->{driver});
        $display_2 = $domain->_get_display("$driver-tls");
        ok(!$display_2->{driver},"Expecting no $driver-tls ".Dumper($display_2));
        $display_2 = $domain_f->_get_display($driver);
        ok(!$display_2->{driver});
        $display_2 = $domain_f->_get_display("$driver-tls");
        ok(!$display_2->{driver});
    }
    my @displays2 = $domain->display_info(user_admin);
    is(scalar(@displays2),0) or exit;
    @displays2 = $domain_f->display_info(user_admin);
    is(scalar(@displays2),0) or die Dumper(\@displays2);
    $domain->remove(user_admin);
}

########################################################################


{
my $rvd_back = rvd_back();
ok($rvd_back,"Launch Ravada");# or exit;
}

ok($Ravada::CONNECTOR,"Expecting conector, got ".($Ravada::CONNECTOR or '<unde>'));

remove_old_domains();
remove_old_disks();

for my $vm_name ( vm_names()) {
    my $vm;
    $vm = rvd_back->search_vm($vm_name)  if rvd_back();
	if ( !$vm || ($vm_name eq 'KVM' && $>)) {
	    diag("Skipping VM $vm_name in this system");
	    next;
	}
    _download_alpine64() if !$<;
    $TLS = 0;
    $TLS = 1 if check_libvirt_tls() && $vm_name eq 'KVM';
    for my $base ( _create_base($vm) ) {
        $BASE = $base;
	my $name = new_domain_name();
	my $domain_b = $BASE->clone(
        name => $name
        ,user => $USER
    );
    test_remove_display($vm);
    my %controllers = $domain_b->list_controllers;

    for my $hardware ( reverse sort keys %controllers ) {
        diag("Testing $hardware controllers for VM $vm_name");
        test_front_hardware($vm, $domain_b, $hardware);

        test_add_hardware_custom($domain_b, $hardware);
        test_add_hardware_request($vm, $domain_b, $hardware);
        test_change_hardware($vm, $domain_b, $hardware);
        test_remove_hardware($vm, $domain_b, $hardware, 0);

        # change driver is not possible for displays
        test_change_drivers($domain_b, $hardware)   if $hardware !~ /^(display|usb|mock)$/;
        test_add_hardware_request_drivers($vm, $domain_b, $hardware);
        test_all_drivers($domain_b, $hardware)   if $hardware !~ /^(display|usb|mock)$/;

        # try to add with the machine started
        $domain_b->start(user_admin) if !$domain_b->is_active;
        ok($domain_b->is_active) or next;

        test_add_hardware_request($vm, $domain_b, $hardware);

        $domain_b->shutdown_now(user_admin) if $domain_b->is_active;
        is($domain_b->is_active,0) or next;

        if ( $hardware ne 'usb' ) {
            for (1 .. 3 ) {
                test_add_hardware_request($vm, $domain_b, $hardware);
            }
        }



        $domain_b->shutdown_now(user_admin) if $domain_b->is_active;
        ok(!$domain_b->is_active);
        }
    }
    ok($TEST_TIMESTAMP);
}

end();
done_testing();
