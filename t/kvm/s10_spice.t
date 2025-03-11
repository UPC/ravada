use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use feature qw(signatures);
no warnings "experimental::signatures";

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

init();
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

my $TLS=0;

#######################################################

sub test_displays {
    my $domain = shift;
    my @displays = $domain->_get_controller_display();
    is(scalar @displays,1 + $TLS);
}

sub test_spice {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , disk => 1024 * 1024
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start($USER);
    wait_request(debug => 0);

    test_displays($domain);

    my $display_file = $domain->display_file($USER);

    my $display = $domain->display($USER);
    my ($ip_d,$port_d) = $display =~ m{spice://(.*):(.*)};
    my ($ip_f) = $display_file =~ m{host=(.*)}mx;
    my ($port_f) = $display_file =~ m{port=(.*)}mx;
    is($ip_d, $ip_f);
    is($port_d, $port_f);
    return $domain;
}

sub _remove_display($domain) {
    my $req = Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,index => 0
    );
    wait_request();

    is($req->error,'');

    my $doc =XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my ($spice) = $doc->findnodes("/domain/devices/graphics");
    ok(!$spice);

    my $info = $domain->info(user_admin);
    my ($hw_spice) = grep { $_->{driver} =~ /spice/ } @{$info->{hardware}->{display}};
    ok(!$hw_spice);
}

sub _add_display($domain,$driver='spice') {
    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,data => { driver => $driver}
    );
    wait_request();

    my $doc =XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my ($spice) = $doc->findnodes("/domain/devices/graphics[\@type='$driver']");
    ok($spice);

    my @redir = $doc->findnodes("/domain/devices/redirdev[\@type=\'spicevmc\']");
    ok(scalar(@redir)>2);

    my @audio = $doc->findnodes("/domain/devices/audio[\@type='spice']");
    is(scalar(@audio),1);

    my @channel = $doc->findnodes("/domain/devices/channel[\@type='spicevmc']");
    is(scalar(@channel),1);
}

sub test_remove_spice($domain) {
    $domain->shutdown_now(user_admin) if $domain->is_active;

    my $doc =XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my ($spice) = $doc->findnodes("/domain/devices/graphics");
    die "Error: no spice found in ".$domain->name if !$spice;

    _remove_display($domain);

    _add_display($domain, 'spice');

    $domain->start(user_admin);

    my $info = $domain->info(user_admin);
    like($info->{hardware}->{display}->[0]->{driver},qr'spice');
}

#######################################################

if ($>)  {
    diag("SKIPPED: Test must run as root");
    done_testing();
    exit;
}

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);


SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    $TLS = 1 if check_libvirt_tls() && $vm_name eq 'KVM';

    my $domain = test_spice($vm_name);
    test_remove_spice($domain);
}

end();
done_testing();
