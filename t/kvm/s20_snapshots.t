#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector);
clean();

###################################################################################

sub test_snapshots_pre {
	my $vm = shift;
	my $domain = create_domain($vm->type);
    ok($domain);

    $domain->start(user_admin) if !$domain->is_active();
    my $snap_template_xml = "<domainsnapshot>
  <name>test_snap</name>
</domainsnapshot>";
    my $snap = $domain->domain->create_snapshot($snap_template_xml); #Sys::Virt::DomainSnapshot
    ok($snap, "Create Snapshot");
    
    is($domain->domain->has_current_snapshot(),1);
    
    eval {$snap->delete()};
    ok(!$@, "Deleted Snapshot");
}

sub test_snapshots_post {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    ok($domain);

    $domain->start(user_admin) if !$domain->is_active();
    
    my $sname = "test_snap";
    eval{ $domain->create_snapshot($sname) };
    ok(!$@);
    
    my @snaps = $domain->list_snapshots();
    ok(scalar @snaps > 0);
    
    eval{ $domain->delete_snapshot($sname) };
    ok(!$@);
    
    eval { $domain->delete_snapshot('fake_name') };
    ok($@);
}

###################################################################################


for my $vm_name ( q(KVM) ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };
    warn $@ if $@;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg       if !$vm;

        diag("Testing free mem on $vm_name");

        test_snapshots_post($vm);
    }
}
clean();

done_testing();
1;