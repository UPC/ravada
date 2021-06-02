use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Mojo::JSON qw(decode_json);
use Ravada::Request;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada::HostDevice::Templates');

####################################################################

sub test_templates($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    ok(@$templates);

    my $templates2 = Ravada::HostDevice::Templates::list_templates($vm->id);
    is_deeply($templates2,$templates);

    my $n=scalar($vm->list_host_devices);

    for my $first  (@$templates) {

        $vm->add_host_device(template => $first->{name});

        my @list_hostdev = $vm->list_host_devices();
        is(scalar @list_hostdev, $n+1, Dumper(\@list_hostdev)) or exit;

        $vm->add_host_device(template => $first->{name});
        @list_hostdev = $vm->list_host_devices();
        is(scalar @list_hostdev, $n+2);
        like ($list_hostdev[-1]->{name} , qr/[a-zA-Z] \d+$/) or exit;

        my $req = Ravada::Request->list_host_devices(
            uid => user_admin->id
            ,id_host_device => $list_hostdev[-1]->id
        );
        wait_request();
        is($req->status, 'done');
        is($req->error, '');
        like($req->output,qr'.');
        $n++;

        next if $req->output eq '[]';

        $list_hostdev[-1]->_data('list_filter' => '002');
        my $req2 = Ravada::Request->list_host_devices(
            uid => user_admin->id
            ,id_host_device => $list_hostdev[-1]->id
        );
        wait_request();
        is($req2->status, 'done');
        is($req2->error, '');
        like($req2->output,qr'.');
        isnt($req2->output, $req->output);
        $n++;
    }

}

####################################################################

clean();

for my $vm_name ( reverse vm_names()) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        test_templates($vm);

    }
}

end();
done_testing();

