use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

##################################################################################
sub test_remote_standalone( @nodes ) {
    for my $node0 (@nodes) {
        my $domain = create_domain($node0);
        for my $node1 (@nodes) {
            diag("Migrate from ".$domain->_vm->name." to ".$node1->name);
            my $req = Ravada::Request->migrate(
                uid => user_admin->id
                ,id_domain => $domain->id
                ,id_node => $node1->id
                ,shutdown => 1
                ,start => 1
            );
            wait_request( debug => 1);
            my $domain_f = Ravada::Front::Domain->open($domain->id);
            is($domain_f->_data('id_vm'),$node1->id);
        }
        remove_domain($domain);
    }
}


sub test_remove_n($vm, @nodes ) {
    my $domain = create_domain($vm);

    $domain->prepare_base(user_admin);

    my $n=1;
    $n++ if !$domain->_vm->is_local;
    for my $node ( @nodes ) {
        Ravada::Request->set_base_vm(
            id_vm=> $node->id
            ,uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request();
        is($domain->list_instances, ++$n)
            or die Dumper([$domain->list_instances]);
    }

    for my $node1 ( @nodes ) {
        my $clone = $domain->clone(user => user_admin, name => new_domain_name);
        diag("Migrate clone ".$clone->name." from ".$clone->_vm->name
                ." to ".$node1->name);
        my $req = Ravada::Request->migrate(
            uid => user_admin->id
            ,id_domain => $clone->id
            ,id_node => $node1->id
            ,shutdown => 1
            ,start => 1
        );
        wait_request();
        for my $node2 ( @nodes ) {
            next if $node2->id == $node1->id;
            diag("Migrating ".$clone->name." from ".$node1->name." to ".$node2->name);
            my $req = Ravada::Request->migrate(
                uid => user_admin->id
                ,id_domain => $clone->id
                ,id_node => $node2->id
                ,shutdown => 1
                ,start => 1
            );
            wait_request( debug => 0);
            is($req->status,'done');
            is($req->error,'');
            my $clone2 = Ravada::Domain->open($clone->id);
            is($clone2->_vm->id, $node2->id);
            is($clone2->is_active,1,"Expecting ".$clone2->name." [ ".$clone2->id." ] active")
                or exit;
            delete_request('enforce_limits','set_time', 'refresh_machine');
        }
        $clone->remove(user_admin);
    }
    $domain->remove(user_admin);

}

sub test_remove($vm, $node1, $node2) {
    my $domain = create_domain($vm);

    is($domain->list_instances,1);
    $domain->prepare_base(user_admin);
    is($domain->list_instances,1);
    $domain->set_base_vm(vm => $node1, user => user_admin);
    is($domain->list_instances,2);
    $domain->set_base_vm(vm => $node2, user => user_admin);
    is($domain->list_instances,3);

    my $clone1 = $domain->clone( user => user_admin
        , name => new_domain_name
    );
    is($clone1->list_instances,1);

    my $n_exp_instances=2;
    if ($clone1->_vm->id == $node1->id ) {
        # does nothing
        $n_exp_instances=1;
    } elsif ( !$clone1->_vm->is_local && !$node1->is_local ) {
        # does a pass via local
        $n_exp_instances=3;
    }
    Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $clone1->id
        ,id_node => $node1->id
    );
    wait_request();

    is($clone1->list_instances,$n_exp_instances);

    my $clone2 = $domain->clone( user => user_admin
        , name => new_domain_name
    );
    Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $clone2->id
        ,id_node => $node1->id
    );
    wait_request();
    Ravada::Request->migrate(
        uid => user_admin->id
        ,id_domain => $clone2->id
        ,id_node => $node2->id
    );
    wait_request();

    is($clone2->list_instances,3);

    my @name = ( $clone1->name, $clone2->name, $domain->name);
    my @id = ( $clone1->id, $clone2->id, $domain->id);

    $clone1->remove(user_admin);
    $clone2->remove(user_admin);
    is($clone2->list_instances,undef);
    $domain->remove(user_admin);

    for my $name (@name) {
        my $sth = connector->dbh->prepare("SELECT * from domains WHERE name=?");
        $sth->execute($name);
        my @row = $sth->fetchrow;

        is($row[0],undef);
    }

    for my $id (@id) {
        my $sth = connector->dbh->prepare("SELECT * from domains WHERE id=?");
        $sth->execute($id);
        my @row = $sth->fetchrow;

        is($row[0],undef);
    }

    for my $table ( qw(file_base_images iptables domains_kvm domains_void bases_vm 
                    access_ldap_attribute volumes ) ) {
        for my $id (@id) {
            my $sth = connector->dbh->prepare("SELECT * from $table WHERE id_domain=?");
            $sth->execute($id);
            my @row = $sth->fetchrow;

            is($row[0],undef, "Expecting no id_domain: $id in $table ".Dumper(\@row));
        }
    }
}

sub _req_create($vm, $start=0) {
    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_vm => $vm->id
        ,id_owner => user_admin->id
        ,id_iso => search_id_iso('Alpine%64')
        ,disk => 10240
        ,swap => 10240
        ,data => 10240
        ,start => $start
    );
    wait_request();
    is($req->error,'');
    my $base = rvd_back->search_domain($name);
    ok($base) or return;
    is($base->_vm->id, $vm->id);

    return $base;
}


sub test_remove_base_node($vm, $node1, $node2) {

    my $base = _req_create($node1);
    is($base->_data('id_vm'), $node1->id);
    Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request(debug=>1);

    is($base->base_in_vm($vm->id),0);
    is($base->base_in_vm($node1->id),1);

    Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $base->id
        ,id_vm => $node2->id
    );
    wait_request(debug=>1);

    Ravada::Request->remove_base_vm(
        uid => user_admin->id
        ,id_domain => $base->id
        ,id_vm => $vm->id
    );
    wait_request(debug=>1);

    $base = Ravada::Domain->open($base->id);
    is($base->base_in_vm($vm->id),0);
    is($base->base_in_vm($node1->id),1);
    is($base->base_in_vm($node2->id),1);
    isnt($base->_data('id_vm'), $vm->id);

    my $req_rm = Ravada::Request->remove_base(
        uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request(debug=>1);
    is($req_rm->status,'done');
    is($req_rm->error,'');

    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request(debug=>1);
    is($req->status,'done');
    is($req->error,'');

    remove_domain($base);
}

##################################################################################
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP:{
        skip($msg,10);
    }
    done_testing();
    exit;
}

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name ( 'Void', 'KVM') {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        my ($node1, $node2) = remote_node_2($vm_name);

        if ( !$node1 || !$node2 ) {
            diag("Skipped: No remote nodes configured in $Test::Ravada::FILE_CONFIG_REMOTE");
            goto NEXT;
        }

        test_remove_base_node($vm, $node1, $node2);
        test_remove_base_node($vm, $node2, $node1);

        my $node_shared = remote_node_shared($vm_name)  or next;

        test_remove_base_node($vm, $node1, $node_shared);
        test_remove_base_node($vm, $node2, $node_shared);

        test_remote_standalone($node1, $node2, $node_shared);

        test_remove_n($node1, $node2, $node_shared);
        # create on local first
        test_remove_n($vm, $node1, $node2, $node_shared);

        test_remove($vm, $node1, $node2);

        NEXT:
        clean_remote_node($node1)   if $node1;
        clean_remote_node($node2)   if $node2;
        remove_node($node1)         if $node1;
        remove_node($node2)         if $node2;
        remove_node($node_shared)   if $node_shared;
    }

}

END: {
    end();
    done_testing();
}

