use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use POSIX qw(WNOHANG);
use Storable qw(dclone);
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

sub _driver_field($hardware) {
    my $driver_field = 'driver';
    $driver_field = 'type'  if $hardware =~ /^video$/;
    $driver_field = 'model' if $hardware =~ /^(sound|usb controller)$/;
    $driver_field = 'mode'  if $hardware eq 'cpu';
    $driver_field = '_name' if $hardware eq 'filesystem';
    $driver_field = 'bus'   if $hardware eq 'disk';
    return $driver_field;
}

sub test_add_hardware_request_drivers {
	my $vm = shift;
	my $domain = shift;
	my $hardware = shift;

    my $driver_field = _driver_field($hardware);

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info0 = $domain->info(user_admin);

    my $options = $info0->{drivers}->{$hardware};

    for my $remove ( 1,0 ) {
        test_remove_almost_all_hardware($vm, $domain, $hardware);
        for my $driver (@$options) {
            $driver = lc($driver);
            next if $hardware eq 'video' && $driver eq 'none';
            diag("Testing new $hardware $driver remove=$remove");

            my $info0 = $domain->info(user_admin);
            my @dev0 = sort map { $_->{$driver_field} }
                        grep { !exists $_->{is_secondary} || !$_->{is_secondary} }
                        @{$info0->{hardware}->{$hardware}};
            test_add_hardware_request($vm, $domain, $hardware, { $driver_field => $driver} );

            my $info1 = $domain->info(user_admin);
            my @dev1 = sort map { $_->{$driver_field} } @{$info1->{hardware}->{$hardware}};

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

            if ($hardware eq 'video' ) {
                my ($new) = grep {$_->{$driver_field} eq $driver_short }
                    @{$info1->{hardware}->{$hardware}};
                ok($new,"Expecting a $hardware $driver_short");
            } else {
                is($info1->{hardware}->{$hardware}->[-1]->{$driver_field}, $driver_short) or confess( $domain->name
                    , Dumper($info1->{hardware}->{$hardware}))
            }

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
    = grep { lc($_->{name}) eq lc($option) || lc($_->{value}) eq lc($option)}
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

sub _remove_other_video_primary($domain) {
    my @list_hardware = $domain->get_controller('video');
    my $removed = 0;
    for my $index (reverse 0 .. scalar(@list_hardware)-1 ) {
        next if $list_hardware[$index]->{type} !~ /vmvga|cirrus/;
        Ravada::Request->remove_hardware(
            name => 'video'
            ,id_domain => $domain->id
            ,index => $index
            ,uid => user_admin->id
        );
        $removed++;
    }
    wait_request() if $removed;
}

sub test_add_hardware_request($vm, $domain, $hardware, $data={}) {

    return if $hardware eq 'video'
        && exists $data->{type} && defined $data->{type}
        && $data->{type} eq 'none';

    $domain = Ravada::Domain->open($domain->id);

    confess if !ref($data) || ref($data) ne 'HASH';

    if ($hardware eq 'video' && exists $data->{type} &&  $data->{type} eq 'cirrus') {
        _remove_other_video_primary($domain);
    }

    my $date_changed = $domain->_data('date_changed');

    my @list_hardware1 = $domain->get_controller($hardware);
    @list_hardware1 = map { $_->{file} } @list_hardware1 if $hardware eq 'disk';

	my $numero = scalar(@list_hardware1);

    while (($hardware =~ /display/ && $numero > 0 ) || ($hardware eq 'usb' && $numero > 3) || ($hardware =~ /video/ && $numero > 0)) {
        my $n_old = $numero;
        test_remove_hardware($vm, $domain, $hardware, 0);
        $domain = Ravada::Domain->open($domain->id);
        @list_hardware1 = $domain->get_controller($hardware);
	    $numero = scalar(@list_hardware1);
        last if $n_old == 1 && scalar(@list_hardware1)==1 && $hardware eq 'video';
    }
    test_display_db($domain,0) if $hardware eq 'display';

    $data = { driver => 'spice' } if !keys %$data && $hardware eq 'display';

    if ( !keys %$data && $hardware eq 'filesystem' ) {
        my $dir = "/var/tmp/".new_domain_name();
        mkdir $dir if ! -e $dir;
        $data = { source => { dir => $dir } }
    }

    if ($hardware eq 'video') {
        Ravada::Request->change_hardware(uid => $USER->id
            ,id_domain => $domain->id
            ,hardware => $hardware
            ,index => 0
            ,data => { driver => 'qxl'}
        );
        wait_request();
    }
    _remove_usbs($domain,$hardware);
	my $req;
    diag("Adding $hardware ".($numero+1)."\n".Dumper($data));
	eval {
		$req = Ravada::Request->add_hardware(uid => $USER->id
                , id_domain => $domain->id
                , name => $hardware
                , number => $numero+1
                , data => $data
            );
	};
	is($@,'') or return;
    $USER->unread_messages();
	ok($req, 'Request');
    sleep 1 if !$TEST_TIMESTAMP;
    wait_request(debug => 1);
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
    my @list_hardware3 = $domain->get_controller($hardware);
    is(scalar(@list_hardware3), $numero+$n) or exit;
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
    return $domain;
}

sub _remove_hardware_video($domain) {
    my $info = $domain->info(user_admin);
    my $video = $info->{hardware}->{video};
    for my $n ( reverse 0 .. scalar(@$video)-1 ) {
        next if $video->[$n]->{type} =~ /qxl/;
        Ravada::Request->remove_hardware(
            name => 'video'
            ,index => $n
            ,id_domain => $domain->id
            ,uid => user_admin->id
        );
    }
    wait_request();
}

sub test_video_primary($domain) {
    my $req = Ravada::Request->add_hardware(
            name => 'video'
            ,uid => user_admin->id
            ,id_domain => $domain->id
            ,data => { 'driver' => 'qxl','primary' => 'yes'}
    );
    wait_request();

    my $driver = $domain->drivers('video');
    for my $option ( $driver->get_options ) {
        _remove_hardware_video($domain);
        my $option_value = lc($option->{name});
        my $info = $domain->info(user_admin);
        my $video = $info->{hardware}->{video};
        my $n;
        for ( 0 .. scalar(@$video)-1 ) {
            $n = $_;
            last if !exists $video->[$n]->{primary}
            || $video->[$n]->{primary} !~ /yes/;
        }
        die "Error: I can't find a non primary video ".Dumper($video)
        if !defined $n;

        my @args = (
            uid => user_admin->id
            ,id_domain => $domain->id
            ,hardware => 'video'
            ,index => $n
        );
        diag($domain->name." $option_value");
        $req = Ravada::Request->change_hardware(
            @args
            ,data => { driver => $option_value}
        );
        wait_request();
    }
}

sub _remove_all_video_but_one($domain, $keep = 'virtio') {
    my $info = $domain->info(user_admin);
    my $video = $info->{hardware}->{video};

    for my $n ( reverse 0 .. scalar(@$video)-1 ) {
        confess Dumper($info->{hardware}) if !exists $video->[$n]->{type};
        next if $video->[$n]->{type} eq $keep;
        Ravada::Request->remove_hardware(name => 'video'
            ,uid => user_admin->id
            ,id_domain => $domain->id
            ,index => $n
        );
    }
    wait_request();

    $info = $domain->info(user_admin);
    $video = $info->{hardware}->{video};

    my $n;
    for ( 0 .. scalar(@$video)-1 ) {
        $n = $_;
        last if $video->[$n]->{type} eq $keep
    }
    return $n if defined $n;

    my $req = Ravada::Request->change_hardware(
        hardware => 'video'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { 'type' => $keep }
        ,index => 0
    );
    wait_request();

    $info = $domain->info(user_admin);
    $video = $info->{hardware}->{video};

    for ( 0 .. scalar(@$video)-1 ) {
        $n = $_;
        last if $video->[$n]->{type} eq 'virtio'
    }

    die "Error: I can't find video virtio ".Dumper($video)
    if !defined $n;

    return $n;
}

sub test_video_vgamem($domain) {
    my $n = _remove_all_video_but_one($domain, 'qxl');
    my @args = (
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'video'
        ,index => $n
    );
    for my $field ( 'vgamem', 'ram' ) {
        for my $type ( 'cirrus', 'qxl','vga', 'virtio','vmvga') {
            Ravada::Request->change_hardware(
                @args
                ,data => { type => 'qxl'
                    ,$field => '16384'
                }
            );
            wait_request( debug => 0);
            my $req = Ravada::Request->change_hardware(
                @args
                ,data => { type => $type
                    ,$field => '16384'
                }
            );
            wait_request( debug => 0);
        }
    }
}

sub test_video_virtio_3d_change_type($domain) {
    my $n = _remove_all_video_but_one($domain);
    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'video'
        ,index => $n
        ,data => { type => 'virtio'
            , acceleration => { accel3d => 'yes'}
        }
    );
    wait_request( debug => 0);

    $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'video'
        ,index => $n
        ,data => { type => 'cirrus'
            , acceleration => { accel3d => 'yes'}
        }
    );
    wait_request(debug => 0);
}

sub test_video_virtio_3d($domain) {
    my $n = _remove_all_video_but_one($domain);

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'video'
        ,index => $n
        ,data => { type => 'virtio'
            , acceleration => { accel3d => 'yes'}
        }
    );
    wait_request( debug => 0);

    _test_kvm_accel3d($domain, 'yes');
    $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'video'
        ,index => $n
        ,data => { type => 'virtio'
            , acceleration => { accel3d => 'no'}
        }
    );
    wait_request( debug => 0);
    _test_kvm_accel3d($domain,'no');
}

