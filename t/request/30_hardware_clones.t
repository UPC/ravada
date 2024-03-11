use warnings;
use strict;

use Test::More;

use Carp qw(carp confess cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use Storable qw(dclone);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

################################################################

sub test_add_hw_all($hardware, $base, $clone) {
    my $before = $base->info(user_admin)->{hardware}->{$hardware};
    my $before_c = $clone->info(user_admin)->{hardware}->{$hardware};

    my $drivers = $base->info(user_admin)->{drivers}->{$hardware};

    for my $reverse ( 1,0 ) {
        my @drivers = sort @$drivers;
        @drivers = reverse(@drivers) if $reverse;

        for my $driver (@drivers) {
            my $req = Ravada::Request->add_hardware(
                name => $hardware
                ,uid => user_admin->id
                ,id_domain => $base->id
                ,data => { driver => $driver }
            );
            wait_request(debug => 0);
        }
        my $after = $base->info(user_admin)->{hardware}->{$hardware};
        my $after_c = $clone->info(user_admin)->{hardware}->{$hardware};
        is(scalar(@$after),scalar(@$before)+scalar(@drivers)) or die
        Dumper([[sort map {$_->{driver}} @$after],[sort @drivers]]);
        is(scalar(@$after_c),scalar(@$before_c)+scalar(@drivers)) or exit;

        test_clean_hw($hardware, $base, $clone);
    }

    my $req = Ravada::Request->add_hardware(
        name => $hardware
        ,uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request(debug => 0);

}

sub test_clean_hw($hardware, $base, $clone) {
    my $before = $base->info(user_admin)->{hardware}->{$hardware};
    for my $index ( 0 .. scalar(@$before)-1) {
        next if $before->[$index]->{is_secondary};
        my $req = Ravada::Request->remove_hardware(
            name => $hardware
            ,uid => user_admin->id
            ,id_domain => $base->id
            ,index => 0
        );
    }
    wait_request();
    my $after = $base->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$after),0) or exit;
    my $after_c = $clone->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$after_c),0) or exit;
}

sub test_add_hw($hardware, $base, $clone) {

    my $before = $base->info(user_admin)->{hardware}->{$hardware};
    my $before_c = $clone->info(user_admin)->{hardware}->{$hardware};

    my $data = _data($base->_vm, $hardware);
    my @args;
    push @args, ( data => $data ) if $data;

    my $req = Ravada::Request->add_hardware(
        name => $hardware
        ,uid => user_admin->id
        ,id_domain => $base->id
        ,@args
    );
    my $check_error = 1;
    $check_error=0 if $hardware eq 'disk';

    wait_request(debug => 0, check_error => $check_error);
    if ($hardware eq 'disk') {
        like($req->error, qr/new.*bases/);
    } else {
        is($req->error,'');
    }
    my $after = $base->info(user_admin)->{hardware}->{$hardware};
    my $after_c = $clone->info(user_admin)->{hardware}->{$hardware};

    my $add = 1;
    $add=0 if $hardware eq 'disk';

    is(scalar(@$after),scalar(@$before)+$add,Dumper([$after,$before]));
    is(scalar(@$after_c),scalar(@$before_c)+$add);

    my $clone2 = $base->clone(name => new_domain_name, user => user_admin);
    my $after_c2 = $clone2->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$after_c2),scalar(@$after_c));

    test_clone_req($base, $hardware, $after_c);

}

sub test_clone_req($base, $hardware,$base_hw0) {
    my $base_hw = dclone($base_hw0);
    my $name = new_domain_name();
    Ravada::Request->clone(
        id_domain => $base->id
        ,uid => user_admin->id
        ,remote_ip => '1.2.3.4'
        ,name => $name
    );
    wait_request();
    my ($clone_data) =grep { $_->{name} eq $name } $base->clones();
    my $clone = Ravada::Domain->open($clone_data->{id});

    my $clone_hw = $clone->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$clone_hw),scalar(@$base_hw));

    _clean_hw($hardware, $base_hw, $clone_hw);
    is_deeply($clone_hw, $base_hw,"Expecting hw $hardware identical");
};

sub _clean_hw($name, @hw) {
    for my $hw (@hw) {
        for my $item (@$hw) {
            next if !ref($item);
            unlock_hash(%$item);
            if ($name eq 'disk') {
                $item->{name} = '';
                $item->{file} = '';
            } elsif ($name eq 'filesystem') {
                $item->{_id} = '';
            } elsif ($name eq 'network') {
                delete $item->{hwaddr};
            }
            lock_hash(%$item);
        }
    }
}

sub _test_change_disk($base, $clone) {
    my $disks_base = $base->info(user_admin)->{hardware}->{disk};
    my $disks_clone = $clone->info(user_admin)->{hardware}->{disk};
    my $data_base = dclone($disks_base->[0]);
    my $data_clone = dclone($disks_clone->[0]);
    my $cache = 'none';
    $cache = 'unsafe' if $data_base->{driver}->{cache} eq 'none';
    $data_base->{driver}->{cache} = 'none';
    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'disk'
        ,id_domain => $base->id
        ,index => 0
        ,data => $data_base
    );
    wait_request();
    my $disks_base2 = $base->info(user_admin)->{hardware}->{disk};
    my $disks_clone2 = $clone->info(user_admin)->{hardware}->{disk};

    my $data_base2 = dclone($disks_base2->[0]);
    my $data_clone2 = dclone($disks_clone2->[0]);

    is_deeply($data_base2, $data_base);
    is($data_clone2->{file}, $data_clone->{file}) or exit;
}

