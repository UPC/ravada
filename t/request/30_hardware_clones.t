use warnings;
use strict;

use Test::More;

use Carp qw(carp confess cluck);
use Data::Dumper;

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

sub test_add_rm_hw($base) {
    my ($clone_d) = $base->clones;
    my $clone = Ravada::Domain->open($clone_d->{id});
    my %controllers = $base->list_controllers;

    for my $hardware (sort keys %controllers ) {
        next if $hardware eq 'display';
        next if $base->type eq 'KVM' && $hardware =~ /^(cpu|features)$/;

        test_add_hw($hardware, $base, $clone);
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

    test_add_rm_hw($base);
}

end();

done_testing();