sub _test_kvm_accel3d($domain,$value) {
    return if $domain->type ne 'KVM';
    my $xml = XML::LibXML->load_xml(
            string => $domain->domain->get_xml_description()
    );
    my $path = "/domain/devices/video/model/acceleration";
    my ($acceleration ) = $xml->findnodes($path);
    ok($acceleration,"Expecting $path in ".$domain->name)
        or exit;
    is($acceleration->getAttribute('accel3d'), $value)
        or die $domain->name;
}

sub test_add_video($domain) {
    test_add_video_none($domain);
    my $data = { type => 'virtio', heads => 1 };
    test_video_vgamem($domain);
    test_video_virtio_3d_change_type($domain);
    test_video_virtio_3d($domain);
    test_add_hardware_request($domain->_vm,$domain,'video',$data);
    test_video_primary($domain);
}

sub test_add_video_none($domain) {
    my %args = (
        uid => user_admin->id
        ,name => 'video'
        ,id_domain => $domain->id
        ,data => {
            type => 'none'
        }
    );
    my $req = Ravada::Request->add_hardware(%args);
    wait_request();
    is($req->error,'');

    $args{data}->{type} = 'cirrus';
    $req = Ravada::Request->add_hardware(%args);
    wait_request();
    is($req->error,'');


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

sub test_add_filesystem_fail($domain) {
    my @args = (
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'filesystem'
    );
    my $req = Ravada::Request->add_hardware(
        @args
        ,data => { source => { dir => '/home/fail' } }
    );
    wait_request( check_error => 0);
    like($req->error, qr/./);
    is($req->status,'done');

}

sub test_add_filesystem_missing($domain) {
    my @args = (
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'filesystem'
    );
    my $dir = "/var/tmp/".new_domain_name();
    mkdir $dir if ! -e $dir;
    my $req = Ravada::Request->add_hardware(
        @args
        ,data => { source => { dir => $dir } }
    );
    wait_request( check_error => 0);
    is($req->error, '');
    is($req->status,'done');
    rmdir $dir or die "$! $dir";
    $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request( check_error => 0 );
    like($req->error, qr/./);
    is($req->status,'done') or exit;
    my $info = $domain->info(user_admin);
    my $index = scalar (@{$info->{hardware}->{filesystem}})-1;
    Ravada::Request->remove_hardware(
        @args
        ,index => $index
    );
    wait_request( debug => 0);

}

sub test_add_filesystem($domain) {
    test_add_filesystem_missing($domain);
    test_add_filesystem_fail($domain);
}

sub test_add_network_bridge($domain) {

    my $vm = Ravada::VM->open($domain->_data('id_vm'));
    my @bridges = $vm->_list_bridges();
    return if !scalar(@bridges);

    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,name => 'network'
        ,id_domain => $domain->id
        ,data => {
            driver => 'virtio'
            ,type => 'bridge'
            ,bridge => $bridges[0]
        }
    );
    wait_request();
    is($req->error,'');
}

