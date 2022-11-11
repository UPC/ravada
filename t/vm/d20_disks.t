#!/usr/bin/perl
# test volatile anonymous domains kiosk mode

use warnings;
use strict;

use Data::Dumper;
use Mojo::JSON qw(decode_json);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my @MOCK_ISOS;

init();
#############################################################################

sub test_frontend {
    my $vm = shift;
    my $swap = ( shift or 0);
    my $domain = create_domain($vm);

    my @volumes = $domain->list_volumes();
    is(scalar@volumes,2);

    $domain->info(user_admin);
    my $domain_f = rvd_front->search_domain($domain->name);
    my @volumes_f = $domain_f->list_volumes();

    is(scalar @volumes_f, scalar @volumes);

    my $info = $domain_f->info(user_admin);
    isa_ok($info->{hardware}->{disk}->[0],'HASH') or die Dumper($domain->name,$info->{hardware});

    $domain->remove(user_admin);
}

sub test_frontend_refresh {
    my $vm = shift;
    my $domain = create_domain($vm);

    my $sth = connector->dbh->prepare("UPDATE domains SET info=? WHERE id=?");
    $sth->execute('',$domain->id);

    $sth = connector->dbh->prepare("DELETE FROM volumes WHERE id_domain=?");
    $sth->execute($domain->id);

    my $req = Ravada::Request->refresh_machine(id_domain => $domain->id, uid => user_admin->id);
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    is($req->error, '');

    my $domain_f = rvd_front->search_domain($domain->name);
    my $info = $domain_f->info(user_admin);
    ok($info) or return;
    my $disk = $info->{hardware}->{disk};
    isa_ok($disk,'ARRAY') or return;
    isa_ok($disk->[0],'HASH', Dumper($disk));

    $domain->remove(user_admin);
}

sub test_remove_disk($vm, %options) {
    my $make_base = delete $options{make_base};
    my $clone = delete $options{clone};
    my $remove_by_file = ( delete $options{remove_by_file} or 0);
    my $remove_by_index = ( delete $options{remove_by_index} or 1);
    my $add_iso_to_clone = delete $options{add_iso_to_clone};
    return if $clone && $vm->type eq 'Void';

    my $id_iso = ( delete $options{id_iso} or search_id_iso('Alpine%64'));

    die "Error: unknown options ".Dumper(\%options)
    if keys %options;

    for my $index ( 0 .. 2 ) {
        my $name = new_domain_name();
        my $req = Ravada::Request->create_domain(
            name => $name
            ,id_owner => user_admin->id
            ,disk => 2*1024 * 1024
            ,swap => 1024 * 1024
            ,data => 1024 * 1024
            ,id_iso => $id_iso
            ,vm => $vm->type
        );
        wait_request(debug => 0);

        is($req->error,'');
        my $domain = rvd_back->search_domain($name);
        ok($domain) or return;

        if ($make_base) {
            $domain->prepare_base(user_admin);
            $domain->remove_base(user_admin);
        }
        if ($clone || $add_iso_to_clone) {
            $domain->prepare_base(user_admin);
            my $clone = $domain->clone(
                name => new_domain_name()
                ,user => user_admin
            );
            $domain = $clone;
            _add_iso_to_clone($domain) if $add_iso_to_clone;
        }

        my $info0 = $domain->info(user_admin);
        my $n_disks0 = scalar(@{$info0->{hardware}->{disk}});
        my %files0 = map { ($_->{file} or '') => 1 } @{$info0->{hardware}->{disk}};
        my $expect_removed = $info0->{hardware}->{disk}->[$index];

        my @way = ( index => $index );
        @way = ( option => { "source/file" => $expect_removed->{file} } )
        if $remove_by_file && $expect_removed->{file};

        push @way ,( index => $index )
        if $remove_by_index;

        my $req_rm = Ravada::Request->remove_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,name => 'disk'
            ,@way
        );
        wait_request(debug => 0);
        is($req_rm->status,'done');
        is($req_rm->error, '');
        my $info = $domain->info(user_admin);
        my $n_disks = scalar(@{$info->{hardware}->{disk}});
        my %files = map { ($_->{file} or '') => 1 } @{$info->{hardware}->{disk}};
        is($n_disks, $n_disks0-1) or exit;

        isnt($info->{hardware}->{disk}->[$index]->{file}
            ,$info0->{hardware}->{disk}->[$index]->{file})
        if $index<3;

        if ($expect_removed->{file}) {
            if ($expect_removed->{device} eq 'cdrom') {
                ok(-e $expect_removed->{file},$expect_removed->{file});
            } else {
                ok(!-e $expect_removed->{file}) or die "$expect_removed->{file} should be removed";
            }
        }
        _check_volumes_table($domain, $n_disks, $expect_removed->{file});
        _check_info($domain, $n_disks, $expect_removed->{file});
        _check_info_front($domain->id, $n_disks, $expect_removed->{file});

        $domain->remove(user_admin);
    }
}

