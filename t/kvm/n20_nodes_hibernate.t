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

#######################################################################
sub test_node_down($node, $action) {
    diag("Starting domain in remote node ".$node->type
        ." then hibernate domain, down remote node and"
        ." check if domain starts in local node."
        );

    start_node($node);

    my $domain = create_domain($node->type);
    $domain->prepare_base(user_admin);
    $domain->migrate_base(user => user_admin, node => $node);

    my $clone = $domain->clone(
         user => user_admin
        ,name => new_domain_name
    );
    $clone->migrate($node);

    $clone->start(user_admin);
    is($clone->is_local,0 );

    $action->($clone);

    shutdown_node($node);

    eval { $clone->start(user_admin) };
    is($@,'');
    is($clone->is_active, 1);
    is($clone->is_local, 1);

    start_node($node);

    $clone->shutdown_now(user_admin);
    $clone->migrate($node);

    is($clone->is_local, 0);
    is($clone->_vm->id, $node->id);

    $clone->remove(user_admin);
    $domain->remove(user_admin);
}

sub _shutdown_domain($domain) {
    $domain->shutdown_now(user_admin);
}

sub _hibernate_domain($domain) {
    $domain->hibernate(user_admin);
}
#######################################################################

clean();
clean_remote();

for my $vm_name ('Void' , 'KVM' ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        my $node = remote_node($vm_name)  or next;

        test_node_down($node, \&_shutdown_domain);
        test_node_down($node, \&_hibernate_domain);

        start_node($node);
        clean_remote_node($node);
        clean_remote_node($vm);
        remove_node($node);
    }
}

clean();
clean_remote();
done_testing();