sub test_add_network_nat($domain) {
    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,name => 'network'
        ,id_domain => $domain->id
        ,data => {
            driver => 'virtio'
            ,type => 'NAT'
            ,network => 'default'
        }
    );
    wait_request();
    is($req->error,'');
}

sub test_add_network($domain) {
    test_add_network_bridge($domain);
    test_add_network_nat($domain);
}

sub test_add_hardware_custom($domain, $hardware) {
    return if $hardware =~ /cpu|features/i;
    my %sub = (
        disk => \&test_add_disk
        ,display => sub {}
        ,filesystem => \&test_add_filesystem
        ,usb => sub {}
        ,mock => sub {}
        ,network => \&test_add_network
        ,video => \&test_add_video
        ,sound => sub {}
        ,'usb controller' => sub {}
        ,'memory' => sub {}
    );

    my $exec = $sub{$hardware} or die "No custom add $hardware";
    return $exec->($domain);
}

sub _set_three_devices($domain, $hardware) {
    my %drivers = map { $_ => 1 } @{$domain->info(user_admin)->{drivers}->{$hardware}};
    my $info_hw = $domain->info(user_admin)->{hardware};
    my $items = [];
    $items = $info_hw->{$hardware};

    my $driver_field = _driver_field($hardware);

    for my $item (@$items) {
        next if !ref($item);
        confess "Missing field $driver_field in ". Dumper($item) if !exists $item->{$driver_field};
        delete $drivers{$item->{$driver_field}} if ref($item);
    }
    for my $n (1 .. 3-scalar(@$items)) {
        my @driver;
        if ($hardware eq 'display') {
            my ($driver) = keys %drivers;
            delete $drivers{$driver};
            @driver =( data => { $driver_field => $driver } );
        } elsif ($hardware eq 'filesystem') {
            my $source = "/var/tmp/".new_domain_name();
            mkdir $source if ! -e $source;
            @driver =( data => { source => { dir =>  $source } } )
        }
        Ravada::Request->add_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,name => $hardware
            ,@driver
        );
    }
    wait_request(debug => 0);
}

