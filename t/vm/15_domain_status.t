use warnings;
use strict;

use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

######################################################################
sub test_has_clones($vm) {
    my $base = create_base($vm);
    is($base->has_clones,0);

    my $clone=$base->clone(
        name => new_domain_name()
        ,user => user_admin
    );
    delete $base->{_data};
    is($base->has_clones,1);
    is($base->has_clones(1),1);
    is(scalar($base->clones()), 1);

    $clone->remove(user_admin);
    delete $base->{_data};
    is($base->has_clones,0);
    is(scalar($base->clones()), 0);

    remove_domain($base);

}

sub test_is_locked($vm) {
    my $base = create_base($vm);
    my $req = Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $base->id
    );
    delete $base->{_data};
    is($base->_data('is_locked'),$req->id);
    delete $base->{_data};
    $base->is_locked();
    is($base->_data('is_locked'),$req->id);

    wait_request();

    delete $base->{_data};
    is($base->_data('is_locked'),0);

    remove_domain($base);
}

######################################################################

clean();

for my $vm_name ( vm_names() ) {

    SKIP: {
        my $vm;
        eval { $vm = rvd_back->search_vm($vm_name) };
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        if (!$vm) {
            diag($msg);
            skip $msg,10;
        }

        test_has_clones($vm);
        test_is_locked($vm);
    }
}

end();
done_testing();
