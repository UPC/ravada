use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Storable qw(dclone);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

########################################################################

sub test_threads($vm) {
    my $name = new_domain_name();
    my $id_iso = search_id_iso('Alpine');

    my $n_threads = 4;
    my $req = Ravada::Request->create_domain(
        name => $name
        ,vm => $vm->type
        ,id_iso => $id_iso
        ,id_owner => user_admin->id
        ,memory => 512 * 1024
        ,disk => 1024 * 1024
        ,options => { hardware => { cpu => { cpu => { topology => { threads => $n_threads }}}} }
    );
    wait_request( debug => 0);
    my $domain = $vm->search_domain($name);
    ok($domain);
    my $config = $domain->xml_description();

    my $doc = XML::LibXML->load_xml(string => $config);
    my ($topology) = $doc->findnodes("/domain/cpu/topology");
    ok($topology) or die $domain->name;
    is($topology->getAttribute('threads'), $n_threads);

}

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
        next if $machine !~ /^(pc-i440fx|pc-q35)-(\d+.\d+)/
            && $machine !~ /^(pc)-(\d+\d+)$/;
        my $version = ( $2 or 0 );
        $types{$1} = [ $version,$machine ]
        if !exists $types{$1} || $version > $types{$1}->[0];
    }
    my @types;
    for (keys %types) {
        push @types,($types{$_}->[1]);
    }
    return @types,('pc');
}

sub test_machine_types($vm) {
    my $xml = $vm->vm->get_capabilities();
    my $doc = XML::LibXML->load_xml(string => $xml);
    my @node_emulator = $doc->findnodes("/capabilities/guest/arch/emulator");
    die $doc->toString if !$node_emulator[0];

    my ($found_q35, $found_4m)=(0,0);
    for my $node_emulator (@node_emulator) {
        my $emulator = $node_emulator->textContent;
        next if $emulator !~ /x86_64/i;
        for my $node_arch ($doc->findnodes("/capabilities/guest/arch")) {
            my $arch = $node_arch->getAttribute('name');
            next if $arch =~ /^(i386|arm|aarch)/ || $emulator =~ /i[36]86/;
            for my $machine (_machine_types($vm, $node_arch)) {

                my $id_iso = search_id_iso('Alpine%32');
                $id_iso = search_id_iso('Alpine%64') if $arch eq 'x86_64';

                my $iso = $vm->_search_iso($id_iso);
                diag("$arch $machine $iso->{name}");

                my $name = new_domain_name();

                my $options = dclone($iso->{options});
                $options->{machine} = $machine;
                $options->{arch} = $arch;

                my $req = Ravada::Request->create_domain(
                    name => $name
                    ,vm => $vm->type
                    ,id_iso => $id_iso
                    ,id_owner => user_admin->id
                    ,memory => 512 * 1024
                    ,disk => 1024 * 1024
                    ,options => $options
                );
                wait_request();
                my $domain = $vm->search_domain($name);
                ok($domain);
                my $config = $domain->xml_description();
                my $doc = XML::LibXML->load_xml(string => $config);
                my ($node_type) = $doc->findnodes("/domain/os/type");
                my $dom_machine = $node_type->getAttribute('machine');
                is($dom_machine, $machine) if ($machine ne 'pc');
                is($node_type->getAttribute('arch'), $arch);

                is($node_type->getAttribute('arch'), $iso->{arch});

                if( exists $options->{bios}
                    && $options->{bios} =~ /uefi/i
                        && $iso->{arch} =~ /x86_64/
                        && $node_type->getAttribute('machine') =~ /q35/
                    ) {

                    $found_q35++;
                    my ($loader) = $doc->findnodes('/domain/os/loader/text()');
                    like ($loader,qr/OVMF_CODE_4M.fd$/);
                    $found_4m++;
                }

                $domain->start(user_admin);
                $domain->shutdown_now(user_admin);
                $domain->remove(user_admin) if $domain;
            }
        }
    }
    ok($found_q35);
    ok($found_4m);
}