sub test_remove_hardware_by_index_network_kvm($vm, $hardware) {
    return if $hardware ne 'network' || $vm->type ne 'KVM';

    my $domain = create_domain($vm);
    _set_three_devices($domain, $hardware);

    my $info_hw1 = $domain->info(user_admin)->{hardware};
    my $items1 = [];
    $items1 = $info_hw1->{$hardware};

    $domain->_remove_device(1,"interface", type => qr'(bridge|network)');
    my $info_hw2 = $domain->info(user_admin)->{hardware};
    my $items2 = [];
    $items2 = $info_hw2->{$hardware};

    is($items2->[0]->{name},$items1->[0]->{name});
    is($items2->[1]->{name},$items1->[2]->{name});

    remove_domain($domain);
}


sub test_remove_hardware_by_index($vm, $hardware) {
    return if $hardware eq 'usb';

    my $domain = create_domain($vm);
    _set_three_devices($domain, $hardware);
    my $info_hw1 = $domain->info(user_admin)->{hardware};
    my $items1 = [];
    $items1 = $info_hw1->{$hardware};

    my $index = scalar(@$items1)-1;

    Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $hardware
        ,index => $index
    );
    wait_request();
    my $info_hw2 = $domain->info(user_admin)->{hardware};
    my $items2 = [];
    $items2 = $info_hw2->{$hardware};
    my $name_field = 'name';
    $name_field = 'driver'  if $hardware eq 'display';
    $name_field = 'model'   if $hardware eq 'sound';
    $name_field = '_name'   if ref($items2->[0]) && !exists $items2->[0]->{$name_field};
    if (!ref($items2->[0])) {
        is($items2->[0], $items1->[0]);
        is($items2->[1], $items1->[2]);
    } elsif ($hardware !~ /^(usb controller|video)$/) {
        die "Error: no $name_field in ".Dumper($items2) if !exists $items2->[0]->{$name_field};

        is($items2->[0]->{$name_field},$items1->[0]->{$name_field});
        is($items2->[1]->{$name_field},$items1->[2]->{$name_field});
    }

    $domain->remove(user_admin);
}

sub test_remove_hardware($vm, $domain, $hardware, $index) {

    $domain->shutdown_now(user_admin)   if $domain->is_active;
    $domain = Ravada::Domain->open($domain->id);
    my @list_hardware1 = $domain->get_controller($hardware);

    confess "Error: I can't remove $hardware $index, only ".scalar(@list_hardware1)
        ."\n"
        .Dumper(\@list_hardware1)
            if $index > scalar @list_hardware1;

    $index = scalar(@list_hardware1)-1 if $index ==-1;
    confess "Error: I can't remove index $index for $hardware"
    if $hardware eq 'usb controller' && $index<1;

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
    wait_request(debug => 0);
	is($req->status(), 'done');
	is($req->error(), '') or exit;


    # there is no poing in checking if removed because
    # a new video device will be created when there is none
    return if $hardware eq 'video' && scalar(@list_hardware1)==1;

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
    my @hw = $domain->get_controller($hardware);
    my $total_hardware = scalar(@hw);
    return if !defined $total_hardware || $total_hardware <= $n_keep;
    for my $index ( reverse 0 .. $total_hardware-1) {
        diag("removing $hardware $index");
        test_remove_hardware($vm, $domain, $hardware, $index);
        $domain->list_volumes() if $hardware eq 'disk';
    }
}

