use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Storable qw(dclone);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my %HAS_NOT_VALUE = map { $_ => 1 } qw(image jpeg zlib playback streaming);

##################################################################################
#

sub test_graphics($vm, $node) {
    my $domain = create_domain($vm->type);
    for my $driver_name ( qw( image jpeg zlib playback streaming )) {
        my $driver = $domain->drivers($driver_name) or do {
            diag("No driver for $driver_name in ".$domain->type);
            next;
        };
        test_driver_migrate($vm, $node, $domain, $driver_name);
        for my $option ($driver->get_options) {
            next if $domain->get_driver($driver_name)
                && $domain->get_driver($driver_name) eq $option->{value};

                #diag("Testing $driver_name $option->{value} in ".$vm->type);

            test_driver_clone($vm, $node, $domain, $driver_name, $option);

            last unless $ENV{TEST_LONG};
        }
    }
    $domain->remove(user_admin);
}

sub test_driver_clone($vm, $node, $domain, $driver_name, $option) {
    if ( $domain->is_base ) {
        Ravada::Request->remove_clones(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        Ravada::Request->remove_base(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request();
    }
    my $req = Ravada::Request->set_driver(uid => user_admin->id
        , id_domain => $domain->id
        , id_option => $option->{id}
    );
    wait_request();
    is($req->status,'done');
    is($req->error,'');
    is($domain->get_driver($driver_name), $option->{value}
        , $driver_name);
    Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node->id
    );

    my $name = new_domain_name();
    Ravada::Request->clone(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $name
    );
    wait_request();
    my $clone = rvd_back->search_domain($name);
    Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $clone->id
        ,id_node => $node->id
    );
    wait_request();
    my $clone2 = Ravada::Domain->open($clone->id);
    is($clone2->_vm->id,$node->id);
    is($clone2->get_driver($driver_name), $option->{value}
        , $driver_name);

    Ravada::Request->remove_clones(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();
    Ravada::Request->remove_base(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();
}

sub test_driver_migrate($vm, $node, $domain, $driver_name) {
    my $option;
    my $driver = $domain->drivers($driver_name) or do {
            diag("No driver for $driver_name in ".$domain->type);
            next;
    };

    # make sure prepare_base and the set_base_vm are chained
    Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $domain->id
    ) if !$domain->is_base();
    Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node->id
    );

    wait_request(debug => 0);
    for my $option ($driver->get_options) {
        next if defined $domain->get_driver($driver_name)
        && $domain->get_driver($driver_name) eq $option->{value};

        # diag("Testing $driver_name $option->{value} then migrate");
        my $name = new_domain_name();
        my $req_clone = Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,name => $name
        );
        wait_request();
        my $clone;
        for ( 1 .. 3 ) {
            $clone = rvd_back->search_domain($name);
            last if $clone;
            sleep 1;
        }
        my $req = Ravada::Request->set_driver(uid => user_admin->id
            , id_domain => $clone->id
            , id_option => $option->{id}
        );
        wait_request();
        is($req->status,'done');
        is($req->error,'');

        Ravada::Request->migrate(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,id_node => $node->id
        );
        wait_request();
        my $clone2 = Ravada::Domain->open($clone->id);
        is($clone2->_vm->id,$node->id);
        is($clone2->get_driver($driver_name), $option->{value}
            , $driver_name) or exit;

        Ravada::Request->remove(
            uid => user_admin->id
            ,name => $clone->name
        );
        last unless $ENV{TEST_LONG};
    }
}

