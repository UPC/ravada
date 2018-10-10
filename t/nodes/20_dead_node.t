use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
init($test->connector);

##################################################################################

sub test_down_node($vm, $node) {
    my $domain = create_domain($vm);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(node => $node, user => user_admin);

    my $clone = $domain->clone(user => user_admin, name => new_domain_name() );
    $clone->migrate($node);
    $clone->start(user_admin);
    is($clone->_vm->id, $node->id );

    shutdown_node($node);
    my $req = Ravada::Request->refresh_vms();
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    is($req->error, '',"Expecting no error after refresh vms");

    is($clone->is_active, 0, "Expecting clone not active after node shutdown");

    $clone->remove(user_admin);
    $domain->remove(user_admin);
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

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    clean();
    done_testing();
}
