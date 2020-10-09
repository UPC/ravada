#!perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

init();

sub test_memory_empty($vm) {
    my $domain = create_domain($vm->type);
    ok($domain->get_info->{memory});

    my $clone = $domain->clone( name => new_domain_name, user=> user_admin);
    ok($clone) or return;

    ok($clone->get_info->{memory});

    my $info = $clone->get_info;
    delete $info->{memory};
    $clone->_store(info => $info);

    ok($clone->get_info->{memory});
}

#########################################################################
#
clean();

use_ok('Ravada');

for my $vm_name ( 'Void' ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10        if !$vm;

        test_memory_empty($vm);
    }
}

end();
done_testing();