sub test_drivers_type($type, $vm, $node) {

    my $domain = create_domain($vm);

    my $req = Ravada::Request->add_hardware(uid => user_admin->id
                , id_domain => $domain->id
                , name => 'usb'
                , number => 3
    );
    wait_request(debug => 0);
    my $driver_type = $domain->drivers($type);

    if (!$HAS_NOT_VALUE{$type}) {
        my $value = $driver_type->get_value();
        ok($value,"Expecting value for driver type: $type ".ref($driver_type)."->get_value")
            or exit;
    }

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    for my $option (@options) {
        die "No value for driver ".Dumper($option)  if !$option->{value};

        # diag("Testing $type $option->{value}");

        eval { $domain->set_driver($type => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));

        is($domain->get_driver($type), $option->{value}, $type);
        my $req_prepare = Ravada::Request->prepare_base(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request();
        is($req_prepare->status(),'done');
        is($req_prepare->error(),'');

        my $req = Ravada::Request->set_base_vm(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,id_vm => $node->id
        );
        wait_request();
        is($req->status(),'done');
        is($req->error(),'');

        my $clone = $domain->clone(name => new_domain_name, user => user_admin);
        is($clone->get_driver($type), $option->{value}, $type);
        $clone->migrate($node);
        my $clone2 = Ravada::Domain->open($clone->id);
        is($clone2->_vm->id,$node->id);
        is($clone2->get_driver($type), $option->{value}, $type);

        $clone->remove(user_admin);
        my @vols = $domain->list_files_base();
        Ravada::Request->remove_base(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(debug => 0);
        my $domainb = Ravada::Domain->open($domain->id);
        is($domainb->is_base,0);

        for my $vol (@vols) {
            ok (! -e $vol ) or die "$vol";
        }
        $domain = Ravada::Domain->open($domain->id);

    }
    $domain->remove(user_admin);
}

sub test_drivers($vm, $node) {
    my @drivers = $vm->list_drivers();
     for my $driver ( @drivers ) {
         next if $driver->name =~ /display|features|usb controller/;
         test_drivers_type($driver->name, $vm, $node);
     }

}

sub _add_hardware($domain) {
    return unless $domain->type eq 'KVM';

    my $dir = "/var/tmp/".new_domain_name();
    mkdir $dir or die $! unless -e $dir;

    my $req = Ravada::Request->add_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => {
            source => { dir => $dir }
        }
    );
    Ravada::Request->add_hardware(
        name => 'usb controller'
        ,uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request(debug => 0);
}

sub _change_disk_size($domain) {
    $domain->shutdown_now(user_admin) if $domain->is_active;

    my $info = $domain->info(user_admin);
    my $disk = $info->{hardware}->{disk};
    confess Dumper([$domain->_vm->name." ".$domain->name, $disk]) if !defined $disk->[0];

    my $data = dclone($disk->[0]);
    my $new_capacity = int($data->{capacity}*3.5);
    $data->{capacity}=$new_capacity;

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,index => 0
        ,data => $data
        ,hardware => 'disk'
    );
    wait_request();

    my $data2;
    for ( 1 .. 3 ) {
        my $domain2 = Ravada::Domain->open($domain->id);
        my $disk2 = $domain2->info(user_admin)->{hardware}->{disk};
        $data2 = dclone($disk2->[0]);
        last if int($data2->{capacity}*0.9) == int($new_capacity*0.9);

        Ravada::Request->refresh_machine(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,_force => 1
        );
        wait_request();
    }

    is(int($data2->{capacity}*0.9), int($new_capacity*0.9)) or die $domain->name;


}

sub _do_test_change_hardware($domain, $hardware) {

    $domain = Ravada::Domain->open($domain->id);
    my %sub = (
        'disk' => \&_change_disk_size
    );
    my $sub = $sub{$hardware};
    if (!$sub) {
        return;
    }
    $sub->($domain);
}

sub _clone_and_add_volume($domain) {
    my $name = new_domain_name();
    Ravada::Request->clone(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $name
    );
    my $clone;
    for ( 1 .. 3 ) {
        $clone = rvd_back->search_domain($name);
        wait_request();
    }
    my $data = {
        'file' => '',
        'driver' => {
            'cache' => 'writeback',
        },
        'device' => 'disk',
        'allocation' => '200M',
        'bus' => 'virtio',
        'capacity' => '1G',
        'type' => 'data'
    };
    delete $data->{driver} if $domain->type eq 'Void';

    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $clone->id
        ,name => 'disk'
        ,'data' => $data
    );
    wait_request();
    return $clone;
}

sub _migrate_clone($clone, @nodes) {

    for my $node (@nodes) {
        for ( 1 .. 10 ) {
            last if $node->ping(undef,0);
            diag("Waiting for ".$node->name." ping $_");
            sleep 1;
        }
        is($node->ping(),1) or die "Error: I can't ping ".$node->ip;

        my $req_set_base = Ravada::Request->set_base_vm(
            uid => user_admin->id
            ,id_domain => $clone->id_base()
            ,id_vm => $node->id
        );
        wait_request($req_set_base);

        my $clone2 = $node->search_domain($clone->name);
        ok(!$clone2);

        my $req_migrate = Ravada::Request->migrate(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,id_node => $node->id
        );
        wait_request($req_migrate);
        $clone2 = $node->search_domain($clone->name);
        ok($clone2);
    }

}

