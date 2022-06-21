use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE_NAME = "zz-test-base-alpine";
my $BASE;

##########################################################################

sub _base($vm) {
    if ($vm->type eq 'KVM') {
        my $base0 = import_domain('KVM', $BASE_NAME, 1);
        $BASE = $base0->clone(
            name => new_domain_name()
            ,user => user_admin
        );
        my $t0 = time;
        $BASE->spinoff();
        warn time-$t0;
    } else {
        $BASE = create_domain($vm);
    }
    $BASE->prepare_base(user_admin);
}

sub test_same_node($vm, $node1, $node2) {
    my $user = create_user();
    user_admin->grant($user, 'start_limit', 10);
    for my $node ( $node1, $node2 ) {
        $BASE->set_base_vm(
            id_vm => $node->id
            ,user => user_admin
        );
    }
    my $domain = $BASE->clone(
        name => new_domain_name()
        ,user => user_admin
    );
    $domain->prepare_base(user_admin);
    $domain->_data('balance_policy'=>1);
    for my $node ( $node1, $node2 ) {
        $domain->set_base_vm(
            id_vm => $node->id
            ,user => user_admin
        );
    }

    my $clone1 = $domain->clone(
        name => new_domain_name()
        ,user => $user
        ,memory => 128*1024
    );

    my @clone = _create_clones($domain, $user, 3);
    for my $node0 ( $vm, $node1, $node2 ) {
        _migrate($node0, $clone1);
        for my $clone ( @clone ) {
            diag("going to strt ".$clone->name);
            my $req_s = Ravada::Request->start_domain(
                id_domain => $clone->id
                ,uid => $user->id
            );
            wait_request(debug => 1);

            my $clone_f = Ravada::Front::Domain->open($clone->id);
            is($clone_f->_data('id_vm'), $node0->id
                ,"Expecting ".$clone->name." same node in ".$vm->type)
            or exit;
        }
        for my $clone ( @clone ) {
            $clone->shutdown_now(user_admin);
        }

    }

    remove_domain($domain);
}

sub _create_clones($base, $user, $n) {
    my @clone;
    for (1 .. $n ) {
        my $clone = $base->clone(
               name => new_domain_name()
              ,user => $user
            ,memory => 128*1024
        );
        push @clone,($clone);
    }
    return @clone;
}

sub _migrate($node, $clone) {
    return if $clone->_data('id_vm') == $node->id;
    my $req = Ravada::Request->migrate(
        id_node => $node->id
        ,id_domain => $clone->id
        ,uid => user_admin->id
        ,start => 1
    );
    wait_request(debug => 1);
}
##########################################################################

if ($>)  {
    diag("SKIPPED: Test must run as root");
    done_testing();
    exit;
}

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name (reverse vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        my $REMOTE_CONFIG = remote_config($vm_name);
        if (!keys %$REMOTE_CONFIG) {
            my $msg = "skipped, missing the remote configuration for $vm_name in the file "
                .$Test::Ravada::FILE_CONFIG_REMOTE;
            diag($msg);
            skip($msg,10);
        }

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        my ($node1, $node2) = remote_node_2($vm_name)  or next;
        clean_remote_node($node1);
        start_node($node1);
        clean_remote_node($node2);
        start_node($node2);

        _base($vm);
        test_same_node($vm, $node1, $node2);
        $node1->remove();
        $node2->remove();
    }
}

clean();
done_testing();
