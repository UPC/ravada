use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Mojo::JSON qw( encode_json decode_json );
use YAML qw(Load Dump  LoadFile DumpFile);

use Ravada::HostDevice::Templates;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE;
my $MOCK_MDEV;
my $N_TIMERS;

####################################################################

sub test_shutdown_inactive($vm) {
    my $name = new_domain_name();
    my $clone = $BASE->clone( name => $name, user => user_admin);

    my $hd = create_host_devices($vm);
    $clone->add_host_device($hd);

    $clone->_data('shutdown_inactive_gpu' => 2);
    $clone->_data('shutdown_grace_time' => 2);
    $clone->start(user => user_admin, remote_ip => '1.2.3.4');

    my $req_shutdown;
    for my $n (0 .. 5 ) {
        sleep 1 if $n;
        my $req2=Ravada::Request->enforce_limits( _force => 1);
        wait_request(request => $req2, skip => [],debug => 1);
        is($req2->error,'');
        ($req_shutdown) = grep { $_->command =~ /shutdown/ } $clone->list_requests(1);

        last if (!$clone->is_active || $req_shutdown);
        _mock_inactive($clone);
        my $sth = connector->dbh->prepare(
            "DELETE FROM requests where command='enforce_limits'"
        );
        $sth->execute;
    }
    ok(!$clone->is_active || $req_shutdown) or exit;

}

sub _mock_inactive($domain, $minutes=2) {
    my $json_status = $domain->_data('log_status');
    my $h_status = {};
    if ($json_status) {
        eval { $h_status = decode_json($json_status) };
        $h_status = {} if $@;
    }
    push @{$h_status->{'inactive'}},(time()-$minutes*60);

    $domain->_data('log_status', encode_json($h_status));

}


####################################################################

clean();

for my $vm_name ('KVM', 'Void' ) {
    my $vm;
    eval {
        $vm = rvd_back->search_vm($vm_name)
        unless $vm_name eq 'KVM' && $<;
    };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        if ($vm_name eq 'Void') {
            $BASE = create_domain($vm);
        } else {
            $BASE = import_domain($vm);
        }

        test_shutdown_inactive($vm);
    }
}

end();
done_testing();
