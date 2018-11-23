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
            last if $node->ping;
            diag("Waiting for ".$node->name." to answer ping") if $ENV{TERM} && ! $_ % 10;
            sleep 1;
        }
        like($node->_data('mac'),qr(\d\d:\d\d:\d\d:\d\d:)) or next;

        $node->shutdown();
        is( $node->is_active, 0 );

        $node->_start_wake_on_lan();
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