sub test_req_machine_types($vm) {
    my $req = Ravada::Request->list_machine_types(
        id_vm => $vm->id
        ,uid => user_admin->id
    );
    wait_request();
    my $out_json = $req->output;
    my $out = decode_json($out_json);
    my $n = 2;
    ok(scalar(keys %$out) >= $n,"Expecting at least $n machine architectures"
        .  Dumper($out));
    my $types = $out->{x86_64};
    my $n_types = 3;
    ok(scalar(@$types) >= $n_types," Expecting at least $n_types in 64 bits"
        .Dumper($types));
}

sub test_req_machine_types2($vm) {
    my $req = Ravada::Request->list_machine_types(
        vm_type => $vm->type
        ,uid => user_admin->id
    );
    wait_request();
    my $out_json = $req->output;
    my $out = decode_json($out_json);
    my $n = 2;
    ok(scalar(keys %$out) >= $n,"Expecting at least $n machine architectures"
        .  Dumper($out));
    my $types = $out->{x86_64};
    my $n_types = 3;
    ok(scalar(@$types) >= $n_types," Expecting at least $n_types in 64 bits"
        .Dumper($types));
}

sub _mock_device($vm,$iso, $mock_device) {
    my $device = $iso->{device};
    return if $device && -e $device;

    my $sth = connector->dbh->prepare(
        "UPDATE iso_images SET device=? WHERE id=?"
    );
    $sth->execute($mock_device,$iso->{id});
    $iso->{device} = $mock_device;
}

sub _search_iso_alpine($vm) {
    my $id_alpine = search_id_iso('Alpine%32');
    my $iso = $vm->_search_iso($id_alpine);
    return $iso->{device};
}

sub test_isos($vm) {

    my $req = Ravada::Request->list_machine_types(
        vm_type => $vm->type
        ,uid => user_admin->id
    );
    wait_request($req);
    is($req->error,'');
    like($req->output,qr/./);

    my $machine_types = {};
    $machine_types = decode_json($req->output());

    my $isos = rvd_front->list_iso_images();

    my @skip = ('Android');
    my $device_iso = _search_iso_alpine($vm);
    my ($found_q35, $found_4m) = (0,0);
    for my $iso_frontend ( @$isos ) {
        my $iso;
        eval { $iso = $vm->_search_iso($iso_frontend->{id}, $device_iso) };
        next if $@ && $@ =~ /No.*iso.*found/;
        die $@ if $@;
        next if !$iso->{arch} || $iso->{arch} !~ /^(i686|x86_64)$/;
        next if grep {$iso->{name} =~ /$_/} @skip;

        _mock_device($vm,$iso, $device_iso);
        die Dumper($iso) if !$iso->{device} || !-e $iso->{device};
        for my $machine (@{$machine_types->{$iso->{arch}}}) {
            next if $machine eq 'ubuntu';
            for my $uefi ( 0,1 ) {
                next if $machine =~ /^pc-q35/ && $iso->{arch} !~ /x86_64/ && !$uefi;
                next if $iso->{name} =~ /Windows 11/
                && (!$uefi || $machine !~ /q35/);

                next if !$ENV{TEST_LONG} &&
                ( $iso->{description} =~ /Debian \d /i
                    || $iso->{description} =~ /Mint (18|20)/i
                    || $iso->{description} =~ /Ubuntu (18|20)/i
                );
                diag($iso->{arch}." ".$iso->{name}." ".$machine
                ." uefi=$uefi");
                my $name = new_domain_name();
                my $req = Ravada::Request->create_domain(
                    name => $name
                    ,vm => $vm->type
                    ,id_iso => $iso->{id}
                    ,id_owner => user_admin->id
                    ,memory => 512 * 1024
                    ,disk => 1024 * 1024
                    ,swap => 1024 * 1024
                    ,data => 1024 * 1024
                    ,options => { machine => $machine
                        , arch => $iso->{arch}
                        , uefi => $uefi
                    }
                    ,iso_file => $iso->{device}
                );
                wait_request(debug => 0);
                my $domain = $vm->search_domain($name);
                ok($domain);
                wait_request();
                my $config = $domain->xml_description();
                my $doc = XML::LibXML->load_xml(string => $config);
                my ($node_type) = $doc->findnodes("/domain/os/type");
                my $dom_machine = $node_type->getAttribute('machine');
                is($dom_machine, $machine) if ($machine ne 'pc');

                is($node_type->getAttribute('arch'), $iso->{arch});

                if( $uefi
                        && $iso->{arch} =~ /x86_64/
                        && $node_type->getAttribute('machine') =~ /q35/
                    ) {
                    $found_q35++;
                    my ($loader) = $doc->findnodes('/domain/os/loader/text()');
                    like($loader,qr/OVMF_CODE_4M.fd$/) or die $domain->name;
                    $found_4m++;
                }

                $domain->start(user_admin);
                test_drives($doc);
                $domain->shutdown_now(user_admin);
                $domain->remove(user_admin) if $domain;
            }
        }
    }
    ok($found_q35, "Expecting some q35 machines tested");
    ok($found_4m,"Expected some 4M ovmf found");
}