sub test_front_hardware {
    my ($vm, $domain, $hardware ) = @_;

    _set_three_devices($domain, $hardware)
    if $hardware eq 'filesystem';

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

sub test_change_disk_nothing($vm, $domain) {
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info = $domain_f->info(user_admin);

    my $hardware = 'disk';

    for my $count ( 0 .. scalar(@{$info->{hardware}->{$hardware}}) -1 ) {
        my $data= $info->{hardware}->{$hardware}->[$count];
        my $req = Ravada::Request->change_hardware(
            id_domain => $domain_f->id
            ,uid => user_admin->id
            ,hardware => $hardware
            ,index => $count
            ,data => $data
        );
        wait_request($req);
        my $domain2 = Ravada::Front::Domain->open($domain->id);
        my $info2 = $domain_f->info(user_admin);
        my $data2= $info2->{hardware}->{$hardware}->[$count];

        delete $data2->{backing} if
        exists $data2->{backing}
        && $data2->{backing}
        && $data2->{backing} eq '<backingStore/>'
        && !exists $data->{backing};

        is_deeply($data2, $data)
            or die Dumper([$domain->name, $data2, $data]);
    }

}

sub test_change_disk_settings($vm, $domain) {
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info = $domain_f->info(user_admin);

    my $hardware = 'disk';

    my $index;
    my $item;

    for my $count ( 0 .. scalar(@{$info->{hardware}->{$hardware}}) -1 ) {
        $item = $info->{hardware}->{$hardware}->[$count];
        next if $item->{device} ne 'disk';

        $index = $count;
        last;
    }
    confess "Device disk not found ".$domain->name
    ."\n".Dumper($info->{hardware}->{$hardware})
    if !defined $index;

    my $item2 = dclone($item);
    $item2->{driver}->{'$$hashKey'} = 'object:105';

    for my $cache (qw(default none writethrough writeback directsync
            unsafe)) {
            my $item3 = dclone($item2);
            $item3->{driver}->{cache}=$cache;
            my $req = Ravada::Request->change_hardware(
                id_domain => $domain_f->id
                ,uid => user_admin->id
                ,hardware => $hardware
                ,index => $index
                ,data => $item3
            );
            wait_request(debug => 0);
    }

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
    ok($cdrom) or confess "No cdrom in ".$domain->name;
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
    test_change_disk_settings($vm, $domain);
    test_change_disk_nothing($vm, $domain);
    test_change_disk_field($vm, $domain, 'capacity');
    test_change_disk_cdrom($vm, $domain);
}

sub test_change_network_bridge($vm, $domain, $index) {
    SKIP: {
    my @bridges = $vm->list_network_interfaces('bridge');

    skip("No bridges found in this system",6) if !scalar @bridges;
    my $info = $domain->info(user_admin);
    if ($info->{hardware}->{network}->[$index]->{type} eq 'bridge') {
        my $req = Ravada::Request->change_hardware(
            id_domain => $domain->id
            ,hardware => 'network'
            ,index => $index
            ,data => { type => 'NAT', network => 'default'}
            ,uid => user_admin->id
        );
        wait_request();

    }

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
    _test_change_defaults($domain,'network');
}

sub test_change_filesystem($vm,$domain) {

    my $list_hw_fs = $domain->info(user_admin)->{hardware}->{filesystem};

    my $hw_fs0 = $list_hw_fs->[0];

    my $new_source = "/var/tmp/".new_domain_name();
    mkdir $new_source if ! -e $new_source;
    my $data = dclone($hw_fs0);
    $data->{source}->{dir} = $new_source;

    my %args = (
        hardware => 'filesystem'
        ,index => 0
        ,data => $data
        ,uid => user_admin->id
        ,id_domain => $domain->id
    );
    my $req = Ravada::Request->change_hardware(%args);
    wait_request(debug => 0);

    my $domain2 = Ravada::Domain->open($domain->id);
    my $list_hw_fs2 = $domain2->info(user_admin)->{hardware}->{filesystem};
    my ($hw_fs2) = grep { $_->{_id} == $data->{_id} } @$list_hw_fs2;
    ok($hw_fs2) or die Dumper($list_hw_fs2);
    is($hw_fs2->{source}->{dir}, $new_source);
    ok($hw_fs2->{_id}) or die Dumper($hw_fs2);
    is($hw_fs2->{_id},$hw_fs0->{_id});
}

sub _test_change_defaults($domain,$hardware) {
    my @args = (
        hardware => $hardware
        ,id_domain => $domain->id
        ,uid => user_admin->id
        ,index => 0
    );
    my $req = Ravada::Request->change_hardware(
        @args
        ,data => {}
    );
    wait_request();

}

sub _test_cpu_features_topology($domain) {

    $domain->shutdown_now() if $domain->is_active;

    my $doc = XML::LibXML->load_xml(string => $domain->xml_description);

    my ($type) = $doc->findnodes("/domain/os/type");
    my ($cpu) = $doc->findnodes("/domain/cpu");

    my ($model ) = $cpu->findnodes("model");
    $model = $cpu->addNewChild(undef,'model') if !$model;
    $model->setAttribute('fallback'=>'forbid');

    $domain->reload_config($doc);

    my @feature;
    for my $name ('x2apic', 'hypervisor', 'lahf_lm') {
        push @feature, { name => $name, policy => 'require'}
    }
    my $req = Ravada::Request->change_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,hardware =>'cpu'
            ,data => { cpu => { feature => \@feature } }
        );
        wait_request($req);
        is($req->error,'');
    $domain = Ravada::Domain->open($domain->id);
    my $doc2 = XML::LibXML->load_xml(string => $domain->xml_description);
    my ($cpu2) = $doc2->findnodes("/domain/cpu");

    my $topology = { sockets => 1
                        ,dies => 1
                        ,cores => 1
                        , threads => 2
    };

    $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware =>'cpu'
        ,data => {
            cpu => { 'topology'=> $topology, feature => \@feature }
        }
    );
    wait_request($req);
    is($req->error, '');

    $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware =>'cpu'
        ,data => {
            cpu => { 'topology'=> $topology, feature => [] }
        }
    );
    wait_request($req);
    is($req->error, '');

}

