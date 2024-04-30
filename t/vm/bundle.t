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

sub _req_clone($user, @base) {
    for my $base (@base) {
        my $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
        ,name => new_domain_name
        );
    }
    wait_request( debug => 0);
}

sub _req_create($user, @base) {
    for my $base (@base) {
        my $req = Ravada::Request->create_domain(
        id_owner => $user->id
        ,id_base => $base->id
        ,name => new_domain_name
        );
    }
    wait_request( debug => 0);
}


sub _search_clones($user, $base) {
    my @clones = grep { $_->{id_owner} == $user->id }
            $base->clones();
    return @clones;
}

sub _check_net_equal($user, @bases) {
    my $net;
    for my $base ( @bases ) {

        my @clone1 = _search_clones($user, $base);
        is(scalar(@clone1),1) or exit;

        if($net) {
            $net = _check_net_private($clone1[0], $net);
        } else {
            $net = _check_net_private($clone1[0]);
        }
    }
}

sub _start_clones($user, @bases) {

    for my $base ( @bases ) {
        my ($clone) = _search_clones($user, $base);
        Ravada::Request->start_domain(
            uid => $clone->{id_owner}
            ,id_domain => $clone->{id}
        );
    }
    wait_request();
}

sub _check_clones_active($user, @bases) {
    for my $base (@bases) {
        my ($clone0) = grep { $_->{id_owner} == $user->id }
            $base->clones();
        my $clone = Ravada::Domain->open($clone0->{id});
        is($clone->is_active,1);
    }
}

sub _create_n_bases($vm, $id_bundle, $n, $volatile) {

    my @bases;
    for my $count ( 1 .. $n ) {
        my $base1 = create_domain_v2(vm => $vm);
        $base1->prepare_base(user_admin);
        $base1->is_public(1);
        $base1->volatile_clones(1) if $volatile;

        rvd_front->add_to_bundle($id_bundle, $base1->id);

        push @bases,($base1);
    }
    return @bases;
}

sub _test_not_bundled_limit($vm, $user, @bases) {
    my $base1 = create_domain_v2(vm => $vm);
    $base1->prepare_base(user_admin);
    $base1->is_public(1);

    _req_clone($user, $base1);

    _start_clones($user, @bases, $base1);

    Ravada::Request->enforce_limits();
    wait_request(debug => 1);

    _check_clones_active($user, @bases);
    my ($clone_down0) = _search_clones($user, $base1);

    my $clone = Ravada::Domain->open($clone_down0->{id});
    is($clone->is_active,0);

    remove_domain($base1);
}

sub test_bundle_2($vm, $n, $do_clone=0, $volatile=0) {
    my $name = new_domain_name();
    my $id_bundle = rvd_front->create_bundle($name);
    rvd_front->bundle_private_network($id_bundle,1);

    my @bases = _create_n_bases($vm, $id_bundle, $n, $volatile);

    my $user = create_user();
    die "Error: user ".$user->name." should not be admin"
    if $user->is_admin;

    if ($do_clone) {
        _req_clone($user, @bases);
    } else {
        _req_create($user, @bases);
    }
    _check_net_equal($user, @bases);
    _start_clones($user, @bases);

    Ravada::Request->enforce_limits();
    wait_request(debug => 1);
    _check_clones_active($user, @bases);

    _test_not_bundled_limit($vm, $user, @bases);

    remove_domain(@bases);
}

sub test_bundle($vm, $do_clone=0, $volatile=0) {

    my $base1 = create_domain_v2(vm => $vm);
    $base1->prepare_base(user_admin);
    $base1->is_public(1);
    $base1->volatile_clones(1) if $volatile;

    my $base2a = create_domain($vm);
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,name => 'network'
        ,id_domain => $base2a->id
    );
    wait_request( debug => 0);
    my $base2 = Ravada::Domain->open($base2a->id);
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
        _req_clone($user, $base1, $base2);
    } else {
        _req_create($user, $base1, $base2);
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

    my @nets_2 = _get_net($clone2[0]);
    is(scalar(@nets_2),2) or die $clone2[0]->{name};

    remove_domain(@clone1);
    remove_domain(@clone2);

    if ($do_clone) {
        _req_clone($user, $base2, $base1);
    } else {
        _req_create($user, $base2, $base1);
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
    my $found;
    for my $net_found ( _get_net($domain) ) {
        isnt($net_found->{name}, 'default', "Expecting another net in ".$domain->{name}) or exit;
        my $base = base_domain_name();
        like($net_found->{name},qr/^$base/) or die $domain->{name};
        is ( $net_found->{id_owner}, $domain->{id_owner})
            or confess "Expecting net $net_found->{name} owned by $domain->{id_owner}";

        if (defined $net) {
            is($net_found->{name}, $net->{name});
        }

        $found = $net_found if $net_found->{name} ne 'default';
    }
    return $found;
}

sub _get_net($domain0) {
    my $domain = $domain0;
    if (ref($domain) !~ /^Ravada::/) {
        $domain = Ravada::Domain->open($domain0->{id});
    }

    my @net_name;
    if ($domain->type eq 'KVM') {
        @net_name = _get_net_kvm($domain);
    } elsif ($domain->type eq 'Void') {
        @net_name = _get_net_void($domain);
    }

    die "Error: no net found in ".$domain->name if !@net_name;

    my @net;
    for my $name (@net_name) {
        push @net, grep { $_->{name} eq $name }
        $domain->_vm->list_virtual_networks;
    }
    return @net;
}

sub _get_net_kvm($domain) {
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description());

    my @net_source = $doc->findnodes("/domain/devices/interface/source");
    my @names;
    for my $net (@net_source) {
        push @names, $net->getAttribute('network');
    }
    return @names;

}

sub _get_net_void($domain) {
    my $config = $domain->get_config();
    my @names;
    for my $net ( @{$config->{hardware}->{network}} ) {
        push @names,($net->{name});
    }
    return @names;
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

    test_bundle_2($vm,3,0);
    test_bundle_2($vm,3,1);

    test_bundle_2($vm,4,0);
    test_bundle_2($vm,4,1);

    test_bundle($vm,1); # with clone and volatile

    test_bundle($vm,0); # create
    test_bundle($vm,1); # with clone

    }
}

end();
done_testing();
