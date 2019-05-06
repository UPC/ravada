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

##################################################################################

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

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        my ($node1,$node2) = remote_node_2($vm_name);

        ok($node2,"Expecting at least 2 nodes configured to test") or next;

        clean_remote_node($node1);
        clean_remote_node($node2)   if $node2;

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

