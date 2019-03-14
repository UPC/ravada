use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user("foo","bar", 1);

rvd_back();
$Ravada::CAN_FORK = 1;
my %CREATE_ARGS = (
     KVM => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
    ,LXC => { id_template => 1, id_owner => $USER->id }
    ,Void => { id_owner => $USER->id }
);

########################################################################
sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}

sub test_add_hardware_request {
	my $vm = shift;
	my $domain = shift;
	my $hardware = shift;

    $domain->shutdown_now(user_admin)   if $domain->is_active;
	
    my @list_hardware1 = $domain->get_controller($hardware);
	my $numero = scalar(@list_hardware1)+1;
    while ($hardware eq 'usb' && $numero > 4) {
        test_remove_hardware($vm, $domain, $hardware, 0);
        @list_hardware1 = $domain->get_controller($hardware);
	    $numero = scalar(@list_hardware1)+1;
    }
	my $req;
	eval {
		$req = Ravada::Request->add_hardware(uid => $USER->id
                , id_domain => $domain->id
                , name => $hardware
                , number => $numero
            );
	};
	is($@,'') or return;
    $USER->unread_messages();
	ok($req, 'Request');
	rvd_back->_process_all_requests_dont_fork();
    is($req->status(),'done');
    is($req->error(),'');

    {
    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my @list_hardware2 = $domain_f->get_controller($hardware);
    is(scalar @list_hardware2 , scalar(@list_hardware1) + 1
        ,"Adding hardware $numero\n"
            .Dumper(\@list_hardware2, \@list_hardware1));
    }

    {
        my $domain_2 = Ravada::Front::Domain->open($domain->id);
        my @list_hardware2 = $domain_2->get_controller($hardware);
        is(scalar @list_hardware2 , scalar(@list_hardware1) + 1
            ,"Adding hardware $numero\n"
                .Dumper(\@list_hardware2, \@list_hardware1));
    }
}

sub test_remove_hardware {
	my $vm = shift;
	my $domain = shift;
	my $hardware = shift;
	my $index = shift;

    $domain->shutdown_now(user_admin)   if $domain->is_active;
    $domain = Ravada::Domain->open($domain->id);
    my @list_hardware1 = $domain->get_controller($hardware);

	my $req;
	eval {
		$req = Ravada::Request->remove_hardware(uid => $USER->id
				, id_domain => $domain->id
				, name => $hardware
				, index => $index
			);
	};
	is($@, '') or return;
	ok($req, 'Request');
	rvd_back->_process_all_requests_dont_fork();
	is($req->status(), 'done');
	is($req->error(), '');

    {
        my $domain2 = Ravada::Domain->open($domain->id);
        my @list_hardware2 = $domain2->get_controller($hardware);
        is(scalar @list_hardware2 , scalar(@list_hardware1) - 1
        ,"Removing hardware $index ".$domain->name."\n"
            .Dumper(\@list_hardware2, \@list_hardware1)) or exit;
    }
    {
        my $domain_f = Ravada::Front::Domain->open($domain->id);
        my @list_hardware2 = $domain_f->get_controller($hardware);
        is(scalar @list_hardware2 , scalar(@list_hardware1) - 1
        ,"Removing hardware $index ".$domain->name."\n"
            .Dumper(\@list_hardware2, \@list_hardware1)) or exit;
    }
}

sub test_front_hardware {
    my ($vm, $domain, $hardware ) = @_;

    my $domain_f = Ravada::Front::Domain->open($domain->id);

        my @controllers = $domain_f->get_controller($hardware);
        ok(scalar @controllers,"[".$vm->type."] Expecting $hardware controllers ".$domain->name
            .Dumper(\@controllers))
                or exit;

        my $info = $domain_f->info(user_admin);
        ok(exists $info->{hardware},"Expecting \$info->{hardware}") or next;
        ok(exists $info->{hardware}->{$hardware},"Expecting \$info->{hardware}->{$hardware}");
        is_deeply($info->{hardware}->{$hardware},[@controllers]);
}

########################################################################


{
my $rvd_back = rvd_back();
ok($rvd_back,"Launch Ravada");# or exit;
}

ok($Ravada::CONNECTOR,"Expecting conector, got ".($Ravada::CONNECTOR or '<unde>'));

remove_old_domains();
remove_old_disks();

for my $vm_name ( qw(Void KVM)) {
    my $vm= rvd_back->search_vm($vm_name)  if rvd_back();
	if ( !$vm ) {
	    diag("Skipping VM $vm_name in this system");
	    next;
	}
	my $name = new_domain_name();
	
	my $domain_b = $vm->create_domain(
        name => $name
        ,active => 0
        ,disk => 1024 * 1024
        ,create_args($vm_name)
    );
    my %controllers = $domain_b->list_controllers;

    for my $hardware ( sort keys %controllers ) {
        diag("Testing $hardware controllers for VM $vm_name");
        test_front_hardware($vm, $domain_b, $hardware);
        test_add_hardware_request($vm, $domain_b, $hardware);
        test_remove_hardware($vm, $domain_b, $hardware, 0);
    }
}

remove_old_domains();
remove_old_disks();

done_testing();
