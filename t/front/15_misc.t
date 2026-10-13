use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use feature qw(signatures);
no warnings "experimental::signatures";

my $RVD_BACK;
my $RVD_FRONT;

sub _init() {
    $RVD_BACK  = rvd_back( );
    $RVD_FRONT = rvd_front();

    ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");
    ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");

    ok($RVD_BACK->connector());
}

####################################################################################

sub test_machine_types($vm_name) {
    my $req = Ravada::Request->list_machine_types(
        vm_type => $vm_name
        ,uid => user_admin->id
    );
    wait_request(debug => 0);

    isa_ok($req->output,'HASH');

    my $types = $RVD_FRONT->list_machine_types(user_admin->id, $vm_name);

    ok(ref($types));
    isa_ok($types,'HASH')
}

sub test_list_isos($vm_name) {
    my $vm = Ravada::VM->_open_type(type => $vm_name);

    my $req = Ravada::Request->list_isos(
        uid => user_admin->id
        ,id_vm => $vm->id
    );
    wait_request();
    isa_ok($req->output,'ARRAY');

    my $iso = $RVD_FRONT->iso_file(user_admin->id, $vm_name);
    isa_ok($iso,'ARRAY');
}
####################################################################################

init();
clean();

SKIP: {
    _init();
    for my $vm_name ( vm_names() ) {
        test_machine_types($vm_name);
        test_list_isos($vm_name);
    }
}

end();
done_testing();
