#!perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';
use Test::Ravada;

# init ravada for testing
init();
my $USER = create_user("foo","bar", 1);

##############################################################################

sub test_remove_domain {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    $domain->shutdown( user => user_admin )  if $domain->is_active();
    
    $domain->domain->undefine();

    my $removed = $domain->is_removed;

    ok($removed, "Domain deleted: $removed");
    
    eval{ $domain->remove(user_admin) };
    
    is($@,"");

    my $list = rvd_front->list_domains();
    is(scalar @$list , 0);

}


##############################################################################

clean();

use_ok('Ravada');

for my $vm_name ( q'KVM' ) {

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

        diag("Testing remove on $vm_name");

		test_remove_domain($vm);        

    }
}

clean();

done_testing();
