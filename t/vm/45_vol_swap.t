use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

####################################################################

sub test_domain_with_swap {
    my $vm_name = shift;

    my $domain = create_domain($vm_name);
    $domain->add_volume_swap( size => 1000 * 1024);

    my @vol = $domain->list_volumes();
    is(scalar(@vol),3);

    my $clone = $domain->clone(
         name => new_domain_name
        ,user => user_admin
    );
    is($domain->is_base,1);
    is(scalar($clone->list_volumes),2);

    $clone->start(user_admin);
    $clone->shutdown_now(user_admin);

    is(scalar($clone->list_volumes),2);

    my $clone2 = $clone->clone(
        name => new_domain_name
        ,user => user_admin
    );
    is($clone->is_base,0);

    $clone2->start(user_admin);
    $clone2->shutdown_now(user_admin);

    is(scalar($clone2->list_volumes),2);

}
####################################################################

clean();
for my $vm_name ('Void','KVM') {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        my $domain = test_domain_with_swap($vm_name);
    }
}

clean();

done_testing();
