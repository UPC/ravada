use warnings;
use strict;

use IPC::Run3;
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
    $domain = $ravada->search_domain($name);

    if ($domain) {
        diag("Removing domain $name");
        $domain->remove();
    }
    $domain = $ravada->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

}

sub test_new_domain {
    my ($name) = $0 =~ m{.*/(.*)};

    test_remove_domain($name);
    my $domain = $ravada->create_domain(name => $name, id_iso => 1);

    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    $sth->finish;

    return $domain;
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base();

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? AND is_base='y'");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name);
    $sth->finish;
}

################################################################

test_vm_kvm();
my $domain = test_new_domain();

if (ok($domain,"test domain not created")) {
    test_prepare_base($domain);
    test_remove_domain($domain->name);
}

done_testing();
