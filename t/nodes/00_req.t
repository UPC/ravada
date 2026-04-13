use warnings;
use strict;

use utf8;
use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Mojo::JSON qw(decode_json);
use Storable qw(dclone);
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

    wait_request(debug => 0, check_error => 0);
    is($req->status(),'done');
    is($req->error,'failure');

    remove_domain_db($domain);
}

sub test_req_migrate_active($vm, $node1, $node2) {
    my $domain = create_domain($vm);
    $domain->_data('id_vm' => $node1->id);
    $domain->_data('status' => 'active');
    my $req = Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_node => $node2->id
        ,shutdown => 1
    );
    ok($req->after_request_ok());
    my $id_req_prev = $req->after_request_ok();
    $id_req_prev = [$id_req_prev] if !ref($id_req_prev);
    ok($id_req_prev) or return;

    my ($req_prev_migrate,$req_prev_shutdown);
    for my $id ( @$id_req_prev ) {
        my $req_prev = Ravada::Request->open($id);
        $req_prev_migrate = $req_prev if $req_prev->command eq 'migrate';
        $req_prev_shutdown = $req_prev if $req_prev->command eq 'shutdown';
    }
    ok($req_prev_migrate) or exit;
    ok($req_prev_shutdown) or exit;

    my $new_ids = dclone($id_req_prev);
    $req->_data('after_request_ok' => 99);
    delete $req->{_data};

    push @$new_ids,(99);
    is_deeply($req->after_request_ok(), $new_ids)
        or die Dumper([$req->after_request_ok(), $new_ids]);

    $req->_data('after_request' => '');
    for ( 100 .. 103 ) {
        $req->_data('after_request' => $_ );
    }
    is_deeply($req->after_request(), ["100","101","102","103"]);
    $req->_data('after_request' => '');
    $req->_data('after_request_ok' => '');

    remove_domain_db($domain);
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
    ok($id_req_prev) or die Dumper([$domain->id, $req->id]);

    _mock_fail($id_req_prev);

    wait_request(debug => 0, check_error => 0);
    is($req->status(),'done');
    is($req->error,'failure');
    remove_domain_db($domain);
}

sub _mock_fail($id_req) {
    my $sth = connector->dbh->prepare(
        "UPDATE requests set status='done',error='failure' "
        ." WHERE id = ?"
    );
    $sth->execute($id_req);
}

sub test_req_migrate_nested($vm, $node1) {
    my $base1 = create_base($vm);
    $base1->_data('is_base' => 1);

    my $base2 = create_base($vm);
    $base2->_data('is_base' => 1);
    $base2->_data('id_base' => $base1->id);

    my $base3 = create_base($vm);
    $base2->_data('is_base' => 1);
    $base3->_data('id_base' => $base2->id);

    my $clone = create_domain($vm);
    $clone->_data('id_base' => $base3->id);

    my $req = Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $clone->id
        ,id_node => $node1->id
    );
    my $id_req_prev = $req->after_request_ok();
    ok($id_req_prev) or return;
    my $req_prev = Ravada::Request->open($id_req_prev);
    is($req_prev->id_domain, $clone->id_base);
    is($req_prev->id_domain, $base3->id);
    is($req_prev->command(), 'set_base_vm');

    $id_req_prev = $req_prev->after_request_ok();
    ok($id_req_prev) or return;
    isnt($id_req_prev, $req_prev->id) or exit;
    $req_prev = Ravada::Request->open($id_req_prev);
    is($req_prev->id_domain, $base2->id);
    is($req_prev->id_domain, $base3->id_base);
    is($req_prev->command(), 'set_base_vm');

    $id_req_prev = $req_prev->after_request_ok();
    ok($id_req_prev) or return;
    isnt($id_req_prev, $req_prev->id) or exit;
    $req_prev = Ravada::Request->open($id_req_prev);
    is($req_prev->id_domain, $base1->id);
    is($req_prev->id_domain, $base2->id_base);
    is($req_prev->command(), 'set_base_vm');

    $id_req_prev = $req_prev->after_request_ok();
    ok(!$id_req_prev);
    remove_domain_db($clone);
}

