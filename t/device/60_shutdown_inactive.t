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

my $VGPU_ID = 3251658935;
####################################################################

sub _vgpu_id() {
    return $VGPU_ID++;
}

sub test_shutdown_inactive($vm, $connected=0) {
    my $name = new_domain_name();
    my $clone = $BASE->clone( name => $name, user => user_admin);

    my $hd = create_host_devices($vm,3,"GPU Mediated");
    die "I can't find mock GPU Mediated" if !$hd && $vm->type eq 'Void';

    return if !$hd;
    $clone->add_host_device($hd);

    $clone->_data('shutdown_disconnected' => 1);
    $clone->_data('no_shutdown_active_gpu' => 1);
    $clone->_data('shutdown_grace_time' => 2);
    $clone->start(user => user_admin, remote_ip => '1.2.3.4');

    _mock_disconnected($clone);
    _mock_nvidia_load($vm, $clone);

    _wait_shutdown($clone, $connected);

    remove_domain($clone);
}

sub test_no_shutdown_connected($vm) {
    my $name = new_domain_name();
    my $clone = $BASE->clone( name => $name, user => user_admin);

    my $hd = create_host_devices($vm,3,"GPU Mediated");
    die "I can't find mock GPU Mediated" if !$hd && $vm->type eq 'Void';

    return if !$hd;
    $clone->add_host_device($hd);

    $clone->_data('shutdown_disconnected' => 1);
    $clone->_data('no_shutdown_active_gpu' => 0);
    $clone->_data('shutdown_grace_time' => 2);
    $clone->start(user => user_admin, remote_ip => '1.2.3.4');

    my $load = { $clone->name => 3};
    _mock_nvidia_load($vm, $load);

    _wait_shutdown_v2($clone , 0);

    $load->{$clone->name} = 0;
    _mock_nvidia_load($vm, $load);

    _rewind_vgpu_status($vm, 120);

    _mock_nvidia_load($vm, $load);

    delete $clone->{_data};

    is($clone->gpu_active,0);
    like($clone->client_status(),qr/\d+\.\d+\.\d+\.\d+/);
    _wait_shutdown_v2($clone , 0);

    remove_domain($clone);
}
sub test_shutdown_disconnected($vm) {
    my $name = new_domain_name();
    my $clone = $BASE->clone( name => $name, user => user_admin);

    my $hd = create_host_devices($vm,3,"GPU Mediated");
    die "I can't find mock GPU Mediated" if !$hd && $vm->type eq 'Void';

    return if !$hd;
    $clone->add_host_device($hd);

    $clone->_data('shutdown_disconnected' => 1);
    $clone->_data('no_shutdown_active_gpu' => 0);
    $clone->_data('shutdown_grace_time' => 2);
    $clone->start(user => user_admin, remote_ip => '1.2.3.4');

    my $load = { $clone->name => 3};
    _mock_nvidia_load($vm, $load);

    _mock_disconnected($clone);

    _wait_shutdown_v2($clone , 0);

    $load->{$clone->name} = 0;
    _mock_nvidia_load($vm, $load);

    _rewind_vgpu_status($vm, 120);
    _mock_disconnected($clone);

    _mock_nvidia_load($vm, $load);

    delete $clone->{_data};

    is($clone->gpu_active,0);
    is($clone->client_status(),'disconnected');
    _wait_shutdown_v2($clone , 1);

    remove_domain($clone);
}

sub test_shutdown_disconnected_active_gpu($vm) {
    my $name = new_domain_name();
    my $clone = $BASE->clone( name => $name, user => user_admin);

    my $hd = create_host_devices($vm,3,"GPU Mediated");
    die "I can't find mock GPU Mediated" if !$hd && $vm->type eq 'Void';

    return if !$hd;
    $clone->add_host_device($hd);

    $clone->_data('shutdown_disconnected' => 1);
    $clone->_data('no_shutdown_active_gpu' => 1);
    $clone->_data('shutdown_grace_time' => 2);
    $clone->start(user => user_admin, remote_ip => '1.2.3.4');

    _mock_inactive($clone, 1);
    _mock_inactive($clone);
    _mock_disconnected($clone);

    _wait_shutdown($clone);

    remove_domain($clone);
}