sub _add_iso_to_clone($domain) {

    my $file = '/var/lib/libvirt/images/alpine-standard-3.8.1-x86.iso';
    $file = "/var/tmp/alpine-standard-3.8.1-x86.iso" if $<;
    my $req = Ravada::Request->add_hardware(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,'data' => {
            'driver' => 'ide',
            'type' => 'sys',
            'allocation' => '0.1G',
            'device' => 'cdrom',
            'file' => $file,
            'capacity' => '1G'
        },
        'name' => 'disk',
    );
    wait_request();
}

sub _check_volumes_table($domain, $n_disks, $file) {
    my $sth = connector->dbh->prepare(
        "SELECT count(*) FROM volumes WHERE id_domain=?"
    );
    $sth->execute($domain->id);
    my ($count) = $sth->fetchrow;
    is($count, $n_disks) or exit;

    return if !$file;
    $sth = connector->dbh->prepare(
        "SELECT * FROM volumes WHERE id_domain=? AND file=?"
    );
    $sth->execute($domain->id, $file);
    my $row = $sth->fetchrow_hashref;
    ok(!$row->{id}) or die Dumper($row);
}

sub _check_info($domain, $n_disks, $file) {
    my $info = $domain->info(user_admin);
    my @disks = @{$info->{hardware}->{disk}};
    is(scalar(@disks), $n_disks) or die Dumper(\@disks);

    return if !$file;
    my ($gone) = grep { defined $_->{file} && $_->{file} eq $file} @disks;
    ok(!$gone, "Expecting $file gone") or die Dumper(\@disks);
}

sub _check_info_front($id_domain, $n_disks, $file) {

    my $domain = Ravada::Front::Domain->open($id_domain);
    my $info = $domain->info(user_admin);
    my @disks = @{$info->{hardware}->{disk}};
    is(scalar(@disks), $n_disks) or die Dumper(\@disks);

    return if !$file;
    my ($gone) = grep { defined $_->{file} && $_->{file} eq $file} @disks;
    ok(!$gone, "Expecting $file gone") or die Dumper(\@disks);
}


sub test_add_cd($vm, $data) {

    my $domain = create_domain($vm);

    my $info0 = $domain->info(user_admin);
    my $n_disks0 = scalar(@{$info0->{hardware}->{disk}});
    my %targets0 = map { $_->{target} => 1 } @{$info0->{hardware}->{disk}};

    if ($data->{device} eq 'cdrom' && exists $data->{file} && $data->{file} =~ /tmp/) {
        open my $out, ">>",$data->{file} or die "$! $data->{file}";
        close $out;
    }
    my $req = Ravada::Request->add_hardware(
        id_domain => $domain->id
        ,name => 'disk'
        ,uid => user_admin->id
        ,'data' => $data
    );
    ok($req);
    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error,'');
    my $info = $domain->info(user_admin);
    my $n_disks = scalar(@{$info->{hardware}->{disk}});
    is($n_disks, $n_disks0+1);

    my $new_dev;
    for my $dev ( @{$info->{hardware}->{disk}} ) {
        next if $targets0{$dev->{target}};
        $new_dev = $dev;
        last;
    }
    is($new_dev->{driver_type}, 'raw');
    is($new_dev->{driver}, 'ide');
    is($new_dev->{file},$data->{file});
    if ($data->{device} eq 'cdrom' && exists $data->{file} && $data->{file} =~ /tmp/) {
        unlink $data->{file} or die "$! $data->{file}";
    }

}

sub test_add_disk {
    my $vm = shift;
    my $swap = ( shift or 0);
    my $domain = create_domain($vm);

    my @volumes = $domain->list_volumes();

    my $req = Ravada::Request->add_hardware(
        id_domain => $domain->id
        ,name => 'disk'
        ,uid => user_admin->id
        ,data => {
            size => 512 * 1024
            ,swap => $swap
        }
    );
    ok($req);
    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error,'');

    my @volumes2 = $domain->list_volumes();

    is(scalar @volumes2, scalar(@volumes)+1);

    my $domain_f = rvd_front->search_domain($domain->name);
    my @volumes_f = $domain_f->list_volumes();

    is(scalar @volumes_f, scalar @volumes2, $domain->name." [".$vm->type."]") or exit;
    $domain->info(user_admin);
    my $info = $domain_f->info(user_admin);
    is(scalar(@{$info->{hardware}->{disk}}),scalar(@volumes2),Dumper($info->{hardware}->{disk},$domain->name)) or exit;
    isa_ok($info->{hardware}->{disk}->[1],'HASH') or exit;
    $domain->remove(user_admin);
}

