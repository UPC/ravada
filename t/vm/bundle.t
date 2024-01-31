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

sub _req_clone($user, $base) {
    my $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
        ,name => new_domain_name
    );
    wait_request( debug => 0);
}

sub _req_create($user, $base) {
    my $req = Ravada::Request->create_domain(
        id_owner => $user->id
        ,id_base => $base->id
        ,name => new_domain_name
    );
    wait_request( debug => 0);
}


sub test_bundle($vm, $do_clone=0, $volatile=0) {

    my $base1 = create_domain_v2(vm => $vm);
    $base1->prepare_base(user_admin);
    $base1->is_public(1);
    $base1->volatile_clones(1) if $volatile;

    my $base2 = create_domain($vm);
    $base2->prepare_base(user_admin);
    $base2->is_public(1);
    $base2->volatile_clones(1) if $volatile;

    my $name = new_domain_name();
    my $id_bundle = rvd_front->create_bundle($name);
    rvd_front->bundle_private_network($id_bundle,1);

    rvd_front->add_to_bundle($id_bundle, $base1->id);
    rvd_front->add_to_bundle($id_bundle, $base2->id);

    my $user = create_user();

    my @networks0 = $vm->list_virtual_networks();

    if ($do_clone) {
        _req_clone($user, $base1);
    } else {
        _req_create($user, $base1);
    }

    my @clone1 = grep { $_->{id_owner} == $user->id } $base1->clones();
    my @clone2 = grep { $_->{id_owner} == $user->id } $base2->clones();
    is(scalar(@clone1),1);
    is(scalar(@clone2),1);

    my @networks1 = $vm->list_virtual_networks();
    is(scalar(@networks1), scalar(@networks0)+1);

    my $net = _check_net_private($clone1[0]);
    _check_net_private($clone2[0], $net);
    is($clone1[0]->{is_volatile} , $volatile);
    is($clone2[0]->{is_volatile} , $volatile);

    remove_domain(@clone1);
    remove_domain(@clone2);

    if ($do_clone) {
        _req_clone($user, $base2);
    } else {
        _req_create($user, $base2);
    }

    wait_request(debug => 0);

    @clone1 = grep { $_->{id_owner} == $user->id } $base1->clones();
    @clone2 = grep { $_->{id_owner} == $user->id } $base2->clones();
    is(scalar(@clone1),1);
    is(scalar(@clone2),1);

    is($clone1[0]->{is_volatile} , $volatile);
    is($clone2[0]->{is_volatile} , $volatile);

    for my $clone (@clone1, @clone2) {
        Ravada::Request->start_domain( uid => $user->id 
            , id_domain => $clone->{id}
        );
    }
    Ravada::Request->enforce_limits();
    wait_request();

    for my $clone0 ( @clone1, @clone2 ) {
        my $clone = Ravada::Front::Domain->open($clone0->{id} );
        is($clone->is_active,1);
        Ravada::Request->force_shutdown(
            uid => user_admin->id
            ,id_domain => $clone->id
        );
    }
    remove_domain($base1);
    remove_domain($base2);
}

sub _check_net_private($domain, $net=undef) {
    my $net_found = _get_net($domain);
    isnt($net_found->{name}, 'default', "Expecting another net in ".$domain->{name}) or exit;
    my $base = base_domain_name();
    like($net_found->{name},qr/^$base/) or die $domain->{name};
    is ( $net_found->{id_owner}, $domain->{id_owner})
        or confess "Expecting net $net_found->{name} owned by $domain->{id_owner}";

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
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description());

    my ($net_source) = $doc->findnodes("/domain/devices/interface/source");
    return $net_source->getAttribute('network');

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

    test_bundle($vm,1); # with clone and volatile

    test_bundle($vm,0); # create
    test_bundle($vm,1); # with clone
    }
}

end();
done_testing();