sub _test_cpu_topology_old_cpu($domain) {

    my $doc = XML::LibXML->load_xml( string => $domain->xml_description());
    my ($cpu) = $doc->findnodes("/domain/cpu");
    $cpu->setAttribute('mode' => 'host-model');
    $cpu->setAttribute('check' => 'partial');
    $cpu->removeAttribute('match');

    my ($model) = $cpu->findnodes('model');
    $cpu->removeChild($model);

    $domain->reload_config($doc);

    my $model_exp = 'kvm64';

    my %args = (
        uid => user_admin->id
        ,hardware => 'cpu'
        ,id_domain => $domain->id
        ,data => {
            'cpu' => {
                'topology' => {
                    'cores' => 1,
                    'dies' => 1,
                    'threads' => 2,
                    'sockets' => 1
                },
                'feature' => [],
                'model' => {
                    'fallback' => 'allow',
                    '#text' => $model_exp
                },
                'mode' => 'custom',
                'check' => 'none'
            },
            'vcpu' => {
                'placement' => 'static',
                '#text' => 24
            },
            '_can_edit' => 1,
            '_cat_remove' => 0,
            '_order' => 0
        },
    );
    my $req = Ravada::Request->change_hardware(%args);
    wait_request(debug => 0);

    $doc = XML::LibXML->load_xml( string => $domain->xml_description());
    my ($model2) = $doc->findnodes("/domain/cpu/model/text()");
    is($model2,$model_exp) or exit;

    $model_exp = 'qemu64';

    $args{data}->{cpu}->{model}->{'#text'} = $model_exp;

    my $req2 = Ravada::Request->change_hardware(%args);
    wait_request(debug => 0);

    $doc = XML::LibXML->load_xml( string => $domain->xml_description());

    my ($model3) = $doc->findnodes("/domain/cpu/model/text()");
    is($model3,$model_exp) or exit;

    my ($cpu3) = $doc->findnodes("/domain/cpu");
    is($cpu3->getAttribute('mode'),'custom');
}

sub _test_change_cpu($vm, $domain) {

    _test_cpu_features_topology($domain);

    _test_cpu_features($domain);
    _test_cpu_topology_empty($domain);
    _test_change_cpu_topology($domain);
    _test_change_defaults($domain,'cpu');

    _test_cpu_topology_old_cpu($domain);
}

sub _test_change_cpu_topology($domain) {
    diag("testing cpu topology");
    for my $dies ( reverse 1 .. 3 ) {
        for my $sockets ( reverse 1 .. 3 ) {
            for my $cores ( reverse 1 .. 3 ) {
                for my $threads ( reverse 1 .. 3 ) {

                    my $topology = { sockets => $sockets
                        ,dies => $dies
                        ,cores => $cores
                        , threads => $threads
                    };

                    my $req = Ravada::Request->change_hardware(
                        uid => user_admin->id
                        ,id_domain => $domain->id
                        ,hardware =>'cpu'
                        ,data => {
                              cpu => { 'topology'=> $topology}
                        }
                    );
                    wait_request($req);
                    is($req->error, '');
                    is($req->status,'done');

                    my $doc = XML::LibXML->load_xml( string => $domain->xml_description());
                    my ($xml_topology) = $doc->findnodes("/domain/cpu/topology");
                    ok($xml_topology) or exit;
                    for my $field ( keys %$topology ) {
                        is($xml_topology->getAttribute($field)
                            ,$topology->{$field},$field) or exit;
                    }
                }
            }
        }
    }
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware =>'cpu'
        ,data => { }
    );
    wait_request($req);
    is($req->error, '');
    is($req->status,'done');

    my $doc = XML::LibXML->load_xml( string => $domain->xml_description());
    my ($xml_cpu) = $doc->findnodes("/domain/cpu");
    my ($xml_topology) = $doc->findnodes("/domain/cpu/topology");
    ok(!$xml_topology) or die $xml_cpu->toString();

}