sub test_add_disk_boot_order($vm, $iso_name, $options=undef) {
    return if $vm->type ne 'KVM';

    my $domain = create_domain_v2(vm => $vm, iso_name => $iso_name
    , options => $options);
    $domain->add_volume( boot => 1 , name => $domain->name.'-troy' );
    my @volumes = $domain->list_volumes_info();
    my ($troy) = grep { $_->name =~ m/-troy\.\w+$/ } @volumes;
    ok($troy,"Expecting volume called -troy\$") or die Dumper(\@volumes);

    is($troy->info->{boot}, 1);

    $domain->add_volume( boot => 1 , name => $domain->name.'-abed');
    @volumes = $domain->list_volumes_info();
    my ($abed) = grep { $_->name =~ /-abed/ } @volumes;
    is($abed->info->{boot}, 1);
    ($troy) = grep { $_->name =~ m/-troy/ } @volumes;
    is($troy->info->{boot}, 2);


    $domain->add_volume( boot => 2 , name => $domain->name.'-jeff');
    @volumes = $domain->list_volumes_info();
    my ($jeff) = grep { $_->name =~ /-jeff/ } @volumes;

    ($abed) = grep { $_->name =~ m/-abed/ } @volumes;
    is($abed->info->{boot}, 1);

    ($troy) = grep { $_->name =~ m/-troy/ } @volumes;
    is($troy->info->{boot}, 3);

    $domain->change_hardware('disk',0,{ boot => 1 });
    @volumes = $domain->list_volumes_info();
    is($volumes[0]->info->{boot}, 1 );
}

sub test_add_cd_twice($vm) {

    my $domain = create_domain($vm);

    my $info0 = $domain->info(user_admin);
    my $n_disks0 = scalar(@{$info0->{hardware}->{disk}});
    my %targets0 = map { $_->{target} => 1 } @{$info0->{hardware}->{disk}};
    my ($file) = map { $_->{file} }
        grep { $_->{device} eq 'cdrom' }
        @{$info0->{hardware}->{disk}};

    my $req = Ravada::Request->add_hardware(
        id_domain => $domain->id
        ,name => 'disk'
        ,uid => user_admin->id
        ,'data' => {
            'device' => 'cdrom'
            ,'file' => $file
        }
    );
    ok($req);
    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    like($req->error,qr/already/i);

    Ravada::Request->refresh_machine(id_domain => $domain->id
        ,uid => user_admin->id
    );
    wait_request();

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info_f = $domain_f->info(user_admin);
    my $n_disks_f = scalar(@{$info_f->{hardware}->{disk}});
    is($n_disks_f, $n_disks0)
        or die Dumper($info_f->{hardware}->{disk});

    my $info = $domain->info(user_admin);
    my $n_disks = scalar(@{$info->{hardware}->{disk}});
    is($n_disks, $n_disks0) or die Dumper($info->{hardware}->{disk});

}

sub test_add_cd_kvm($vm) {
    test_add_cd($vm
        , { 'device' => 'cdrom',
            'driver' => 'ide'
        });
    test_add_cd($vm
        , { 'device' => 'cdrom'
            ,'driver' => 'ide'
            ,capacity => '1G'
        });
    test_add_cd($vm
        , { 'device' => 'cdrom'
            ,'driver' => 'ide'
            ,capacity => '1G'
            ,allocation => '1G'
        });
    test_add_cd($vm
        , { 'device' => 'cdrom'
            ,'driver' => 'ide'
            ,'file' => "/tmp/".new_domain_name()."a.iso"
        });
}

sub _list_id_isos($vm) {
    return search_id_iso('Alpine%64') if $vm->type eq 'Void';
    return search_id_iso('Alpine%64') if !$ENV{TEST_STRESS};
    my $list = rvd_front->list_iso_images();

    my ($alpine0) = grep { $_->{name} =~ /Alpine.*64/ } @$list;

    my $alpine = $vm->_search_iso($alpine0->{id});
    my $device = $alpine->{device} or die "Error: no device in "
    .Dumper($alpine);

    my $sth = connector->dbh->prepare(
        "UPDATE iso_images set device=? WHERE id=?"
    );
    my @list;
    for my $iso (@$list) {
        next if $iso->{device} && -e $iso->{device};
        next if $iso->{name} =~ /Empty/;
        next if $iso->{name} =~ /Android/i;

        $sth->execute($device, $iso->{id});
        push @list, ( $iso->{id} );
    }
    return @list;
}

