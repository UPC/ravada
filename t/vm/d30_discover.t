use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

########################################################################

sub test_discover($vm) {
    my $domain = create_domain($vm);
    my $name = $domain->name;
    my $id = $domain->id;
    Ravada::Domain::_remove_domain_data_db($id);

    my $domain_removed = rvd_back->search_domain($name);
    is($domain_removed, undef) or warn Dumper($domain_removed->{_data});

    my @discover = $vm->discover();
    my ($found1) = grep { $_ eq $name } @discover;

    ok($found1,"Expecting $name in discover for ".$vm->type) or die Dumper(\@discover);
    my @list = $vm->list_domains();

    my ($found2) = grep { $_->{name} eq $name } @list;

    ok(!$found2,"Expecting no $name in list");

    my $req = Ravada::Request->discover(
        id_vm => $vm->id
        ,uid => user_admin->id
    );
    wait_request();
    my $out = $req->output;
    like($out,qr/./);

    my $decoded = decode_json($out);

    my ($found3) = grep { $_ eq $name } @$decoded;
    ok($found3, "Expecting $name in requested discover for ".$vm->type)
        or die $decoded;

    my $req_import = Ravada::Request->import_domain(name => $found3
        ,vm => $vm->type
        ,id_owner => user_admin->id
        ,uid => user_admin->id
    );
    wait_request( debug => 0);

    my $domain2 = rvd_back->search_domain($name);
    ok($domain2,"Expecting $name imported in ".$vm->type);

    if ($domain2) {
        ok($domain2->name, $name);
        $domain2->remove(user_admin);
    }
}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm eq 'KVM' && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_discover($vm);
    }
}

end();

done_testing();
