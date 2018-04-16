use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
init($test->connector);

######################################################################3

sub test_volatile_clone {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    ok($domain);

    is($domain->volatile_clones, 0);

    $domain->volatile_clones(1);
    is($domain->volatile_clones, 1);

    my $clone = $domain->clone(
        name => new_domain_name
        ,user => user_admin
    );

    is($clone->is_active, 1);
    is($clone->is_volatile, 1);

    $clone->start(user_admin)   if !$clone->is_active;

    is($clone->is_active, 1) && do {

        my $clonef = Ravada::Front::Domain->open($clone->id);
        ok($clonef);
        is($clonef->is_active, 1);

        $clonef = rvd_front->search_domain($clone->name);
        ok($clonef);
        is($clonef->is_active, 1);


        $clone->shutdown_now(user_admin);

        my $clone2 = $vm->search_domain($clone->name);
        ok(!$clone2, "[".$vm->type."] volatile clone should be removed on shutdown");

    };

    $clone->remove(user_admin)  if !$clone->is_removed;
    $domain->remove(user_admin);
}


######################################################################3
clean();

for my $vm_name ( vm_names() ) {
    ok($vm_name);
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing volatile for $vm_name");

        test_volatile_clone($vm);
    }
}

clean();

done_testing();
