use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::KVM');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada = Ravada->new( connector => $test->connector);

sub test_vm_kvm {
    my $vm = $ravada->vm->[0];
    ok($vm,"No vm found") or exit;
    ok(ref($vm) =~ /KVM$/,"vm is no kvm ".ref($vm)) or exit;

    ok($vm->type, "Not defined $vm->type") or exit;
    ok($vm->host, "Not defined $vm->host") or exit;

}
sub test_remove_domain {
    my $name = shift;

    my $domain;
    eval {$domain = $ravada->domain_search($name) };

    if ($domain) {
        $domain->remove();
    }
    eval {$domain = $ravada->domain_search($name) };
    die "I can't remove old domain $name"
        if $domain;

}

sub test_new_domain {
    my $name = "test_domain_$0";

    test_remove_domain($name);
    my $domain = $ravada->domain_create(name => $name, id_iso => 1);

    ok($domain,"Domain not created");
    ok(ref $domain =~ /Sys::Virt/, "Expecting Sys::Virt, got ".ref($domain))
        if $domain;

    return $domain;
}

################################################################

test_vm_kvm();
my $domain = test_new_domain();
test_remove_domain($domain->name) if $domain;

done_testing();
