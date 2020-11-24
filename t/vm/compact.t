use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

sub test_compact($vm) {
    my $domain = create_domain($vm);
    is($domain->_data('is_compacted'),1) or exit;
    $domain->start(user_admin);
    is($domain->_data('is_compacted'),0) or exit;

    eval { $domain->compact() };
    like($@,qr/is active/);

    is($domain->_data('is_compacted'),0);

    $domain->shutdown_now(user_admin);
    is($domain->_data('is_compacted'),0);

    $domain->compact();

    my $req = Ravada::Request->compact(
        id_domain => $domain->id
        ,uid => user_admin->id
    );

    wait_request();
    is($req->status,'done');
    is($req->error, '');

    $domain->remove(user_admin);

}

#######################################################

clean();

for my $vm_name (vm_names() ) {
    ok($vm_name);
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        diag("test compact on $vm_name");
        test_compact($vm);
    }
}

end();
done_testing();
