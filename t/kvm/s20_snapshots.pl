#!perl
use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my @VMS = vm_names();
init($test->connector, 't/etc/ravada_kvm.conf');

###################################################################################
sub test_snapshots {
	my $vm = shift;
	my $domain = create_domain($vm->type);
    ok($domain);

    $domain->start(user_admin) if !$domain->is_active();
	warn "BSNAP";    
    my $snap = $domain->create_snapshot($domain->xml_description);
    ok($snap, "Create Snapshot");
    
    is($domain->has_current_snapshot(),1);
    
    warn ref($snap);
    
    $snap->delete_snapshot();
    ok(!$snap, "Delete Snapshot $snap");
}

###################################################################################

clean();
my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);


SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    test_snapshots($vm);
}

clean();
done_testing();
1;