sub _test_change_display($base, $clone) {

    _test_change_display_settings($base, $clone);
    _test_change_display_driver($base, $clone);
}

sub _test_change_display_settings($base, $clone) {

    my $display = $base->info(user_admin)->{hardware}->{display}->[0];
    my ($key) = sort keys %{$display->{extra}};
    delete $display->{extra}->{$key};

    my $req = Ravada::Request->change_hardware(
            uid => user_admin->id
            ,hardware => 'display'
            ,id_domain => $base->id
            ,index => 0
            ,data => $display
    );

    wait_request(debug => 0);
    wait_request(debug => 0);
}

sub _test_change_display_driver($base, $clone) {
    for my $driver ('vnc','spice') {
        my $req = Ravada::Request->change_hardware(
            uid => user_admin->id
            ,hardware => 'display'
            ,id_domain => $base->id
            ,index => 0
            ,data => {driver => $driver }
        );
        wait_request();
        my $hw = $base->info(user_admin)->{hardware}->{display};
        is($hw->[0]->{driver},$driver);

        $clone = Ravada::Domain->open($clone->id);

        my $hwc = $clone->info(user_admin)->{hardware}->{display};
        is($hwc->[0]->{driver},$driver);

        my $name = new_domain_name();
        Ravada::Request->clone(
            id_domain => $base->id
            ,uid => user_admin->id
            ,remote_ip => '1.2.3.4'
            ,name => $name
        );
        wait_request();
        my ($clone_data) =grep { $_->{name} eq $name } $base->clones();
        my $clone2 = Ravada::Domain->open($clone_data->{id});

        my $hwc2 = $clone2->info(user_admin)->{hardware}->{display};
        is($hwc2->[0]->{driver},$driver) or die Dumper([$base->name, $clone2->name, $name]);

        Ravada::Request->start_domain(
            id_domain => $clone2->id
            ,remote_ip => '192.2.3.4'
            ,uid => user_admin->id
        );
        my $clone3 = Ravada::Domain->open($clone_data->{id});

        my $hwc3 = $clone3->info(user_admin)->{hardware}->{display};
        is($hwc3->[0]->{driver},$driver);

    }
}

sub test_change_hw($hardware, $base, $clone) {
    my %tests = (
        'disk.KVM' => \&_test_change_disk
        ,'display.KVM' => \&_test_change_display
    );
    my $cmd = $tests{$hardware.".".$base->type};
    return if !$cmd;

    $cmd->($base,$clone);
}

sub test_add_rm_change_hw($base) {
    my ($clone_d) = $base->clones;
    my $clone = Ravada::Domain->open($clone_d->{id});
    my %controllers = $base->list_controllers;

    for my $hardware (sort keys %controllers ) {
        next if $hardware eq 'memory';
        next if $base->type eq 'KVM' && $hardware =~ /^(cpu|features)$/;

        if ( $hardware ne 'display' ) {
            test_add_hw($hardware, $base, $clone);
        } else {
            test_clean_hw($hardware, $base, $clone);
            test_add_hw_all($hardware, $base, $clone);
        }
        test_change_hw($hardware, $base, $clone);
        test_rm_hw($hardware, $base, $clone);
    }
}

sub _data($vm, $hardware) {
    my $data;
    if ( $hardware eq 'filesystem' ) {
        my $dir = "/var/tmp/".new_domain_name();
        mkdir $dir if ! -e $dir;
        $data = { source => { dir => $dir } }
    }
    return $data;
}

sub test_rm_hw($hardware, $base, $clone) {

    my $prev_files_base = scalar($base->list_files_base);
    my $before = $base->info(user_admin)->{hardware}->{$hardware};
    my $before_c = $clone->info(user_admin)->{hardware}->{$hardware};

    my $req = Ravada::Request->remove_hardware(
        name => $hardware
        ,uid => user_admin->id
        ,id_domain => $base->id
        ,index => scalar(@$before_c)-1
    );

    my $check_error = 1;
    $check_error=0 if $hardware eq 'disk';
    wait_request(debug => 0, check_error => $check_error);
    die $req->error if $hardware eq 'display' && $req->error;

    if ($hardware eq 'disk') {
        like($req->error, qr/Error.*base/);
    } else {
        is($req->error,'');
    }

    my $add = 1;
    $add=0 if $hardware eq 'disk';

    my $after = $base->info(user_admin)->{hardware}->{$hardware};
    my $after_c = $clone->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$after),scalar(@$before)-$add) or exit;
    is(scalar(@$after_c),scalar(@$before_c)-$add) or die $clone->name;

    is(scalar($base->list_files_base), $prev_files_base) or exit;

    my $clone2 = $base->clone(name => new_domain_name, user => user_admin);
    my $after_c2 = $clone2->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$after_c2),scalar(@$after_c)) or exit;

}

################################################################

clean();

for my $vm_name (vm_names()) {
    my $vm;
    $vm = rvd_back->search_vm($vm_name)  if rvd_back();
	if ( !$vm || ($vm_name eq 'KVM' && $>)) {
	    diag("Skipping VM $vm_name in this system");
	    next;
	}
    my $base = create_domain_v2(vm => $vm, swap => 1, data => 1);
    Ravada::Request->clone(
        uid => user_admin->id
        ,id_domain => $base->id
        ,name => new_domain_name()
    );
    wait_request();

    test_add_rm_change_hw($base);
}

end();

done_testing();
