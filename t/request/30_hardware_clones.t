use warnings;
use strict;

use Test::More;

use Carp qw(carp confess cluck);
use Data::Dumper;
use Hash::Util qw(unlock_hash);
use Storable qw(dclone);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

################################################################

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

    is(scalar(@$after),scalar(@$before)+$add);
    is(scalar(@$after_c),scalar(@$before_c)+$add);

    my $clone2 = $base->clone(name => new_domain_name, user => user_admin);
    my $after_c2 = $clone2->info(user_admin)->{hardware}->{$hardware};
    is(scalar(@$after_c2),scalar(@$after_c));

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

sub test_change_hw($hardware, $base, $clone) {
    my %tests = (
        'disk.KVM' => \&_test_change_disk
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
        next if $hardware eq 'display' || $hardware eq 'memory';
        next if $base->type eq 'KVM' && $hardware =~ /^(cpu|features)$/;

        test_add_hw($hardware, $base, $clone);
        test_change_hw($hardware, $base, $clone);
        test_rm_hw($hardware, $base, $clone);
    }
}

sub test_ports($base) {
    test_add_ports($base);
    test_change_ports($base);
    test_remove_ports($base);
}

sub test_add_ports($base) {
    my ($clone_d) = $base->clones;
    my $clone = Ravada::Domain->open($clone_d->{id});

    for my $n ( 1 .. 2 ) {
        Ravada::Request->expose(
            uid => user_admin->id
            ,id_domain => $base->id
            ,restricted => 1
            ,port => 22+$n
            ,name => 'ssh'.$n
        );
        wait_request();

        my @ports_base = $base->list_ports();
        my @ports_clone = $clone->list_ports();

        _check_ports_equal(\@ports_base, \@ports_clone);
    }
}

sub test_change_ports($base) {
    my ($clone_d) = $base->clones;
    my $clone = Ravada::Domain->open($clone_d->{id});

    my @ports_base0 = $base->list_ports();
    my @ports_clone0 = $clone->list_ports();
    my $new_restricted = $ports_base0[0]->{restricted};
    if ($new_restricted) {
        $new_restricted = 0;
    } else {
        $new_restricted = 1;
    }

    Ravada::Request->expose(
        uid => user_admin->id
        ,id_domain => $base->id
        ,id_port => $ports_base0[0]->{id}
        ,port => $ports_base0[0]->{internal_port}
        ,name=> $ports_base0[0]->{name}
        ,restricted => $new_restricted
    );
    wait_request();
    my @ports_base = $base->list_ports();
    my @ports_clone = $clone->list_ports();
    is($ports_base[0]->{restricted},$new_restricted);

    _check_ports_equal(\@ports_base, \@ports_clone);


}

sub test_remove_ports($base) {
    my ($clone_d) = $base->clones;
    my $clone = Ravada::Domain->open($clone_d->{id});

    my @ports_base0 = $base->list_ports();
    my @ports_clone0 = $clone->list_ports();

    Ravada::Request->remove_expose(
        uid => user_admin->id
        ,id_domain => $base->id
        ,port => $ports_base0[0]->{internal_port}
    );
    wait_request();

    my @ports_base = $base->list_ports();
    is(scalar(@ports_base),scalar(@ports_base0)-1);
    my @ports_clone = $clone->list_ports();
    is(scalar(@ports_clone),scalar(@ports_clone0)-1);

    _check_ports_equal(\@ports_base, \@ports_clone);
}

sub _check_ports_equal($ports_base, $ports_clone) {
    for (@$ports_base, @$ports_clone) {
        unlock_hash(%$_);
        delete $_->{public_port};
        delete $_->{id};
        delete $_->{id_domain};
    }

    is_deeply($ports_clone, $ports_base);
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
    $base->_refresh_db();

    test_ports($base);
    test_add_rm_change_hw($base);
}

end();

done_testing();
