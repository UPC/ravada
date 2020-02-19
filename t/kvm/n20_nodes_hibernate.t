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

#######################################################################
sub test_node_down($node, $action, $action_name) {
    diag("Starting domain in remote node ".$node->type."."
        ." Then $action_name domain, down remote node and"
        ." check if domain starts in local node."
        );

    start_node($node);
    is($node->is_active,1) or exit;
    is($node->is_enabled,1) or exit;

    my $domain = create_domain($node->type);
    $domain->prepare_base(user_admin);
    $domain->migrate_base(user => user_admin, node => $node);

    my $clone = $domain->clone(
         user => user_admin
        ,name => new_domain_name
    );
    $clone->migrate($node);
    is($clone->is_local,0 );

    $clone->start(user => user_admin, id_vm => $node->id);
    is($clone->is_local,0 );

    $action->($clone);

    shutdown_node($node);

    eval { $clone->start(user_admin) };
    is($@,'');
    is($clone->is_active, 1, "Expecting clone ".$clone->name." active");
    is($clone->is_local, 1,"Expecting clone ".$clone->name." local");

    start_node($node);

    is($domain->_vm->is_active, 1);

    eval { $clone->shutdown_now(user_admin) };
    is($@,'');
    eval { $clone->migrate($node) };
    is($@,'');

    is($clone->is_local, 0);
    is($clone->_vm->id, $node->id);

    $clone->remove(user_admin);

    $domain = Ravada::Domain->open($domain->id);
    eval { $domain->remove(user_admin) };
    is(''.$@,'');
}

sub _shutdown_domain($domain) {
    $domain->shutdown_now(user_admin);
}

sub _hibernate_domain($domain) {
    $domain->hibernate(user_admin);
}
#######################################################################

clean();
clean_remote() if !$>;

for my $vm_name ('Void' , 'KVM' ) {
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

        test_node_down($node, \&_shutdown_domain, 'shutdown');
        test_node_down($node, \&_hibernate_domain, 'hibernate');

        start_node($node);
        clean_remote_node($node);
        clean_remote_node($vm);
        remove_node($node);
    }
}

clean();
done_testing();
