use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Mojo::JSON qw( encode_json decode_json );

use Ravada::HostDevice::Templates;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE;

####################################################################

sub _prepare_dir_mdev() {

    my $dir = "/run/user/";

    $dir .= "$</" if $<;
    $dir .= new_domain_name();

    mkdir $dir or die "$! $dir"
    if ! -e $dir;

    my $uuid="3913694f-ca45-a946-efbf-94124e5c09";

    for (1 .. 2 ) {
        open my $out, ">","$dir/$uuid$_$_ " or die $!;
        print $out "\n";
        close $out;
    }
    return $dir;
}

sub test_mdev($vm) {

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($mdev) = grep { $_->{name} eq "GPU Mediated Device" } @$templates;
    ok($mdev,"Expecting PCI template in ".$vm->name) or return;

    my $dir = _prepare_dir_mdev();

    my $id = $vm->add_host_device(template => $mdev->{name});
    my $hd = Ravada::HostDevice->search_by_id($id);

    $hd->_data('list_command' => "ls $dir");

    is( $hd->list_available_devices() , 2);

    my $domain = $BASE->clone(
        name =>new_domain_name
        ,user => user_admin
    );
    $domain->add_host_device($id);

    $domain->_add_host_devices();
    is($hd->list_available_devices(), 1);

    test_config($domain);

    return ($domain, $hd);
}

sub test_config($domain) {

    if ($domain->type eq'KVM') {
        test_xml($domain);
    } elsif ($domain->type eq 'Void') {
        test_yaml($domain);
    } else {
        die "unknown type ".$domain->type;
    }
}

sub test_yaml($domain) {
    my $config = $domain->_load();

    my $hd= $config->{hardware}->{host_devices};
    ok($hd);

    my $features = $config->{features};
    ok($features);

}

sub test_xml($domain) {

    my $xml = $domain->xml_description();

    my $doc = XML::LibXML->load_xml(string => $xml);

    my $hd_path = "/domain/devices/hostdev";
    my ($hostdev) = $doc->findnodes($hd_path);
    ok($hostdev,"Expecting $hd_path") or exit;

    my ($video) = $doc->findnodes("/domain/devices/video/model");
    my $v_type = $video ->getAttribute('type');
    isnt($v_type,'none') or exit;

    my $kvm_path = "/domain/features/kvm/hidden";
    my ($kvm) = $doc->findnodes($kvm_path);
    ok($kvm,"Expecting $kvm_path") or return;
    is($kvm->getAttribute('state'),'on')

}

sub test_base($domain) {

    my @args = ( uid => user_admin->id ,id_domain => $domain->id);

    Ravada::Request->shutdown_domain(@args);
    my $req = Ravada::Request->prepare_base(@args);

    wait_request();

    test_config($domain);

    Ravada::Request->clone(@args, number => 2, remote_ip => '1.2.3.4');
    wait_request();
    is(scalar($domain->clones),2);

    for my $clone_data( $domain->clones ) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->_add_host_devices();
        test_config($clone);
        $clone->remove(user_admin);
    }
}

sub test_volatile_clones($vm, $domain, $host_device) {
    my @args = ( uid => user_admin->id ,id_domain => $domain->id);

    $domain->shutdown_now(user_admin) if $domain->is_active;

    Ravada::Request->prepare_base(@args) if !$domain->is_base();

    wait_request();

    is($host_device->list_available_devices(), 2) or exit;

    $domain->_data('volatile_clones' => 1);
    my $n_clones = $domain->clones;

    my $n=2;
    my $exp_avail = $host_device->list_available_devices()- $n;

    Ravada::Request->clone(@args, number => $n, remote_ip => '1.2.3.4');
    wait_request(check_error => 0);
    is(scalar($domain->clones), $n_clones+$n);

    my $n_device = $host_device->list_available_devices();
    is($n_device,$exp_avail);

    for my $clone_data( $domain->clones ) {
        diag($clone_data->{name});
        my $clone = Ravada::Domain->open($clone_data->{id});
        test_config($clone);
        is($clone->is_volatile,1);
        $clone->shutdown_now(user_admin);

        $n_device = $host_device->list_available_devices();
        is($n_device,++$exp_avail) or exit;

        my $clone_gone = rvd_back->search_domain($clone_data->{name});
        ok(!$clone_gone,"Expecting $clone_data->{name} removed on shutdown");

        my $clone_gone2 = $vm->search_domain($clone_data->{name});
        ok(!$clone_gone2,"Expecting $clone_data->{name} removed on shutdown");

        my $clone_gone3;
        eval { $clone_gone3 = $vm->import_domain($clone_data->{name},user_admin,0) };
        ok(!$clone_gone3,"Expecting $clone_data->{name} removed on shutdown") or exit;
    }
    $domain->_data('volatile_clones' => 0);
    is($host_device->list_available_devices(), 2) or exit;
}

####################################################################

clean();

for my $vm_name ('KVM', 'Void' ) {
    my $vm;
    eval {
        $vm = rvd_back->search_vm($vm_name)
        unless $vm_name eq 'KVM' && $<;
    };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        if ($vm_name eq 'Void') {
            $BASE = create_domain($vm);
        } else {
            $BASE = import_domain($vm);
        }
        my ($domain, $host_device) = test_mdev($vm);
        test_volatile_clones($vm, $domain, $host_device);
        test_base($domain);

    }
}

end();
done_testing();