sub test_change_hardware($vm, @nodes) {
    diag("Change hardware nodes=".scalar(@nodes));
    my $domain = create_domain($vm);

    _add_hardware($domain);

    my $clone = _clone_and_add_volume($domain);
    my @volumes = $clone->list_volumes();

    _migrate_clone($clone,@nodes);
    $clone = Ravada::Domain->open($clone->id);

    my $n_instances = $domain->list_instances();
    my $info = $clone->info(user_admin);
    my %devices;
    for my $hardware ( sort keys %{$info->{hardware}} ) {
        $devices{$hardware} = scalar(@{$info->{hardware}->{$hardware}});
    }
    my @hardware = grep (!/^(disk|display|usb)$/, sort keys %{$info->{hardware}});
    push @hardware,("display");
    push @hardware,("usb") if $vm->type ne 'Void';
    push @hardware,("disk");
    for my $hardware (reverse @hardware) {
        next if $hardware =~ /cpu|features|memory/;
        my $tls = 0;
        $tls = grep {$_->{driver} =~ /-tls/} @{$info->{hardware}->{$hardware}}
        if $hardware eq 'display';

        _do_test_change_hardware($clone, $hardware);

        #TODO disk volumes in Void
        #next if $vm->type eq 'Void' && $hardware =~ /disk|volume/;

        diag("Testing remove $hardware");

        my $current_vm = $clone->_vm;
        my $n = 0;
        $n = scalar(@{$info->{hardware}->{$hardware}})-1
        if $hardware eq 'usb controller';

        Ravada::Request->remove_hardware(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,name => $hardware
            ,index => $n
        );
        wait_request(debug => 0);
        is (scalar($clone->list_instances()), $n_instances);

        my $n_expected = scalar(@{$info->{hardware}->{$hardware}})-1;
        die "Warning: no $hardware devices in ".$clone->name if $n_expected<0;
        $n_expected-- if $hardware eq 'display' && $tls;

        $n_expected = 0 if $n_expected<0;

        my $count_instances = $domain->list_instances();
        is($count_instances,1+scalar(@nodes),"Expecting other instances not removed when hardware $hardware removed");

        for my $node ($vm, @nodes) {
            my $clone2 = $node->search_domain($clone->name);
            ok($clone2,"Expecting clone ".$clone->name." in remote node ".$node->name
                ." when removing $hardware") or next;

            my $devices2;
            if ($hardware eq 'disk') {
                $devices2 = [ $clone2->list_volumes ];
            } else {
                my $info2 = $clone2->info(user_admin);
                $devices2 = $info2->{hardware}->{$hardware};
            }

            if ($hardware eq 'video' && $vm->type eq 'KVM') {
                is( scalar(@$devices2),1);
                is($devices2->[0]->{type},'none');
            } else {
                is( scalar(@$devices2),$n_expected
                , $clone2->name.": Expecting 1 $hardware device less in instance in node ".$node->name)
                or die Dumper($devices2);
            }
        }

        my $clone_fresh = Ravada::Domain->open($clone->id);
        shift @volumes if $hardware eq 'disk';
        for (@volumes) {
            ok(-e $_,$_) or exit;
        }

    }
    for my $name ( $clone->name, $domain->name ) {
        Ravada::Request->remove_domain(
            uid => user_admin->id
            ,name => $name
        );
        wait_request();
    }
}

##################################################################################
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP:{
        skip($msg,10);
    }
    done_testing();
    exit;
}

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

my @nodes;

for my $vm_name (reverse vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        my ($node1,$node2);
        if ($vm) {
            ($node1,$node2) = remote_node_2($vm_name);
            if (!$node2) {
                $vm = undef;
                $msg = "Expecting at least 2 nodes configured to test";
            }
        }
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");

        clean_remote_node($node1);
        clean_remote_node($node2)   if $node2;

        test_change_hardware($vm);

        test_drivers($vm, $node1);
        test_graphics($vm, $node1);

        test_change_hardware($vm);
        test_change_hardware($vm, $node1);
        test_change_hardware($vm, $node2);
        test_change_hardware($vm, $node1, $node2);

        NEXT:
        clean_remote_node($node1);
        remove_node($node1);
        clean_remote_node($node2);
        remove_node($node2);
    }

}

END: {
    end();
    done_testing();
}

