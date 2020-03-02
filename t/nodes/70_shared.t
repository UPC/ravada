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

my $SHARED_SP = "pool_tst";

init();

#################################################################################

sub test_shared($vm, $node) {
    $vm->default_storage_pool_name($SHARED_SP);

    my $domain = create_domain($vm);

    my $storage_path = $vm->_storage_path($SHARED_SP);

    is($vm->shared_storage($node, $storage_path),1,"Expecting $SHARED_SP shared") or exit;
    for my $vol ($domain->list_disks) {
        like($vol,qr(^$storage_path), $vol);
    }

    my $req = Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node->id
    );
    rvd_back->_process_requests_dont_fork(1);

    ok($req->status, 'done');
    is($req->error, '') or exit;
    is($domain->base_in_vm($node->id),1);
    is($domain->base_in_vm($vm->id),1);

    my @files_base = $domain->list_files_base();

    $req = Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node->id
        ,value => 0
    );
    rvd_back->_process_requests_dont_fork(1);

    ok($req->status, 'done');
    is($req->error, '') or exit;

    is($domain->base_in_vm($node->id),0);
    is($domain->base_in_vm($vm->id),1);

    for my $vol (@files_base) {
        my $ok;
        for ( 1 .. 5 ) {
            $ok = -e $vol;
            last if $ok;
            sleep 1;
        }
        ok($ok,"Volume $vol should exists");
    }
    $domain->remove(user_admin);

}

#################################################################################

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name ( 'Void', 'KVM') {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        my $REMOTE_CONFIG = remote_config($vm_name);
        if (!keys %$REMOTE_CONFIG) {
            my $msg = "skipped, missing the remote configuration for $vm_name in 
the file "
                .$Test::Ravada::FILE_CONFIG_REMOTE;
            diag($msg);
            skip($msg,10);
        }

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        if ($vm && !grep /^$SHARED_SP$/,$vm->list_storage_pools) {
            $msg = "SKIPPED: Missing storage pool '$SHARED_SP' in node ".$vm->name;
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        my $node = remote_node($vm_name)  or next;
        clean_remote_node($node);

        ok($node->vm,"[$vm_name] expecting a VM inside the node") or do {
            remove_node($node);
            next;
        };
        is($node->is_local,0,"Expecting ".$node->name." ".$node->ip." is remote") or BAIL_OUT();

        if (!grep /^$SHARED_SP$/,$node->list_storage_pools) {
            $msg = "SKIPPED: Missing storage pool '$SHARED_SP' in node ".$node->name;
            diag($msg);
            skip($msg,10);
        }

        test_shared($vm, $node);
        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    end();
    done_testing();
}