sub test_req_prepare_nested($vm, $node1) {
    my $base1 = create_base($vm);
    $base1->_data('is_base' => 1);

    my $base2 = create_base($vm);
    $base2->_data('is_base' => 1);
    $base2->_data('id_base' => $base1->id);

    my $base3 = create_base($vm);
    $base2->_data('is_base' => 1);
    $base3->_data('id_base' => $base2->id);

    my $clone = create_domain($vm);
    $clone->_data('id_base' => $base3->id);

    my $req = Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $clone->id
        ,id_vm => $node1->id
    );
    my $id_req_prev = $req->after_request_ok();
    ok($id_req_prev) or return;

    #First prepare clone on node vm local
    my $req_prev = Ravada::Request->open($id_req_prev->[0]);
    is($req_prev->id_domain, $clone->id) or exit;
    is($req_prev->args('id_vm'), $vm->id);
    is($req_prev->command(), 'set_base_vm');

    #Then prepare base on node 
    $req_prev = Ravada::Request->open($id_req_prev->[1]);
    is($req_prev->id_domain, $base3->id) or exit;
    is($req_prev->args('id_vm'), $node1->id);
    is($req_prev->command(), 'set_base_vm');

    # Chain prepare base requirements
    $id_req_prev = $req_prev->after_request_ok();
    ok($id_req_prev) or die;
    isnt($id_req_prev, $req_prev->id) or exit;
    $req_prev = Ravada::Request->open($id_req_prev);
    is($req_prev->id_domain, $base2->id);
    is($req_prev->id_domain, $base3->id_base);
    is($req_prev->command(), 'set_base_vm');

    $id_req_prev = $req_prev->after_request_ok();
    ok($id_req_prev) or return;
    isnt($id_req_prev, $req_prev->id) or exit;
    $req_prev = Ravada::Request->open($id_req_prev);
    is($req_prev->id_domain, $base1->id);
    is($req_prev->id_domain, $base2->id_base);
    is($req_prev->command(), 'set_base_vm');

    $id_req_prev = $req_prev->after_request_ok();
    ok(!$id_req_prev);

    for my $base ( $base1, $base2, $base3, $clone) {
        $base->_set_base_vm_db( $node1->id,1);
        for ( 1 .. 2 ) {
            my $clone2 = create_domain($vm);
            $clone2->_data('id_base' => $base->id);
            $clone2->_data('id_vm' => $node1->id);
        }
    }
    test_req_remove_base_nested($vm, $node1, $clone, $base3, $base2, $base1);
    remove_domain_db($base1);
}

sub test_req_remove_base_nested($vm, $node1, $clone, $base3, $base2, $base1) {
    my $req = Ravada::Request->remove_base_vm(
        uid => user_admin->id
        ,id_domain => $base1->id
        ,id_vm => $node1->id
    );
    test_remove_requirements($base1, $req);
}

sub test_remove_requirements($base, $req) {
    diag("testing remove requirements for ".$base->id." ".$base->name);
    my @clones = $base->clones;
    return if !@clones;

    my $id_req_prev = $req->after_request_ok();
    ok($id_req_prev) or die "Expecting requirements for "
        .$req->id." ".$req->command." ".Dumper($req->args);
    $id_req_prev=[$id_req_prev] if !ref($id_req_prev);
    for my $clone ( @clones ) {
        my $req_prev;
        for my $id (@$id_req_prev) {
            $req_prev = Ravada::Request->open($id);
            last if $req_prev->id_domain == $clone->{id};
        }
        ok($req_prev, "Expecting req for clone $clone->{id}") or die ;
        if ($clone->{is_base}) {
            my $base2 = Ravada::Front::Domain->open($clone->{id});
            test_remove_requirements($base2, $req_prev);
        }
    }
}


###############################################################################

init();
clean();
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

        isnt($vm->name,'Void_localhost');
        my $node1 = _create_remote_node($vm_name);
        my $node2 = _create_remote_node($vm_name);

        test_req_prepare_nested($vm, $node1);
        test_req_migrate_nested($vm, $node1);
        test_req_prepare_base($vm, $node1, $node2);
        test_req_migrate_active($vm, $node1, $node2);
        test_req_migrate($vm, $node1, $node2);
        $node1->remove();
        $node2->remove();
    }
}

END: {
    end();
    done_testing();
}


