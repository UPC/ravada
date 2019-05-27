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

sub test_remove($vm, $node1, $node2) {
    my $domain = create_domain($vm);

    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node1, user => user_admin);
    $domain->set_base_vm(vm => $node2, user => user_admin);

    my $clone1 = $domain->clone( user => user_admin
        , name => new_domain_name
    );
    $clone1->migrate($node1);

    my $clone2 = $domain->clone( user => user_admin
        , name => new_domain_name
    );
    $clone2->migrate($node1);
    $clone2->migrate($node2);

    my @name = ( $clone1->name, $clone2->name, $domain->name);
    my @id = ( $clone1->id, $clone2->id, $domain->id);

    $clone1->remove(user_admin);
    $clone2->remove(user_admin);
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

        test_remove($vm, $node1, $node2);

        NEXT:
        clean_remote_node($node1)   if $node1;
        clean_remote_node($node2)   if $node2;
        remove_node($node1)         if $node1;
        remove_node($node2)         if $node2;
    }

}

END: {
    clean();
    done_testing();
}