sub combine_iso_options($vm, $iso_name) {

    return (undef) if $vm->type ne 'KVM';

    $Ravada::VM::KVM::VERIFY_ISO = 0;
    my $iso = $vm->_search_iso(search_id_iso($iso_name));
    my @options = (
        { machine => 'pc' }
        ,{ machine => search_latest_machine($vm, $iso->{arch},'pc-i440fx')}
    );
    my $machine = $iso->{options}->{machine};
    if ($machine) {
        my $found = 0;
        for my $option (@options) {
            $found++ if $option->{machine} eq $machine;
        }
        push @options,(
            {machine =>search_latest_machine($vm, $iso->{arch},$machine)})
        if !$found;
    }
    if ($iso->{options}->{bios} && $iso->{options}->{bios} eq 'UEFI') {
        my @options2;
        for my $option (@options) {
            my %option2 = %$option;
            $option2{uefi} = 1;
            push @options2, \%option2;
        }
        push @options,@options2;
    }
    return @options;
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

sub remove_mock_isos() {
    for my $file (@MOCK_ISOS) {
        next if $file !~ m{/tst_};
        unlink $file if -e $file;
    }
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


sub _search_iso_alpine($vm) {
    my $id_alpine = search_id_iso('Alpine%32');
    my $iso = $vm->_search_iso($id_alpine);
    return $iso->{device};
}
sub _machine_types($vm) {
    my $req = Ravada::Request->list_machine_types(
        vm_type => $vm->type
        ,uid => user_admin->id
    );
    wait_request($req);
    is($req->error,'');
    like($req->output,qr/./);

    my $machine_types = {};
    $machine_types = decode_json($req->output());

    return $machine_types;
}

sub test_cdrom($vm) {
    return if $vm->type ne 'KVM';

    my $device_iso = _search_iso_alpine($vm);
    my $machine_types = _machine_types($vm);

    my $isos = rvd_front->list_iso_images();
    for my $iso_frontend (@$isos) {
        next if !$iso_frontend->{arch};
        my $iso;
        eval { $iso = $vm->_search_iso($iso_frontend->{id}, $device_iso) };
        next if $@ && $@ =~ /No.*iso.*found/;
        die $@ if $@;
        $iso->{device} = $device_iso;

        my %done;
        for my $bios (undef, 'legacy','uefi') {
            die Dumper($iso) if !$iso->{arch} || !$machine_types->{$iso->{arch}};
            for my $machine ( @{$machine_types->{$iso->{arch}}}) {
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

        diag("Testing disks for $vm_name");

        test_add_cd_twice($vm);
        test_add_cd_kvm($vm) if $vm_name eq 'KVM';

        for my $id_iso ( _list_id_isos($vm) ) {
            for my $by_file ( 1, 0 ) {
                for my $by_index ( 0, 1 ) {
                    diag("Testing id_iso: $id_iso , by_file:$by_file, by_index:$by_index");
                    test_remove_disk($vm
                        ,clone => 1
                        ,id_iso => $id_iso
                        ,remove_by_file => $by_file
                        ,remove_by_index => $by_index
                    );
                    test_remove_disk($vm
                        ,add_iso_to_clone => 1
                        ,id_iso => $id_iso
                        ,remove_by_file => $by_file
                        ,remove_by_index => $by_index
                    );

                    test_remove_disk($vm, id_iso => $id_iso
                        ,remove_by_index => $by_index
                        ,remove_by_file => $by_file);
                    test_remove_disk($vm, make_base => 1, id_iso => $id_iso
                        ,remove_by_index => $by_index
                        ,remove_by_file => $by_file);
                }
            }
        }
        test_cdrom($vm);

        for my $iso_name ('Alpine%64 bits', 'Alpine%32 bits') {
            for my $options ( combine_iso_options($vm, $iso_name)) {
                test_add_disk_boot_order($vm, $iso_name, $options);
            }
        }


        test_frontend($vm);
        test_frontend_refresh($vm);

        test_add_disk($vm);
        test_add_disk($vm , 1); # swap file

	}
}

end();
done_testing();
