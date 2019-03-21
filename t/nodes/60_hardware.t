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

sub test_change_hardware($vm, $node) {
    my $domain = create_domain($vm);
    my $clone = $domain->clone(name => new_domain_name, user => user_admin);

    $domain->set_base_vm( vm => $node, user => user_admin);
    my $clone2 = $node->search_domain($clone->name);
    ok(!$clone2);
    $clone->migrate($node);

    $clone2 = $node->search_domain($clone->name);
    ok($clone2);

    my $info = $domain->info(user_admin);
    my ($hardware) = keys %{$info->{hardware}};
    $clone->remove_controller($hardware,0);

    $clone2 = $node->search_domain($clone->name);
    ok(!$clone2,"Expecting no clone ".$clone->name." in remote node ".$node->name) or exit;

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
        my $node = remote_node($vm_name)  or next;

        push @nodes,($node) if !grep { $_->name eq $node->name } @nodes;

        clean_remote_node($node);

        test_change_hardware($vm, $node);

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    clean();
    for my $node (@nodes) {
        shutdown_node($node);
    }
    done_testing();
}