sub test_drives($doc) {
    my @drives = $doc->findnodes("/domain/devices/disk");
    die "Error: only ".scalar(@drives) if scalar(@drives)<4;
    my $previous = '';
    my $prev_target = '';
    my $prev_file = '';
    for my $drive (@drives) {
        my ($address) = $drive->findnodes("address");
        my ($source) = $drive->findnodes("source");
        my $file = $source->getAttribute('file');
        next if $file =~ /\.iso$/;
        ok($file gt $prev_file);
        $prev_file = $file;
        if ($address->getAttribute('type') eq 'drive') {
            next;
        } else {
            my $bus = $address->getAttribute('bus');
            my $slot = $address->getAttribute('slot');
            my $function = $address->getAttribute('function');

            my ($target_node) = $drive->findnodes('target');
            my $target = $target_node->getAttribute('dev');

            my $current = "$bus.$slot.$function";
            ok($current gt $previous, "Expecting $target greather than $prev_target $current < $previous");
            $previous = $current;
            $prev_target = $target;
        }
    }
}

sub test_nvram($vm) {
    my $name = new_domain_name();
    my $id_iso = search_id_iso('Alpine');

    my $req = Ravada::Request->create_domain(
        name => $name
        ,vm => $vm->type
        ,id_iso => $id_iso
        ,id_owner => user_admin->id
        ,memory => 512 * 1024
        ,disk => 1024 * 1024
        ,options => { uefi => 1, machine => 'q35' }
    );
    wait_request();
    my $domain = $vm->search_domain($name);
    ok($domain);
    my $config = $domain->xml_description();
    my $doc = XML::LibXML->load_xml(string => $config);
    my ($nvram) = $doc->findnodes("/domain/os/nvram");
    ok($nvram,"Expecting /domain/os/nvram");

    $domain->prepare_base(user_admin);

    my $clone = $domain->clone(user => user_admin, name => new_domain_name);
    my $config_clone = $clone->xml_description();
    my $doc_clone = XML::LibXML->load_xml(string => $config_clone);
    my ($nvram_clone) = $doc_clone->findnodes("/domain/os/nvram");
    ok($nvram_clone,"Expecting /domain/os/nvram");
    isnt($nvram_clone->toString, $nvram->toString);

    remove_domain($domain);
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

        test_nvram($vm);

        test_threads($vm);

        test_isos($vm);
        test_req_machine_types($vm);
        test_req_machine_types2($vm);
        test_machine_types($vm);
        test_uefi($vm);

    }
}

end();

done_testing();