sub test_shutdown_inactive_but_connected($vm) {
    test_shutdown_inactive($vm, 1);
}

sub _wait_shutdown($domain, $connected=0) {
    diag("Waiting for shutdown, connected=$connected ".$domain->name);
    my $req_shutdown;
    for my $n (0 .. 5 ) {
        sleep 1 if $n;
        my $req2=Ravada::Request->enforce_limits( _force => 1);

        if ($connected) {
            my $status = 'connected (spice)';
            $domain->_data('client_status', $status);
            $domain->_data('client_status_time_checked', time );
            $domain->log_status($status);
        } else {
            my $status = 'disconnected';
            $domain->_data('client_status', $status);
            $domain->log_status($status);
        }

        wait_request(request => $req2, skip => [],debug => 0);
        is($req2->error,'');
        ($req_shutdown) = grep { $_->command =~ /shutdown/ } $domain->list_requests(1);

        last if (!$domain->is_active || $req_shutdown);

        is($domain->gpu_active,0) or exit;
        my $sth = connector->dbh->prepare(
            "DELETE FROM requests where command='enforce_limits'"
        );
        $sth->execute;
    }
    if ($connected) {
        ok($domain->is_active && !$req_shutdown, "Expecting kept up while connected");
    } else {
        ok(!$domain->is_active || $req_shutdown) or exit;
    }

}

sub _wait_shutdown_v2($domain, $expected_down=1) {
    diag("Waiting for shutdown, expected_down=$expected_down ".$domain->name);
    my $req_shutdown;
    for my $n (0 .. 5 ) {
        sleep 1 if $n;

        if ($expected_down) {
            is($domain->gpu_active,0)
                or confess Dumper([$domain->name, time,$domain->is_active,$domain->_data('log_status')]);
        }

        my $req2=Ravada::Request->enforce_limits( _force => 1);

        wait_request(request => $req2, skip => [],debug => 0);
        is($req2->error,'');
        ($req_shutdown) = grep { $_->command =~ /shutdown/ } $domain->list_requests(1);

        last if (!$domain->is_active || $req_shutdown);

        my $sth = connector->dbh->prepare(
            "DELETE FROM requests where command='enforce_limits'"
        );
        $sth->execute;
    }
    if ($expected_down) {
        ok(!$domain->is_active || $req_shutdown) or confess;
    } else {
        ok($domain->is_active && !$req_shutdown, "Expecting kept up while connected");
    }

}


sub _mock_disconnected($domain, $minutes=2) {

    delete $domain->{_data};
    my $json_status = $domain->_data('log_status');
    my $h_status = {};
    if ($json_status) {
        eval { $h_status = decode_json($json_status) };
        die $json_status."\n".$@ if $@;
        $h_status = {} if $@;
    }
    push @{$h_status->{'disconnected'}},(time()-$minutes*60);

    $domain->_data('log_status', encode_json($h_status));
    $domain->_data('client_status', 'disconnected');
    $domain->_data('client_status_time_checked', time );

}


sub _mock_inactive($domain, $minutes=2) {
    my $json_status = $domain->_data('log_status');
    my $h_status = {};
    if ($json_status) {
        eval { $h_status = decode_json($json_status) };
        $h_status = {} if $@;
    }
    push @{$h_status->{gpu_inactive}} ,( time() - $minutes*60 );

    $domain->_data('log_status', encode_json($h_status));

}

sub _mock_nvidia_load($vm, $value={}) {

    _rewind_vgpu_status($vm);

    my @domains = $vm->list_domains(active => 1);

    if (ref($vm) =~ /Void/) {
        my $dir = Ravada::Front::Domain::Void::_config_dir()."/gpu";
        mkdir $dir or die "$! $dir" if ! -e $dir;
        my $file = "$dir/nvidia_smi.txt";
        open my $out,">",$file or die "$! $file";
        for my $n ( 41 .. 43 ) {
            last if !@domains;
            print $out "GPU 00000000:$n:00.0\n";
            for ( 1 .. 3 ) {
                my $domain = shift @domains;
                my $vm_name = "";
                $vm_name = $domain->name if $domain;
                print $out "    vGPU ID                : "._vgpu_id()."\n";
                print $out "        VM Name            : $vm_name\n";
                print $out "        Utilization\n";
                for my $item (qw(Gpu Memory Encoder Decoder Jpeg)) {
                    my $current = 0;
                    $current=$value->{$vm_name} if exists $value->{$vm_name};
                    print $out "            $item            : $current %\n";
                }
            }
        }
        close $out;
    }

    ok($vm->get_nvidia_smi()) or exit;

    for my $dom (@domains) {
        ok($dom->_data('log_status'),"Expecting log status in ".$dom->name) or exit;
    }
    $vm->get_gpu_nvidia_status();
}

