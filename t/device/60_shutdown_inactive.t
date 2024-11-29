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

sub test_shutdown_inactive($vm) {
    my $name = new_domain_name();
    my $clone = $BASE->clone( name => $name, user => user_admin);

    my $hd = create_host_devices($vm);
    $clone->add_host_device($hd);

    $clone->_data('shutdown_inactive_gpu' => 2);
    $clone->_data('shutdown_grace_time' => 2);
    $clone->start(user => user_admin, remote_ip => '1.2.3.4');

    my $req_shutdown;
    for my $n (0 .. 5 ) {
        sleep 1 if $n;
        my $req2=Ravada::Request->enforce_limits( _force => 1);
        wait_request(request => $req2, skip => [],debug => 1);
        is($req2->error,'');
        ($req_shutdown) = grep { $_->command =~ /shutdown/ } $clone->list_requests(1);

        last if (!$clone->is_active || $req_shutdown);
        _mock_inactive($clone);
        my $sth = connector->dbh->prepare(
            "DELETE FROM requests where command='enforce_limits'"
        );
        $sth->execute;
    }
    ok(!$clone->is_active || $req_shutdown) or exit;

}

sub _mock_inactive($domain, $minutes=2) {
    my $json_status = $domain->_data('log_status');
    my $h_status = {};
    if ($json_status) {
        eval { $h_status = decode_json($json_status) };
        $h_status = {} if $@;
    }
    push @{$h_status->{'inactive'}},(time()-$minutes*60);

    $domain->_data('log_status', encode_json($h_status));

}

sub _mock_nvidia_load($vm, $value={}) {

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
    } else {
        die "TODO for ".ref($vm);
    }
}

sub test_status($vm) {

    my $dir = Ravada::Front::Domain::Void::_config_dir()."/gpu";
    mkdir $dir or die "$! $dir" if ! -e $dir;
    my $file = "$dir/nvidia_smi.txt";
    unlink $file if -e $file;

    my $out = $vm->get_gpu_nvidia_status();

    is($out, undef);

    my @clones;
    for ( 1 .. 3 ) {
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
    _mock_nvidia_load($vm);

    $vm->get_gpu_nvidia_status();

    my %load;
    my $n = 0;
    for my $name (@clones) {
        my $domain = $vm->search_domain($name);
        my $status = $domain->_data('log_status');
        my $data;
        eval {
            $data = decode_json($status);
        };
        my $info = $data->{vgpu}->{Gpu}->[-1];
        my ($time) = keys %$info;
        $load{$name} = ++$n;
    }

    _mock_nvidia_load($vm, \%load);

    $vm->get_gpu_nvidia_status();
    for my $name (@clones) {
        my $domain = $vm->search_domain($name);
        my $status = $domain->_data('log_status');
        my $data;
        eval {
            $data = decode_json($status);
        };
        my $info = $data->{vgpu}->{Gpu}->[-1];
        my ($time) = keys %$info;
        is($info->{$time},$load{$name});
    }

    exit;
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

        test_status($vm);
        test_shutdown_inactive($vm);
    }
}

end();
done_testing();
