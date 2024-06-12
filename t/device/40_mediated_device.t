use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Mojo::JSON qw( encode_json decode_json );
use YAML qw(Load Dump  LoadFile DumpFile);

use Ravada::HostDevice::Templates;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE;
my $MOCK_MDEV;
my $N_TIMERS;

####################################################################

sub _prepare_dir_mdev() {

    my $dir = "/run/user/";

    $dir .= "$</" if $<;
    $dir .= new_domain_name();

    mkdir $dir or die "$! $dir"
    if ! -e $dir;

    my $uuid="3913694f-ca45-a946-efbf-94124e5c09";

    for (1 .. 2 ) {
        open my $out, ">","$dir/$uuid$_$_ " or die $!;
        print $out "\n";
        close $out;
    }
    return $dir;
}

sub _check_mdev($vm, $hd) {

    my $n_dev = $hd->list_available_devices();
    return _check_used_mdev($vm, $hd) if $n_dev;

    my $dir = _prepare_dir_mdev();
    $hd->_data('list_command' => "ls $dir");

    $MOCK_MDEV=1 unless $vm->type eq 'Void';
    return $hd->list_available_devices;;
}

sub _check_used_mdev($vm, $hd) {
    return $hd->list_available_devices() if $vm->type eq 'Void';

    my @active = $vm->vm->list_domains;
    for my $dom (@active) {
        my $doc = XML::LibXML->load_xml(string => $dom->get_xml_description);

        my $hd_path = "/domain/devices/hostdev/source/address";
        my ($hostdev) = $doc->findnodes($hd_path);
        next if !$hostdev;

        my $uuid = $hostdev->getAttribute('uuid');
        if (!$uuid) {
            warn "No uuid in ".$hostdev->toString;
            next;
        }
        my $dom_imported = rvd_front->search_domain($dom->get_name);
        $dom_imported = $vm->import_domain($dom->get_name,user_admin)
        unless $dom_imported;

        $dom_imported->add_host_device($hd->id);
        my ($dev) = grep /^$uuid/, $hd->list_devices;
        if (!$dev) {
            warn "No $uuid found in mdevctl list";
            next;
        }
        $dom_imported->_lock_host_device($hd, $dev);
    }
    return $hd->list_available_devices();
}

sub _req_start($domain) {
    if ($MOCK_MDEV) {
        $domain->_attach_host_devices();
    } else {
                diag("Starting for real ".$domain->name." MOCK_MDEV=".($MOCK_MDEV or 0));
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request();
    }
}

sub _req_shutdown($domain) {
    #    $domain->_dettach_host_devices();
    my $req = Ravada::Request->shutdown_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,timeout => 1
    );
    wait_request();

    for ( 1 .. 10 ) {
        last if !$domain->is_active;
        diag("Waiting for ".$domain." down");
        sleep 1;
    }

}

sub test_mdev($vm) {

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($mdev) = grep { $_->{name} eq "GPU Mediated Device" } @$templates;
    ok($mdev,"Expecting PCI template in ".$vm->name) or return;

    my $id = $vm->add_host_device(template => $mdev->{name});
    my $hd = Ravada::HostDevice->search_by_id($id);

    my $n_devices = _check_mdev($vm, $hd);
    is( $hd->list_available_devices() , $n_devices);

    my $domain = $BASE->clone(
        name =>new_domain_name
        ,user => user_admin
    );
    test_config_no_hd($domain);
    $domain->add_host_device($id);
    _req_start($domain);
    is($hd->list_available_devices(), $n_devices-1);
    test_config($domain);

    sleep 1;
    _req_shutdown($domain);
    for ( 1 .. 3 ) {
        last if $hd->list_available_devices() >= $n_devices;
        _req_shutdown($domain);
        sleep 1;
    }
    #    $domain->_dettach_host_devices();
    is($hd->list_available_devices(), $n_devices) or die $domain->name;

    test_change_ram($domain);

    test_config_no_hd($domain);

    return ($domain, $hd);
}

sub test_change_ram($domain) {
    my $info = $domain->info(user_admin);
    my ($memory, $max_mem) = ($info->{memory}, $info->{max_mem});

    my $new_memory = int(($memory+1) * 1.5)+1;
    my $new_max_mem= int(($max_mem+1) * 1.6)+2;

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'memory'
        ,id_domain => $domain->id
        ,data => {
            memory => $new_memory
            ,max_mem => $new_max_mem
        }
    );
    wait_request(debug => 0);

    my $info1 = $domain->info(user_admin);
    my ($memory1, $max_mem1) = ($info1->{memory}, $info1->{max_mem});
    is($memory1, $new_memory) or die $domain->name;
    is($max_mem1, $new_max_mem);

    _req_start($domain);

    my $info2 = $domain->info(user_admin);
    my ($memory2, $max_mem2) = ($info2->{memory}, $info2->{max_mem});
    is($memory2, $new_memory) or die $domain->name;
    is($max_mem2, $new_max_mem);
    Ravada::Request->shutdown_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,timeout => 1
    );
    wait_request();

    my $info3 = $domain->info(user_admin);
    my ($memory3, $max_mem3) = ($info3->{memory}, $info3->{max_mem});
    is($memory3, $new_memory);
    is($max_mem3, $new_max_mem);
}

