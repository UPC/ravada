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

sub test_remove_n($vm, @nodes ) {
    my $domain = create_domain($vm);

    $domain->prepare_base(user_admin);

    my $n=1;
    for my $node ( @nodes ) {
        $domain->set_base_vm(vm => $node, user => user_admin);
        is($domain->list_instances, ++$n);
    }

    for my $node1 ( @nodes ) {
        my $clone = $domain->clone(user => user_admin, name => new_domain_name);
        $clone->migrate($node1);
        $clone->start(user_admin);
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
    $clone1->migrate($node1);
    is($clone1->list_instances,2);

    my $clone2 = $domain->clone( user => user_admin
        , name => new_domain_name
    );
    $clone2->migrate($node1);
    $clone2->migrate($node2);
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

        my $node_shared = remote_node_shared($vm_name)  or next;

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

