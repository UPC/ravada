use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $CONFIG_FILE = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($test->connector , $CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new(
    config => $CONFIG_FILE
    , connector => $test->connector
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
    );
    
    ok($domain_b);

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);

    return $name;
}

sub test_vm_controllers_fe {
	my $vm_name = shift;
	my $name = shift;
	my $domain_f = $RVD_FRONT->search_domain($name);
	isa_ok($domain_f, "Ravada::Front::Domain::$vm_name");
	
	my @usbs = $domain_f->get_controller('usb');
	ok(scalar @usbs > 0, "Got USB: @usbs");
	
	#my $nusb = $domain_f->set_controller('usb' , 'spicevmc');
	#ok($nusb, "Added usb: $nusb");
	
	#eval {$domain_f->remove_controller('usb')};
	#ok(!$@, $@);
}

##############################################################3

remove_old_domains();
remove_old_disks();

for my $vm_name (qw(KVM)) {
    my $vm = $RVD_BACK->search_vm($vm_name);
    if ( !$vm ) {
        diag("Skipping VM $vm_name in this system");
        next;
    }
    my $dom_name = test_create_domain($vm_name);
    test_vm_controllers_fe($vm_name, $dom_name);
}

remove_old_domains();
remove_old_disks();

done_testing();
