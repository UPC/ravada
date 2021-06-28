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
clean();

##################################################################################

sub test_fail_different_storage_pools($node) {

    my $sp_name = create_storage_pool($node->type);

    my $base = create_domain($node->type);
    my $vm = $base->_vm;

    eval {
        $base->migrate($node);
    };
    is(''.$@, '',"migrating to ".$node->name) or BAIL_OUT();

    eval {
        $base->migrate($vm);
    };
    is(''.$@, '',"migrating to ".$vm->name);
    my $sp_default = $vm->default_storage_pool_name();
    $vm->default_storage_pool_name($sp_name);

    eval {
        $base->migrate($node);
        $base->migrate($vm);
    };
    like($@, qr'.');

    $vm->default_storage_pool_name($sp_default);
    $vm->base_storage_pool($sp_name);

    eval {
        $base->migrate($node);
        $base->migrate($vm);
    };
    like($@, qr'.');


    $vm->base_storage_pool('');
    $vm->clone_storage_pool($sp_name);

    eval {
        $base->migrate($node);
        $base->migrate($vm);
    };
    like($@, qr'.');

    $base->remove(user_admin);
    $vm->clone_storage_pool('');
}

sub test_fail_storage_pools_different_path($vm,$node2) {

    my $sp_name = create_storage_pool($vm);
    my $dir2="/var/tmp/".new_pool_name();
    my $sp2 = create_storage_pool($node2,$dir2, $sp_name);

    my $sp_default = $vm->default_storage_pool_name();
    $vm->default_storage_pool_name($sp_name);
    my $base = create_domain($vm->type);
    $base->remove_controller('disk',1);

    eval {
        $base->migrate($node2);
    };
    like(''.$@, qr/Error: Storage pool.*different/,"migrating to ".$node2->name) or BAIL_OUT();
    diag($@);

    $vm->default_storage_pool_name($sp_default);

    $base->remove(user_admin);
}

sub test_shared_conflict($vm, $node) {
    $vm->_shared_storage_cache($node,"/var/tmp/",1);
    is($vm->_shared_storage_cache($node,"/var/tmp/"),1);
    is($node->_shared_storage_cache($vm,"/var/tmp/"),1);
    is($vm->shared_storage($node,"/var/tmp"),1);
    is($node->shared_storage($vm,"/var/tmp"),1);

    eval { $vm->_shared_storage_cache($node,"/var/tmp/",0) };
    like($@,qr"conflict");

    is($vm->_shared_storage_cache($node,"/var/tmp/"),1);
    is($node->_shared_storage_cache($vm,"/var/tmp/"),1);

    is($vm->shared_storage($node,"/var/tmp"),1);
    is($node->shared_storage($vm,"/var/tmp"),1);
}

##################################################################################
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP: {
        skip($msg,10);
    }

    done_testing();
    exit;
}

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name ( 'KVM' ) {
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

        test_fail_storage_pools_different_path($vm, $node);
        test_fail_different_storage_pools($node);

        test_shared_conflict($vm, $node);

        clean_remote_node($node);
        remove_node($node);
    }

}

end();
done_testing();