sub _change_state_on($domain) {
    if ($domain->type eq 'KVM') {
        _change_kvm_state_on($domain);
    } elsif ($domain->type eq 'Void') {
        _change_void_state_on($domain);
    }
}

sub _change_void_state_on($domain) {
    my $config = $domain->_load();
    my $features = ($config->{features} or {});
    $features->{hidden}='on';
    $domain->_store(features => $features);
}

sub _change_kvm_state_on($domain) {
    my $xml = $domain->xml_description();
    my $doc = XML::LibXML->load_xml(string => $xml);

    my $kvm_path = "/domain/features/kvm";
    my ($kvm) = $doc->findnodes($kvm_path);
    if (!$kvm) {
        my ($features) = $doc->findnodes("/domain/features");
        $kvm = $features->addNewChild(undef,'kvm');
        my $hidden = $kvm->addNewChild(undef, 'hidden');
        $hidden->setAttribute('state' => 'on');
    }
    ok($kvm,"Expecting $kvm_path") or return;
    my ($state) = $kvm->findnodes("hidden");
    is($state->getAttribute('state'),'on');

    $domain->reload_config($doc);
}

sub _change_timer($domain) {
    if ($domain->type eq 'KVM') {
        _change_timer_kvm($domain);
    } elsif ($domain->type eq 'Void') {
        _change_timer_void($domain);
    } else {
        die $domain->type;
    }
}

sub _base_timers_void($domain) {
    my $config = $domain->_load();
    my $clock = ($config->{clock} or []);
    my @timers = (
        { name => 'rtc', tickpolicy => 'catchup'}
        ,{ name => 'pit', tickpolicy => 'delay'}
        ,{ name => 'hpet', present => 'no'}
    );
    for my $timer (@timers) {
        push @$clock ,({timer => $timer });
    }
    $domain->_store(clock => $clock);
}

sub _change_timer_void($domain) {
    _base_timers_void($domain);
    my $config = $domain->_load();
    my $clock = $config->{clock};

    $N_TIMERS = scalar(@$clock);

    $domain->_store(clock => $clock);
}

sub _change_timer_kvm($domain) {

    my $doc = XML::LibXML->load_xml(string => $domain->xml_description());

    my $timer;
    for (my ($node) = $doc->findnodes("/domain/clock/timer") ) {
        $timer = $node if $node->getAttribute('name' eq 'tsc');
    }
    return if $timer;
    my ($clock) = $doc->findnodes("/domain/clock");
    for my $timer ( $clock->findnodes("timer") ) {
        $clock->removeChild($timer) if $timer->getAttribute('name') eq 'tsc';
    }

    my @timers = $doc->findnodes("/domain/clock/timer");
    $N_TIMERS = scalar(@timers);

    $domain->reload_config($doc);

}

sub test_timer($domain, $field, $value) {
    my ($timers,$timer_tsc);
    if ($domain->type eq 'KVM') {
       ($timers, $timer_tsc)=_get_timer_kvm($domain);
    } elsif ($domain->type eq 'Void') {
       ($timers, $timer_tsc)= _get_timer_void($domain);
    } else {
        die $domain->type;
    }
    is(scalar(@$timers), $N_TIMERS+1);
    is(scalar(@$timer_tsc), 1);
    is($timer_tsc->[0]->{$field},$value) or confess Dumper([$domain->name,$timer_tsc]);

}

sub test_no_timer($domain) {
    my ($timers,$list_timer_tsc);
    my $expected_tsc = undef;
    if ($domain->type eq 'KVM') {
       ($timers, $list_timer_tsc)=_get_timer_kvm($domain);
    } elsif ($domain->type eq 'Void') {
       ($timers, $list_timer_tsc)= _get_timer_void($domain);
    } else {
        die $domain->type;
    }
    is(scalar(@$timers), $N_TIMERS) or confess $domain->name;
    is(scalar(@$list_timer_tsc),0);
    my $timer_tsc = $list_timer_tsc->[0];
    is_deeply($timer_tsc, $expected_tsc) or confess Dumper($timer_tsc);

}
sub _get_timer_kvm($domain) {
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description());
    my ($clock) = $doc->findnodes("/domain/clock");
    my @timers = $doc->findnodes("/domain/clock/timer");
    my @found_tsc;
    for my $node (@timers) {
        if ( $node->getAttribute('name') eq'tsc') {
            my $found_tsc = {};
            for my $attrib ($node->attributes) {
                $found_tsc->{$attrib->name}= $attrib->value;
            }
            push @found_tsc,($found_tsc);
        }
    }
    return (\@timers,\@found_tsc);
}

