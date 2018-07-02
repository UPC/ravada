use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, 't/etc/ravada.conf');

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
	my $numero = shift;
	
	my $req;
	eval {
		$req = Ravada::Request->add_hardware(uid => $USER->id
                , id_domain => $domain->id
                , name => $hardware
                , number => $numero
            );
	};
	is($@,'') or return;
	ok($req, 'Request');
	rvd_back->_process_all_requests_dont_fork();
    is($req->status(),'done');
    is($req->error(),'');
}

sub test_remove_hardware {
	my $vm = shift;
	my $domain = shift;
	my $hardware = shift;
	my $index = shift;
	
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
}

sub test_front_hardware {
    my ($vm, $domain) = @_;

    my $domain_f = Ravada::Front::Domain->open($domain->id);

    for my $hardware ( qw(usb)) {
        my @controllers = $domain_f->get_controller($hardware);
        ok(scalar @controllers);

        my $info = $domain_f->info(user_admin);
        ok(exists $info->{hardware},"Expecting \$info->{hardware}") or next;
        ok(exists $info->{hardware}->{$hardware},"Expecting \$info->{hardware}->{$hardware}");
        is_deeply($info->{hardware}->{$hardware},[@controllers]);
    }
}

########################################################################


{
my $rvd_back = rvd_back();
ok($rvd_back,"Launch Ravada");# or exit;
}

ok($Ravada::CONNECTOR,"Expecting conector, got ".($Ravada::CONNECTOR or '<unde>'));

remove_old_domains();
remove_old_disks();

for my $vm_name ( qw(KVM)) {
    my $vm= rvd_back->search_vm($vm_name)  if rvd_back();
	if ( !$vm ) {
	    diag("Skipping VM $vm_name in this system");
	    next;
	}
	my $name = new_domain_name();
	
	my $domain_b = $vm->create_domain(
        name => $name
        ,active => 0
        ,create_args($vm_name)
    );
    test_front_hardware($vm, $domain_b);
	test_add_hardware_request($vm, $domain_b, 'hardware_usb', 2);
	test_remove_hardware($vm, $domain_b, 'usb', 0);
}

remove_old_domains();
remove_old_disks();

done_testing();
