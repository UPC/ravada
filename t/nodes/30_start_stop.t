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

##################################################################

for my $vm_name ( 'KVM') {
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

        diag("Testing WOL node in $vm_name");
        my $node = remote_node($vm_name)  or next;
        for ( 1 .. 60 ) {
            diag("[$_] Waiting for ".$node->name." to answer ping") if $ENV{TERM};
            last if $node->ping;
            sleep 1;
        }
        like($node->_data('mac'),qr([\da-f][\da-f]:[\da-f][\da-f]:[\da-f][\da-f]:[\da-f][\da-f]:[\da-f][\da-f]:)) or next;

        is( $node->is_active, 1 );
        $node->shutdown();
        for ( 1 .. 60 ) {
            last if !$node->ping;
            sleep 1;
        }
        is( $node->ping, 0 );
        is( $node->is_active, 0 );

        # it actually dows nothing on virtual machines, just check it won't fail
        eval { $node->_wake_on_lan() };
        is($@,'');
#        KVM testing machines can't Wake On LAN
#        sleep 1;
#        $node->start();
#        for ( 1 .. 60 ) {
#            last if $node->is_active;
#            sleep 1;
#        }
#        is( $node->is_active, 1 );

    }
}
done_testing();
