#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Storable qw(dclone);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my @MOCK_ISOS;

init();

sub _search_iso_alpine($vm) {
    my $id_alpine = search_id_iso('Alpine%32');
    my $iso = $vm->_search_iso($id_alpine);
    return $iso->{device};
}

sub _req_add_cd($domain) {
    my $info = $domain->info(user_admin);
    my $disks = $info->{hardware}->{disk};

    my $file = _create_mock_iso($domain->_vm);
    my $req = Ravada::Request->add_hardware(
        uid => Ravada::Utils::user_daemon->id
        ,id_domain => $domain->id
        ,name => 'disk'
        ,data => { type => 'cdrom'
            ,file => $file
        }
    );
    wait_request(debug => 0);
}

sub _req_remove_cd($domain) {
    my $info = $domain->info(user_admin);
    my $disks = $info->{hardware}->{disk};
    my $n=0;
    for my $disk (@$disks) {
        last if $disk->{file} =~ /\.iso$/;
        $n++;
    }
    my $req = Ravada::Request->remove_hardware(
        uid => Ravada::Utils::user_daemon->id
        ,id_domain => $domain->id
        ,name => 'disk'
        ,index => $n
    );
    wait_request( debug => 0);
}
sub _create_mock_iso($vm) {

    my $file = $vm->dir_img()."/".new_domain_name()."a.iso";
    open my $out, ">>",$file or die "$! $file";
    print $out "test\n";
    close $out;

    push @MOCK_ISOS,($file);

    return $file;
}


sub _req_create($vm, $iso, $options) {
    my $name = new_domain_name();
    my @args = (
        name => $name
        ,vm => $vm->type
        ,id_iso => $iso->{id}
        ,id_owner => user_admin->id
        ,memory => 512 * 1024
        ,disk => 1024 * 1024
        #        ,swap => 1024 * 1024
        #   ,data => 1024 * 1024
        ,iso_file => $iso->{device}
        ,start => 1
    );
    push @args,(options => $options) if defined $options;

    my $req = Ravada::Request->create_domain(@args);
    wait_request( debug => 0);
    my $domain = $vm->search_domain($name);
    ok($domain) or die "No machine $name ".Dumper($iso);
    $domain->shutdown_now(user_admin);
    return $domain;
}

sub remove_mock_isos() {
    for my $file (@MOCK_ISOS) {
        next if $file !~ m{/tst_};
        unlink $file if -e $file;
    }
}

sub test_cdrom($vm) {
    return if $vm->type ne 'KVM';

    my $device_iso = _search_iso_alpine($vm);
    my %machine_types = $vm->list_machine_types();
    my $machine_types = \%machine_types;

    my $isos0 = rvd_front->list_iso_images();
    my $isos = dclone($isos0);
    if ( !$ENV{TEST_STRESS} ) {

        my ($alpine32) = grep { $_->{name} =~ /alpine.*32/i } @$isos;
        my ($alpine64) = grep { $_->{name} =~ /alpine.*64/i } @$isos;
        my ($ubuntu) = grep { $_->{name} =~ /ubuntu/i} @$isos;

        $isos = [$alpine32,$alpine64,$ubuntu];

    }

    for my $iso_frontend (@$isos) {
        next if !$iso_frontend->{arch};
        my $iso;
        eval { $iso = $vm->_search_iso($iso_frontend->{id}, $device_iso) };
        next if $@ && $@ =~ /No.*iso.*found/;
        die $@ if $@;
        $iso->{device} = $device_iso;

        my %done;
        for my $bios ('uefi', undef, 'legacy') {
            die Dumper($iso) if !$iso->{arch} || !$machine_types->{$iso->{arch}};
            for my $machine ( @{$machine_types->{$iso->{arch}}}) {
                next if defined $bios && $bios eq 'uefi' && $machine !~ /q35/;
                my $key = ($bios or '')."-".($machine or '')."-"
                    .$iso->{xml}."-".($iso->{xml_volume} or '');
                next if $done{$key}++;
                my %options;
                $options{bios}=$bios if defined $bios;
                $options{machine}=$machine if defined $machine;

                my $domain = _req_create($vm, $iso, \%options);

                _req_add_cd($domain);
                _req_remove_cd($domain);
                _req_add_cd($domain);
                $domain->prepare_base(user_admin);
                $domain->remove_base(user_admin);

                _req_add_cd($domain);

                remove_domain($domain);
                remove_mock_isos();

            }
        }
    }
}

#############################################################################

clean();


for my $vm_name (vm_names() ) {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";

        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        diag("Testing ISOs for $vm_name");

        test_cdrom($vm);

	}
}

end();
done_testing();