sub _test_cpu_features($domain) {
    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware =>'cpu'
        ,data => { cpu => { feature => [
                        {name => 'acpi' ,policy => 'require'}
                ] } }
    );
    wait_request($req);
    is($req->error, '');
    is($req->status,'done');

}

sub _test_cpu_topology_empty($domain) {
    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware =>'cpu'
        ,data => { cpu => { 'topology'=> undef } }
    );
    wait_request($req);
    is($req->error, '');
    is($req->status,'done');
}

sub _test_change_features($vm, $domain) {
    _test_change_defaults($domain,'cpu');
}

sub test_change_display($vm, $domain) {
    _test_change_defaults($domain,'display');
}

sub _test_change_memory($vm, $domain) {

    for ( 1 .. 3 ) {
        my $info = $domain->info(user_admin);
        my $hw_mem = $info->{hardware}->{memory}->[0];
        my $new_mem = int($hw_mem->{memory}*1.5);
        my $req = Ravada::Request->change_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,hardware =>'memory'
            ,data => { memory => $new_mem*1024,max_mem => ($new_mem+1)*1024 }
            ,index => 0
        );
        wait_request(debug => 0);
        is($req->error, '');
        is($req->status,'done');

        my $info2 = $domain->info(user_admin);
        my $hw_mem2 = $info2->{hardware}->{memory}->[0];
        is($hw_mem2->{memory}, $new_mem);
        is($hw_mem2->{max_mem}, $new_mem+1);
    }
}

sub test_change_hardware($vm, $domain, $hardware) {
    my %sub = (
      network => \&test_change_network
        ,disk => \&test_change_disk
        ,filesystem => \&test_change_filesystem
        ,mock => sub {}
         ,usb => sub {}
         ,display => \&test_change_display
         ,video => sub {}
         ,sound => sub {}
         ,cpu => \&_test_change_cpu
         ,features => \&_test_change_features
         ,'usb controller' => sub {}
         ,'memory' => \&_test_change_memory
    );
    my $exec = $sub{$hardware} or die "I don't know how to test $hardware";
    $exec->($vm, $domain);
}

sub _remove_usbs($domain, $hardware) {

    return unless $domain->type eq 'KVM'
    && $hardware =~ /usb|disk/;

    my $info = $domain->info(user_admin);

    return if !exists $info->{hardware}->{usb}
    || scalar(@{$info->{hardware}->{usb}} < 3);

    Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'usb'
        ,index => 0
    );
    wait_request();
}

sub test_change_drivers($domain, $hardware) {

    return if $domain->type eq 'Void' && $hardware eq 'network';

    _remove_usbs($domain, $hardware);

    my $info = $domain->info(user_admin);
    my $options = $info->{drivers}->{$hardware};
    ok(scalar @$options,"No driver options for $hardware") or exit;
    for my $option ( @$options ) {
        is(ref($option),'',"Invalid option for driver $hardware") or exit;
    }

    my $driver_field = _driver_field($hardware);

    for my $option (@$options) {
        my $index = 0;
        $index = _search_disk($domain) if $hardware eq 'disk';

        $index = scalar(@{$info->{hardware}->{"usb controller"}}) -1
        if $hardware eq 'usb controller';

        diag("Testing $hardware type $option in $hardware $index");
        $option = lc($option);
        my $req = Ravada::Request->change_hardware(
            id_domain => $domain->id
            ,hardware => $hardware
            ,index => $index
            ,data => { $driver_field => $option }
            ,uid => user_admin->id
        );

        wait_request(debug => 0);

        is($req->status,'done');
        is($req->error, '') or exit;

        my $domain_f = Ravada::Front::Domain->open($domain->id);
        $info = $domain_f->info(user_admin);

        die "Error: no field $driver_field in $hardware [$index] ".Dumper($info->{hardware}->{$hardware}->[$index])
        if !exists $info->{hardware}->{$hardware}->[$index]->{$driver_field};

        is ($info->{hardware}->{$hardware}->[$index]->{$driver_field}, $option
        ,Dumper($domain_f->name,$info->{hardware}->{$hardware}->[$index])) or exit;

        my $domain_b = Ravada::Domain->open($domain->id);
        my $info_b = $domain_b->info(user_admin);
        is ($info_b->{hardware}->{$hardware}->[$index]->{$driver_field}, $option
        ,Dumper($info_b->{hardware}->{$hardware}->[$index])) or exit;

        $domain_b->start(user_admin);
        is($domain_b->is_active,1);
        $info_b = $domain_b->info(user_admin);
        is ($info_b->{hardware}->{$hardware}->[$index]->{$driver_field}, $option
        ,Dumper($info_b->{hardware}->{$hardware}->[$index])) or exit;
        $domain_b->shutdown_now(user_admin);
    }
}

