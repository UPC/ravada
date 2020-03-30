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


use_ok('Ravada');
init();

##################################################################################

sub test_disable_node($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);

    my $clone = $base->clone(user => user_admin, name => new_domain_name);
    $clone->migrate($node);
    $clone->start(user_admin);
    sleep 2;
    for (1 .. 10 ) {
        last if$clone->is_active;
        sleep 1;
    }
    is($clone->is_active,1,"Expecting clone active") or return;

    $node->enabled(0);

    is($clone->_vm->name, $node->name);

    my $timeout = 4;
    my $req = Ravada::Request->shutdown_domain(
                uid => user_admin->id
           ,timeout => $timeout
        , id_domain => $clone->id
    );
    rvd_back->_process_requests_dont_fork();
    is($req->status,'done');
    is($req->error,'');

    for ( 0 .. $timeout * 2 ) {
        last if !$clone->is_active;
        sleep 1;
        rvd_back->_process_requests_dont_fork();
    }
    is($clone->is_active, 0,$clone->type." ".$clone->name ) or exit;
    if ( $vm->type eq 'KVM' ) {
        is($clone->domain->is_active, 0);
    } else {
        diag("TODO check internal is active ".$vm->type);
    }
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

##################################################################################
clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name ( 'KVM', 'Void') {
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

        diag("Testing remote node in $vm_name");
        my $node = remote_node($vm_name)  or next;
        clean_remote_node($node);

        ok($node->vm,"[$vm_name] expecting a VM inside the node") or do {
            remove_node($node);
            next;
        };
        is($node->is_local,0,"Expecting ".$node->name." ".$node->ip." is remote" ) or BAIL_OUT();
        test_disable_node($vm,$node);

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    end();
    done_testing();
}