sub _get_timer_void($domain) {
    my $config = $domain->_load();
    my $timers = $config->{clock};

    my @found_tsc;
    for my $timer (@$timers) {
        die Dumper([$domain->name,$timer]) if ref($timer) ne 'HASH';
        die Dumper([$domain->name,$timer]) if !exists $timer->{timer}->{name};

        if ( $timer->{timer}->{name} eq 'tsc') {
            push @found_tsc , ($timer->{timer});
        }
    }
    return ($timers,\@found_tsc);
}

sub _add_template_timer_void($hd) {
    my $sth = connector->dbh->prepare(
        "INSERT INTO host_device_templates "
        ."( id_host_device, path, template,type )"
        ."values( ?, '/clock', ? , 'node')"
    );
    $sth->execute($hd->id,Dump({ timer => { name => 'tsc', present => 'yes' }}))
}

sub _add_template_timer_kvm($hd) {
    my $sth = connector->dbh->prepare(
        "INSERT INTO host_device_templates "
        ."( id_host_device, path, template,type )"
        ."values( ?, '/domain/clock/timer', ? , 'node')"
    );
    $sth->execute($hd->id,"<timer name ='tsc' present='yes'/>" )
}

sub _add_template_timer($hd) {
    my $vm = Ravada::VM->open($hd->id_vm);
    if ($vm->type eq 'Void') {
        _add_template_timer_void($hd);
    } else {
        _add_template_timer_kvm($hd);
    }
}

sub test_mdev_kvm_state($vm) {

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($mdev) = grep { $_->{name} eq "GPU Mediated Device" } @$templates;
    ok($mdev,"Expecting PCI template in ".$vm->name) or return;

    my $id = $vm->add_host_device(template => $mdev->{name});
    my $hd = Ravada::HostDevice->search_by_id($id);

    my $n_devices = _check_mdev($vm, $hd);

    _add_template_timer($hd);

    is( $hd->list_available_devices() , $n_devices);

    my $domain = $BASE->clone(
        name =>new_domain_name
        ,user => user_admin
    );
    _change_state_on($domain);
    _change_timer($domain);
    test_hidden($domain);
    test_no_timer($domain);
    $domain->add_host_device($id);

    _req_start($domain);

    test_hidden($domain);
    test_old_in_locked($domain);
    test_timer($domain,'present' => 'yes');

    _req_shutdown($domain);
    $domain->_dettach_host_devices();

    diag("Test hidden after dettach");
    test_hidden($domain);
    test_no_timer($domain);

    $domain->remove(user_admin);
    $hd->remove();

}

sub test_old_in_locked($domain) {
    my $sth = connector->dbh->prepare("SELECT config_no_hd FROM domains d "
        ." WHERE id=?"
    );
    $sth->execute($domain->id);
    my ($old) = $sth->fetchrow();
    like($old,qr/\w/);
}

sub test_hidden($domain) {

    if ($domain->type eq 'KVM') {
        test_hidden_kvm($domain);
    } else {
        test_hidden_void($domain);
    }
}

sub test_hidden_void($domain) {
    my $config = $domain->_load();
    is($config->{features}->{hidden},'on') or exit;
}

sub test_hidden_kvm($domain) {
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description());
    my $state_path = "/domain/features/kvm/hidden";
    my ($hidden) = $doc->findnodes($state_path);
    ok($hidden,"Missing $state_path ".$domain->name) or confess;
}

sub test_config($domain) {

    if ($domain->type eq'KVM') {
        test_xml($domain);
    } elsif ($domain->type eq 'Void') {
        test_yaml($domain);
    } else {
        die "unknown type ".$domain->type;
    }
}

sub test_config_no_hd($domain){
    if ($domain->type eq'KVM') {
        test_xml_no_hd($domain);
    } elsif ($domain->type eq 'Void') {
        test_yaml_no_hd($domain);
    } else {
        die "unknown type ".$domain->type;
    }

}

sub test_yaml($domain) {
    my $config = $domain->_load();

    my $hd= $config->{hardware}->{host_devices};
    ok($hd) or confess;

    my $features = $config->{features};
    ok($features);

}

sub test_yaml_no_hd($domain) {
    my $config = $domain->_load();

    my $hd= $config->{hardware}->{host_devices};
    ok(!$hd) or confess;

    my $features = $config->{features};
    ok(!$features || !keys(%$features)) or confess(Dumper($features));
}


