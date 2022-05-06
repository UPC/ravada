use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

=pod

"<feature policy='require' name='ss'/>"

    <feature policy='require' name='vmx'/>
    <feature policy='require' name='pcid'/>
    <feature policy='require' name='hypervisor'/>
    <feature policy='require' name='arat'/>
    <feature policy='require' name='tsc_adjust'/>
    <feature policy='require' name='umip'/>
    <feature policy='require' name='md-clear'/>
    <feature policy='require' name='stibp'/>
    <feature policy='require' name='arch-capabilities'/>
    <feature policy='require' name='ssbd'/>
    <feature policy='require' name='xsaveopt'/>
    <feature policy='require' name='pdpe1gb'/>
    <feature policy='require' name='ibpb'/>
    <feature policy='require' name='ibrs'/>
    <feature policy='require' name='amd-stibp'/>
    <feature policy='require' name='amd-ssbd'/>
    <feature policy='require' name='skip-l1dfl-vmentry'/>
    <feature policy='require' name='pschange-mc-no'/>

=cut

sub test_feat_policy($vm) {
    my $domain = create_domain_v2(
        vm => $vm
        ,id_iso => search_id_iso('alpine%64')
    );
    Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,data => { cpu => { 'mode' => 'host-model', check => 'partial' } }
    );
    wait_request();
    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request( check_error => 0);
    test_add_feature_policy($domain, $req->error ) if $req->error;

    $domain->remove(user_admin);
}

sub _verify_features($domain, @features) {
    diag("Verify features @features");
    my $xml = $domain->xml_description();
    my $doc = XML::LibXML->load_xml(string => $xml);
    my @found = $doc->findnodes("/domain/cpu/feature");
    my %missing = map { $_ => } @features;
    my %dupe;
    for my $feat(@found) {
        my $name = $feat->getAttribute('name');
        delete $missing{$name};
        $dupe{$name}++;
    }
    ok(!keys %missing) or die "Missing features ".Dumper([keys %missing]);
    for my $feat ( keys %dupe ) {
        delete $dupe{$feat} if $dupe{$feat}<2;
    }
    ok(!keys %dupe) or die "Duplicated features ".Dumper(\%dupe);
}

sub test_feature_policy($domain, $feature, $policy='require') {
    my $req_change = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,data => { cpu => { 'mode' => 'host-model', check => 'partial'
            ,feature => [
                { 'policy' => $policy, name => $feature}
                ]
            }
        }
    );
    wait_request( debug => 0);
    my $domain2 = Ravada::Front::Domain->open($domain->id);
    my $xml = $domain2->xml_description();
    my $doc = XML::LibXML->load_xml(string => $xml);
    my @features = $doc->findnodes("/domain/cpu/feature");
    my @found = grep { $_->getAttribute('name') eq $feature }
    $doc->findnodes("/domain/cpu/feature");

    is(scalar(@found),1);
    is($found[0]->getAttribute('name'), $feature) or exit;
    is($found[0]->getAttribute('policy'), $policy, "Expecting feature policy=$policy name=$feature ".$found[0]->toString()) or exit;

}

sub test_remove_feature($domain, $feature) {
    my $cpu = $domain->get_controller( 'cpu' );
    my $old = $cpu->{cpu}->{feature};
    my @keep;
    for (@$old) {
        push @keep,($_) if $_->{name} ne $feature;
    }

    my $req_change = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,data => { cpu => { 'mode' => 'host-model', check => 'partial'
            ,feature => \@keep
            }
        }
    );
    wait_request();
    my $xml = $domain->xml_description();
    my $doc = XML::LibXML->load_xml(string => $xml);
    my @found = grep { $_->getAttribute('name') eq $feature }
    $doc->findnodes("/domain/cpu/feature");

    is(scalar(@found),0) or die Dumper([map { $_->toString } @found]);

}

sub test_add_feature_policy($domain, $error) {
    my ($features) = $error =~ /required features: (.*?)($|\s)/;
    my @features = split /,/,$features;
    my $req_change = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,data => { cpu => { 'mode' => 'host-model', check => 'partial'
            ,feature => [
                { 'policy' => 'disable', name => 'svm'}
                ,{ 'policy' => 'require', name => 'vmx'}
                ]
            }
        }
    );
    wait_request();
    _verify_features($domain, 'svm', 'vmx');

    my $cpu = $domain->get_controller( 'cpu' );
    is(scalar(@{$cpu->{cpu}->{feature}}),2);

    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();
    _verify_features($domain, 'svm', 'vmx');
    $domain->shutdown_now(user_admin);
    $req_change->redo();
    wait_request(debug => 0);

    _verify_features($domain, 'svm', 'vmx');

    test_feature_policy($domain, 'vmx','require');
    test_feature_policy($domain, 'vmx','disable');
    test_remove_feature($domain, 'vmx');

}

########################################################################

init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_feat_policy($vm);
    }
}

end();

done_testing();

