use warnings;
use strict;

use utf8;
use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $N_IP = 2;
###############################################################################

sub _create_remote_node($vm_name) {
    my %config = (
            name => new_domain_name()
            ,host => '192.168.18.'.$N_IP++
    );

    my $vm = rvd_back->search_vm($vm_name);

    my  $node = $vm->new(%config);
    return $node;
}

sub test_req_migrate($vm, $node1, $node2) {
    my $domain = create_domain($vm);
    $domain->_data('id_vm' => $node1->id);
    my $req = Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_node => $node2->id
    );
    ok($req->after_request_ok());
    my $id_req_prev = $req->after_request_ok();
    ok($id_req_prev);
    _mock_fail($id_req_prev);

    wait_request(debug => 1, check_error => 0);
    is($req->status(),'done');
    is($req->error,'failure');

    $domain->_remove_domain_data_db();
}

sub test_req_prepare_base($vm, $node1, $node2) {
    my $domain = create_domain($vm);
    $domain->_data('id_vm' => $node1->id);
    my $req = Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node2->id
    );
    my $id_req_prev = $req->after_request_ok();
    ok($id_req_prev) or exit;

    _mock_fail($id_req_prev);

    wait_request(debug => 1, check_error => 0);
    is($req->status(),'done');
    is($req->error,'failure');
    $domain->_remove_domain_data_db();
}

sub _mock_fail($id_req) {
    my $sth = connector->dbh->prepare(
        "UPDATE requests set status='done',error='failure' "
        ." WHERE id = ?"
    );
    $sth->execute($id_req);
}


###############################################################################

init();
for my $vm_name (vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        my $REMOTE_CONFIG = remote_config($vm_name);
        if (!keys %$REMOTE_CONFIG) {
            my $msg = "skipped, missing the remote configuration for $vm_name in the file "
                .$Test::Ravada::FILE_CONFIG_REMOTE;
            diag($msg);
            skip($msg,10);
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");

        my $node1 = _create_remote_node($vm_name);
        my $node2 = _create_remote_node($vm_name);

        test_req_migrate($vm, $node1, $node2);
        test_req_prepare_base($vm, $node1, $node2);
    }
}

END: {
    end();
    done_testing();
}