sub _rewind_vgpu_status($vm, $seconds=1) {
    my @domains = $vm->list_domains(active => 1);
    for my $domain (@domains) {
        my $status_json = $domain->_data('log_status');
        next if !$status_json;
        my $status = {};
        eval { $status = decode_json($status_json) };
        die Dumper([$status_json,$@]) if $@;
        next if !$status->{vgpu} || !$status->{vgpu}->{Gpu};
        for my $item (sort keys %{$status->{vgpu}}) {
            my $n_entries = scalar(@{$status->{vgpu}->{$item}})+$seconds;

            for my $entry (@{$status->{vgpu}->{$item}}) {
                $entry->[0] = $entry->[0]-$n_entries--;
            }
        }
        confess Dumper($status) if exists $status->{Gpu};
        $domain->_data('log_status' => encode_json($status));
    }
}

sub _test_gpu_load($vm , $clones, $load) {

    for my $name (@$clones) {
        my $domain = $vm->search_domain($name);
        my $status = $domain->_data('log_status');
        my $data;
        eval {
            $data = decode_json($status);
        };
        my $info = $data->{vgpu}->{Gpu}->[-1];
        my ($time, $value) = @{$info};
        ok($time,"expecting time in info ".Dumper($info)) or next;

        is($value,$load->{$name}) or confess Dumper($data->{vgpu}->{Gpu});

        my $field = 'gpu_inactive';
        if ($value) {
            is_deeply($data->{$field},[],$field) or exit;
        } else {
            is(scalar(@{$data->{$field}}),1);
        }
    }
}

sub _increase_load($clones, $load) {
    my $n = 1;
    for my $name (@$clones) {
        my $current = ($load->{$name} or 0 );
        $load->{$name} = $current + $n++;
    }
}

sub _create_clones($BASE, $n=3) {
    my @clones;
    for ( 1 .. $n ) {
        my $name = new_domain_name();
        push @clones,($name);
        Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $BASE->id
            ,name => $name
            ,start => 1
        );
    }
    wait_request();
    return @clones;
}

sub _clean_mock_status($vm) {

    return if $vm->type ne 'Void';

    my $dir = Ravada::Front::Domain::Void::_config_dir()."/gpu";
    mkdir $dir or die "$! $dir" if ! -e $dir;
    my $file = "$dir/nvidia_smi.txt";
    unlink $file if -e $file;

    my $out = $vm->get_gpu_nvidia_status();

    is($out, undef);
}

sub test_status($vm) {

    return if !defined $vm->get_nvidia_smi();

    _clean_mock_status($vm);

    my $grace_mins = 2;
    my $base = $BASE->clone(name => new_domain_name() , user => user_admin);

    my @clones = _create_clones($base, 3);
    _mock_nvidia_load($vm);

    my %load;
    for my $name ( @clones ) {
        $load{$name} = 0;
    }

    _test_gpu_load($vm , \@clones, \%load);

    _increase_load(\@clones, \%load);
    _mock_nvidia_load($vm, \%load);

    _increase_load(\@clones, \%load);
    _mock_nvidia_load($vm, \%load);
    _test_gpu_load($vm , \@clones, \%load);

    my ($first,$second) = keys %load;
    $load{$second}=0;

    _mock_nvidia_load($vm, \%load);
    _test_gpu_load($vm , \@clones, \%load);

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

        test_shutdown_disconnected($vm);

        test_shutdown_inactive($vm);
        test_shutdown_inactive_but_connected($vm);
        test_status($vm);

    }
}

end();
done_testing();