sub test_all_drivers($domain, $hardware) {

    return if $domain->type eq 'Void' && $hardware eq 'network';

    my $info = $domain->info(user_admin);
    my $options = $info->{drivers}->{$hardware};
    ok(scalar @$options,"No driver options for $hardware") or exit;
    my $index = int(scalar(@{$info->{hardware}->{$hardware}}) / 2);

    my $domain_b = Ravada::Domain->open($domain->id);
    if ($hardware eq 'video') {
        for ( 1 .. 4 ) {
            Ravada::Request->remove_hardware(
                id_domain => $domain->id
                ,uid => user_admin->id
                ,name => $hardware
                ,index => 0
            );
        }
        wait_request();
    }

    my $driver_field = _driver_field($hardware);
    for my $option1 (@$options) {
        for my $option2 (@$options) {
            # diag("Testing $hardware type from $option1 to $option2");
            next if $hardware eq 'usb controller'
            && $option1 eq 'nec-xhci' &&
            ( $option2 eq 'nec-xhci' || $option2 eq 'pixx3-uhci');

            my $req = Ravada::Request->change_hardware(
                id_domain => $domain->id
                ,hardware => $hardware
                ,index => $index
                ,data => { $driver_field => lc($option1) }
                ,uid => user_admin->id
            );
            rvd_back->_process_requests_dont_fork();

            is($req->status,'done');
            is($req->error, '') or exit;
            $req = Ravada::Request->change_hardware(
                id_domain => $domain->id
                ,hardware => $hardware
                ,index => $index
                ,data => { $driver_field => lc($option2) }
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
        return reverse @base;
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

clean();
remove_old_domains();
remove_old_disks();

for my $vm_name (vm_names()) {
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
	my $domain_b0 = $BASE->clone(
        name => new_domain_name()
        ,user => $USER
        ,memory => 500 * 1024
    );
    test_remove_display($vm);
    my %controllers = $domain_b0->list_controllers;
    lock_hash(%controllers);

    for my $hardware ('video', sort keys %controllers ) {
	    my $name= new_domain_name();
	    my $domain_b = $BASE->clone(
            name => $name
            ,user => $USER
            ,memory => 500 * 1024
        );

        diag("Testing $hardware controllers for VM $vm_name");
        if ($hardware !~ /cpu|features|memory/) {
            test_remove_hardware_by_index($vm, $hardware);
            test_remove_hardware_by_index_network_kvm($vm, $hardware);
            test_add_hardware_request($vm, $domain_b, $hardware);
            my $n = 0;
            $n = -1 if $hardware eq 'usb controller';
            test_remove_hardware($vm, $domain_b, $hardware, $n);
            test_add_hardware_request_drivers($vm, $domain_b, $hardware);
            test_add_hardware_request($vm, $domain_b, $hardware);
        }


        test_front_hardware($vm, $domain_b, $hardware);

        test_add_hardware_custom($domain_b, $hardware);
        test_change_hardware($vm, $domain_b, $hardware);

        # change driver is not possible for displays
        test_change_drivers($domain_b, $hardware)   if $hardware !~ /^(display|filesystem|usb|mock|features|cpu|usb controller|memory)$/;
        test_all_drivers($domain_b, $hardware)   if $hardware !~ /^(display|filesystem|usb|mock|features|memory)$/;

        # try to add with the machine started
        $domain_b->start(user_admin) if !$domain_b->is_active;
        ok($domain_b->is_active) or next;


        $domain_b->shutdown_now(user_admin) if $domain_b->is_active;
        is($domain_b->is_active,0) or next;

        if ( $hardware !~ /memory|cpu|features|usb/ ) {
            for (1 .. 3 ) {
                test_add_hardware_request($vm, $domain_b, $hardware);
            }
        }



        $domain_b->shutdown_now(user_admin) if $domain_b->is_active;
        ok(!$domain_b->is_active);
        $domain_b->remove(user_admin);
        }

    $domain_b0->remove(user_admin);
    }
    ok($TEST_TIMESTAMP);
}

end();
done_testing();