sub test_xml($domain) {

    my $xml = $domain->xml_description();

    my $doc = XML::LibXML->load_xml(string => $xml);

    my $hd_path = "/domain/devices/hostdev";
    my ($hostdev) = $doc->findnodes($hd_path);
    ok($hostdev,"Expecting $hd_path") or exit;

    my ($video) = $doc->findnodes("/domain/devices/video/model");
    my $v_type = $video ->getAttribute('type');
    isnt($v_type,'none') or exit;

    my $kvm_path = "/domain/features/kvm/hidden";
    my ($kvm) = $doc->findnodes($kvm_path);
    ok($kvm,"Expecting $kvm_path") or return;
    is($kvm->getAttribute('state'),'on')

}

sub test_xml_no_hd($domain) {

    my $xml = $domain->xml_description();

    my $doc = XML::LibXML->load_xml(string => $xml);

    my $hd_path = "/domain/devices/hostdev";
    my ($hostdev) = $doc->findnodes($hd_path);
    ok(!$hostdev,"Expecting no $hd_path") or exit;
    my $model = "/domain/devices/video/model";
    my ($video) = $doc->findnodes($model);
    ok($video,"Expecting a $model ".$domain->name) or exit;
    my $v_type = $video ->getAttribute('type');
    isnt($v_type,'none') or exit;

    my $kvm_path = "/domain/features/kvm/hidden";
    my ($kvm) = $doc->findnodes($kvm_path);
    ok(!$kvm,"Expecting no $kvm_path in ".$domain->name) or confess;
}


sub test_base($domain) {

    my @args = ( uid => user_admin->id ,id_domain => $domain->id);

    Ravada::Request->shutdown_domain(@args);
    my $req = Ravada::Request->prepare_base(@args);

    wait_request();

    test_config_no_hd($domain);

    Ravada::Request->clone(@args, number => 2, remote_ip => '1.2.3.4');
    wait_request();
    is(scalar($domain->clones),2);

    for my $clone_data( $domain->clones ) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->_attach_host_devices();
        test_config($clone);
        $clone->remove(user_admin);
    }
}

sub test_volatile_clones($vm, $domain, $host_device) {
    my @args = ( uid => user_admin->id ,id_domain => $domain->id);

    $domain->shutdown_now(user_admin) if $domain->is_active;

    Ravada::Request->prepare_base(@args) if !$domain->is_base();
    wait_request();
    my $n_devices = $host_device->list_available_devices();
    ok($n_devices) or exit;

    $domain->_data('volatile_clones' => 1);
    my @old_clones = $domain->clones;

    my $n=2;
    my $max_n_device = $host_device->list_available_devices();
    return if $max_n_device<2;
    my $exp_avail = $host_device->list_available_devices()- $n;

    Ravada::Request->clone(@args, number => $n, remote_ip => '1.2.3.4');
    wait_request(check_error => 0);
    is(scalar($domain->clones), scalar(@old_clones)+$n);

    my $found_active=0;
    for my $clone ($domain->clones) {
        $found_active ++ if $clone->{status} =~ /(active|starting)/;
        next if grep { $_->{name} eq $clone->{name} } @old_clones;
        ok($clone->{status} =~ /(active|starting)/, $clone->{name}) or exit;
    }
    is($found_active, $n);

    my $n_device = $host_device->list_available_devices();
    is($n_device,$exp_avail);

    for my $clone_data( $domain->clones ) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        is($clone->is_active,1) unless $MOCK_MDEV;
        is($clone->is_volatile,1);
        test_config($clone);
        sleep 3;
        $clone->shutdown_now(user_admin);

        $n_device = $host_device->list_available_devices();
        is($n_device,++$exp_avail) or exit;

        my $clone_gone = rvd_back->search_domain($clone_data->{name});
        ok(!$clone_gone,"Expecting $clone_data->{name} removed on shutdown");

        my $clone_gone2 = $vm->search_domain($clone_data->{name});
        ok(!$clone_gone2,"Expecting $clone_data->{name} removed on shutdown");

        my $clone_gone3;
        eval { $clone_gone3 = $vm->import_domain($clone_data->{name},user_admin,0) };
        ok(!$clone_gone3,"Expecting $clone_data->{name} removed on shutdown") or exit;
    }
    $domain->_data('volatile_clones' => 0);
    is($host_device->list_available_devices(), $max_n_device) or exit;
}

####################################################################

clean();

for my $vm_name ('KVM', 'Void' ) {
    my $vm;
    eval {
        $vm = rvd_back->search_vm($vm_name)
        unless $vm_name eq 'KVM' && $<;
    };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        if ($vm_name eq 'Void') {
            $BASE = create_domain($vm);
        } else {
            $BASE = import_domain($vm);
        }
        test_mdev_kvm_state($vm);
        my ($domain, $host_device) = test_mdev($vm);
        test_volatile_clones($vm, $domain, $host_device);
        test_base($domain);

    }
}

end();
done_testing();

