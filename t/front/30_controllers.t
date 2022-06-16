use warnings;
use strict;

use Data::Dumper;
use Test::More;

use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

use feature qw(signatures);
no warnings "experimental::signatures";

use_ok('Ravada::Front');

my $CONFIG_FILE = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new(
    config => $CONFIG_FILE
    , connector => connector()
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar', 1);

my %CREATE_ARGS = (
     KVM => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
    ,LXC => { id_template => 1, id_owner => $USER->id }
    ,Void => { id_owner => $USER->id }
);

our $XML = XML::LibXML->new();

###################################################################

sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}

sub test_create_domain {
    my $vm_name = shift;

    my $name = new_domain_name();

    my $vm = $RVD_BACK->search_vm($vm_name);
    ok($vm,"Expecting VM $vm , got '".ref($vm)) or return;
    
    my $domain_b = $vm->create_domain(
        name => $name
        ,active => 0
        ,create_args($vm_name)
	,disk => 1024 * 1024
    );
    
    ok($domain_b);

    _add_hardware($domain_b);

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);

    return $name;
}

sub _add_hardware($domain) {
    return unless $domain->type eq 'KVM';

    my $dir = "/var/tmp/".new_domain_name();
    mkdir $dir or die $! unless -e $dir;

    my $req = Ravada::Request->add_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => {
            source => { dir => $dir }
        }
    );
    wait_request( debug => 0);
}

sub test_vm_controllers_fe {
	my $vm_name = shift;
	my $dom_name = shift;
	my $domain_f = $RVD_FRONT->search_domain($dom_name);
	isa_ok($domain_f, "Ravada::Front::Domain::$vm_name");
	
    my %ctrl = $domain_f->list_controllers;
    for my $name (keys %ctrl) {
        my @devs = $domain_f->get_controller($name);
        ok(scalar @devs > 0, "Expecting more than 0 $name devices, got ".scalar(@devs)) or die $name;
    }
	
	#my $nusb = $domain_f->set_controller('usb' , 'spicevmc');
	#ok($nusb, "Added usb: $nusb");
	
	#eval {$domain_f->remove_controller('usb')};
	#ok(!$@, $@);
}

##############################################################3

remove_old_domains();
remove_old_disks();

for my $vm_name ( vm_names() ) {
    my $vm = $RVD_BACK->search_vm($vm_name);
    if ( !$vm || ( $vm_name eq 'KVM' && $< ) ) {
        diag("Skipping VM $vm_name in this system");
        next;
    }
    my $dom_name = test_create_domain($vm_name);
    test_vm_controllers_fe($vm_name, $dom_name);
}

end();
done_testing();
