use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
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

            diag("Testing $driver_name $option->{value} in ".$vm->type);

            test_driver_clone($vm, $node, $domain, $driver_name, $option);

            last unless $ENV{TEST_LONG};
        }
    }
    $domain->remove(user_admin);
}

sub test_driver_clone($vm, $node, $domain, $driver_name, $option) {
    $domain->remove_base(user_admin) if $domain->is_base;
    wait_request();
    my $req = Ravada::Request->set_driver(uid => user_admin->id
        , id_domain => $domain->id
        , id_option => $option->{id}
    );
    wait_request();
    is($req->status,'done');
    is($req->error,'');
    is($domain->get_driver($driver_name), $option->{value}
        , $driver_name);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(node => $node, user => user_admin);

    my $clone = $domain->clone(name => new_domain_name, user => user_admin);
    $clone->migrate($node);
    my $clone2 = Ravada::Domain->open($clone->id);
    is($clone2->_vm->id,$node->id);
    is($clone2->get_driver($driver_name), $option->{value}
        , $driver_name);

    $clone->remove(user_admin);

    $domain->remove_base(user_admin);
    wait_request();
}

sub test_driver_migrate($vm, $node, $domain, $driver_name) {
    my $option;
    my $driver = $domain->drivers($driver_name) or do {
            diag("No driver for $driver_name in ".$domain->type);
            next;
    };
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(node => $node, user => user_admin);
    for my $option ($driver->get_options) {
        next if defined $domain->get_driver($driver_name)
        && $domain->get_driver($driver_name) eq $option->{value};

        diag("Testing $driver_name $option->{value} then migrate");
        my $clone = $domain->clone(name => new_domain_name, user => user_admin);
        my $req = Ravada::Request->set_driver(uid => user_admin->id
            , id_domain => $clone->id
            , id_option => $option->{id}
        );
        wait_request();
        is($req->status,'done');
        is($req->error,'');

        $clone->migrate($node);
        my $clone2 = Ravada::Domain->open($clone->id);
        is($clone2->_vm->id,$node->id);
        is($clone2->get_driver($driver_name), $option->{value}
            , $driver_name) or exit;

        $clone->remove(user_admin);
        last unless $ENV{TEST_LONG};
    }
    $domain->remove_base(user_admin);
    wait_request();
}

sub test_drivers_type($type, $vm, $node) {

    my $domain = create_domain($vm->type);
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

        diag("Testing $type $option->{value}");

        eval { $domain->set_driver($type => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));

        is($domain->get_driver($type), $option->{value}, $type);
        $domain->prepare_base(user_admin);
        $domain->set_base_vm(node => $node, user => user_admin);

        my $clone = $domain->clone(name => new_domain_name, user => user_admin);
        is($clone->get_driver($type), $option->{value}, $type);
        $clone->migrate($node);
        my $clone2 = Ravada::Domain->open($clone->id);
        is($clone2->_vm->id,$node->id);
        is($clone2->get_driver($type), $option->{value}, $type);

        $clone->remove(user_admin);
        my @vols = $domain->list_files_base();
        $domain->remove_base(user_admin);
        wait_request(debug => 0);
        for my $vol (@vols) {
            ok (! -e $vol ) or die "$vol";
        }

    }
    $domain->remove(user_admin);
}

sub test_drivers($vm, $node) {
    my @drivers = $vm->list_drivers();
     for my $driver ( @drivers ) {
         test_drivers_type($driver->name, $vm, $node);
     }

}

sub test_change_hardware($vm, @nodes) {
    diag("[".$vm->type."] testing remove with ".scalar(@nodes)." node ".join(",",map { $_->name } @nodes));
    my $domain = create_domain($vm);
    my $clone = $domain->clone(name => new_domain_name, user => user_admin);
    my @volumes = $clone->list_volumes();

    for my $node (@nodes) {
        $domain->set_base_vm( vm => $node, user => user_admin);
        my $clone2 = $node->search_domain($clone->name);
        ok(!$clone2);
        $clone->migrate($node);
        $clone2 = $node->search_domain($clone->name);
        ok($clone2);
    }

    my $info = $domain->info(user_admin);
    my ($hardware) = grep { !/disk|volume/ } keys %{$info->{hardware}};
    $clone->remove_controller($hardware,0);

    for my $node (@nodes) {
        my $clone2 = $node->search_domain($clone->name);
        ok(!$clone2,"Expecting no clone ".$clone->name." in remote node ".$node->name) or exit;
    }

    is($clone->_vm->is_local,1) or exit;
    for (@volumes) {
        ok(-e $_,$_) or exit;
    }
    $clone->remove(user_admin);
    $domain->remove(user_admin);
}

##################################################################################

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

my @nodes;

for my $vm_name ( 'Void', 'KVM') {
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

        test_graphics($vm, $node1);
        test_drivers($vm, $node1);

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
    clean();
    done_testing();
}

