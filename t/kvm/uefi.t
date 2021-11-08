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

sub test_uefi($vm) {
    my $name = new_domain_name();
    my $id_iso = search_id_iso('Alpine');

    my $req = Ravada::Request->create_domain(
        name => $name
        ,vm => $vm->type
        ,id_iso => $id_iso
        ,id_owner => user_admin->id
        ,memory => 512 * 1024
        ,disk => 1024 * 1024
        ,options => { uefi => 1 }
    );
    wait_request();
    my $domain = $vm->search_domain($name);
    ok($domain);
    my $config = $domain->xml_description();
    my $doc = XML::LibXML->load_xml(string => $config);
    my ($loader) = $doc->findnodes("/domain/os/loader");
    ok($loader,"Expecting /domain/os/loader") or die $name;
    my ($nvram) = $doc->findnodes("/domain/os/nvram");
    ok($nvram,"Expecting /domain/os/nvram");
    $domain->start(user_admin);
    $domain->shutdown_now(user_admin);
    $domain->remove(user_admin) if $domain;
}

sub _machine_types($vm, $node_arch) {
    my %types;
    for my $node_machine (sort { $a->textContent cmp $b->textContent } $node_arch->findnodes("machine")) {
        my $machine = $node_machine->textContent;
        warn$machine;
        next if $machine !~ /^(pc-i440fx|pc-q35)-(\d+.\d+)/;
        $types{$1} = $machine if !exists $types{$1} || $2 > $types{$1};
    }
    warn Dumper(\%types);
    return sort values %types;
}

sub test_machine_types($vm) {
    my $xml = $vm->vm->get_capabilities();
    my $doc = XML::LibXML->load_xml(string => $xml);
    my ($node_emulator) = $doc->findnodes("/capabilities/guest/arch/emulator");
    die $doc->toString if !$node_emulator;
    my $emulator = $node_emulator->textContent;
    for my $node_arch ($doc->findnodes("/capabilities/guest/arch")) {
        my $arch = $node_arch->getAttribute('name');
        next if $arch ne 'amd64';
        for my $machine (_machine_types($vm, $node_arch)) {
            diag("$emulator $arch $machine");
            my $name = new_domain_name();
            my $id_iso = search_id_iso('Alpine');

            my $req = Ravada::Request->create_domain(
                name => $name
                ,vm => $vm->type
                ,id_iso => $id_iso
                ,id_owner => user_admin->id
                ,memory => 512 * 1024
                ,disk => 1024 * 1024
                ,options => { machine => $machine, arch => $arch }
            );
            wait_request();
            my $domain = $vm->search_domain($name);
            ok($domain);
            my $config = $domain->xml_description();
            my $doc = XML::LibXML->load_xml(string => $config);
            my ($node_type) = $doc->findnodes("/domain/os/type");
            if ($machine !~ /^ubuntu/) {
                if ($machine eq 'q35') {
                    like($node_type->getAttribute('machine'), qr/^pc-q35/);
                } elsif ($machine eq 'pc') {
                    like($node_type->getAttribute('machine'), qr/^pc-/);
                } else {
                    is($node_type->getAttribute('machine'), $machine) or exit;
                }
            }
            $domain->start(user_admin);
            $domain->shutdown_now(user_admin);
            $domain->remove(user_admin) if $domain;
        }
    }
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

        test_machine_types($vm);
        test_uefi($vm);
    }
}

end();

done_testing();
