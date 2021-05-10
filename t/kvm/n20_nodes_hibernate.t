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

init();

#######################################################################
sub test_node_down($node, $action, $action_name) {
    diag("Starting domain in remote node ".$node->type."."
        ." Then $action_name domain, down remote node and"
        ." check if domain starts in local node."
        );

    start_node($node);
    is($node->is_active,1) or exit;
    is($node->enabled,1) or exit;

    my $domain = create_domain($node->type);
    $domain->prepare_base(user_admin);
    $domain->migrate_base(user => user_admin, node => $node);
    is($domain->base_in_vm($node->id),1);

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
    $node->_clean_cache();

    $clone = Ravada::Domain->open($clone->id);

    eval { $clone->start(user_admin) };
    is(''.$@,'');
    is($clone->is_active, 1, "Expecting clone ".$clone->name." active");
    is($clone->is_local, 1,"Expecting clone ".$clone->name." local");
    is($domain->base_in_vm($node->id),1);

    delete_request('set_base_vm');
    wait_request(debug => 0);
    $node->_clean_cache();
    start_node($node);
    is($node->is_active,1);
    wait_request(debug => 0);

    is($domain->_vm->is_active, 1);

    eval { $clone->shutdown_now(user_admin) };
    is($@,'');
    my $req = Ravada::Request->migrate(id_domain => $clone->id
        ,uid => user_admin->id
        ,id_node =>$node->id
    );
    wait_request($req);
    is($req->error,'') or exit;

    my $clone2 = Ravada::Domain->open($clone->id);
    is($clone2->is_local, 0);
    is($clone2->_vm->id, $node->id);

    $clone2->remove(user_admin);

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

for my $vm_name ( vm_names() ) {
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

end();
done_testing();
