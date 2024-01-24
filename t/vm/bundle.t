use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

#################################################################
sub test_bundle($vm) {

    my $base1 = create_domain_v2(vm => $vm);
    $base1->prepare_base(user_admin);
    $base1->is_public(1);

    my $base2 = create_domain($vm);
    $base2->prepare_base(user_admin);
    $base2->is_public(1);

    my $name = new_domain_name();
    my $id_bundle = rvd_front->create_bundle($name);
    rvd_front->bundle_private_network($id_bundle,1);

    rvd_front->add_to_bundle($id_bundle, $base1->id);
    rvd_front->add_to_bundle($id_bundle, $base2->id);

    my $user = create_user();

    my @networks0 = $vm->list_virtual_networks();

    my $req_clone1 = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base1->id
        ,name => new_domain_name
    );
    wait_request( debug => 1);
    wait_request( debug => 1);

    my @clone1 = grep { $_->{id_owner} == $user->id } $base1->clones();
    my @clone2 = grep { $_->{id_owner} == $user->id } $base2->clones();
    is(scalar(@clone1),1);
    is(scalar(@clone2),1);

    my @networks1 = $vm->list_virtual_networks();
    is(scalar(@networks1), scalar(@networks0)+1);

    my $net = _check_net_private($clone1[0]);
    _check_net_private($clone2[0], $net);

    remove_domain(@clone1);
    remove_domain(@clone2);

    my $req_clone2 = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base2->id
        ,name => new_domain_name
    );
    wait_request(debug => 1);

    @clone1 = grep { $_->{id_owner} == $user->id } $base1->clones();
    @clone2 = grep { $_->{id_owner} == $user->id } $base2->clones();
    is(scalar(@clone1),1);
    is(scalar(@clone2),1);

    remove_domain($base1);
    remove_domain($base2);
}

sub _check_net_private($domain, $net=undef) {
    my $net_found = _get_net($domain);
    isnt($net_found->{name}, 'default') or exit;
    is ( $net_found->{id_owner}, $domain->{id_owner})
        or die "Expecting net $net_found->{name} owned by $domain->{id_owner}";

    if (defined $net) {
        is($net_found->{name}, $net->{name});
    }
    return $net_found;
}

sub _get_net($domain0) {
    my $domain = $domain0;
    if (ref($domain) !~ /^Ravada::/) {
        $domain = Ravada::Domain->open($domain0->{id});
    }

    my $net_name;
    if ($domain->type eq 'KVM') {
        $net_name = _get_net_kvm($domain);
    } elsif ($domain->type eq 'Void') {
        $net_name = _get_net_void($domain);
    }

    die "Error: no net found in ".$domain->name if !$net_name;

    my ($net) = grep { $_->{name} eq $net_name }
        $domain->_vm->list_virtual_networks;

    return $net;
}

sub _get_net_kvm($domain) {
}

sub _get_net_void($domain) {
    my $config = $domain->get_config();
    return ($config->{hardware}->{network}->[0]->{name});
}
#################################################################

init();
clean();
for my $vm_name ( vm_names() ) {

    SKIP: {
    my $vm = rvd_back->search_vm($vm_name);

    my $msg = "SKIPPED test: No $vm_name VM found ";
    if ($vm_name ne 'Void' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    diag("Testing $vm_name bundle");

    test_bundle($vm);
    }
}

end();
done_testing();
