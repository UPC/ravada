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

sub test_down_node($vm, $node) {
    start_node($node);

    my $domain = create_domain($vm);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(node => $node, user => user_admin);

    my @clone;
    for ( 1 .. 3 ) {
        my $clone = $domain->clone(user => user_admin, name => new_domain_name() );
        $clone->migrate($node);
        $clone->start(user_admin);
        is($clone->_vm->id, $node->id );

        push @clone,($clone);
    }

    shutdown_node($node);
    my $req = Ravada::Request->refresh_vms();
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    is($req->error, '',"Expecting no error after refresh vms");

    is($clone[0]->is_active, 0, "Expecting clone not active after node shutdown");

    my@req;
    for (@clone) {
        push @req,(Ravada::Request->remove_domain(uid => user_admin->id
                    , name=> $_->name
        ));
    }
    for my $req (@req) {
        rvd_back->_process_requests_dont_fork();
        next if $req->status ne 'done';
        is($req->error ,'');
    }
    $domain->remove(user_admin);
}

sub test_disabled_node($vm, $node) {
    diag("[".$vm->type."] Test clones should shutdown on disabled nodes");
    start_node($node);

    my $domain = create_domain($vm);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(node => $node, user => user_admin);

    my $clone = $domain->clone(user => user_admin, name => new_domain_name() );
    $clone->migrate($node);
    $clone->start(user_admin);
    is($clone->_vm->id, $node->id );
    is($clone->is_active, 1);
    is($clone->_data('id_vm'), $node->id) or exit;

    $node->enabled(0);
    is($node->enabled, 0);

    my $timeout = 3;
    my $req = Ravada::Request->refresh_vms( timeout_shutdown => $timeout );
    rvd_back->_process_requests_dont_fork();

    my @reqs = $clone->list_requests();
    if (!@reqs) {
        rvd_back->_process_requests_dont_fork();
        @reqs = $clone->list_requests();
    }
    ok(@reqs,"Expecting requests for clone to shutdown") or exit;
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    is($req->error, '',"Expecting no error after refresh vms");

    for ( 1 .. $timeout * 2 ) {
        delete $clone->{_data};
        rvd_back->_process_requests_dont_fork();
        is($clone->_vm->id, $node->id ) or exit;
        last if !$clone->is_active;
        sleep 1;
    }
    is($clone->is_active, 0, "Expecting clone ".$clone->name." not active in ".$clone->_vm->name
        ." after node disabled") or exit;

    my $clone_f = Ravada::Front::Domain->open($clone->id);
    is($clone_f->is_active, 0, "Expecting clone in frontend not active after node disabled");

    $clone->remove(user_admin);
    $domain->remove(user_admin);

    $node->enabled(1);
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

        if ($vm && $vm_name =~ /kvm/i && $>) {
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
        test_down_node($vm, $node);
        test_disabled_node($vm, $node);

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    clean();
    done_testing();
}
