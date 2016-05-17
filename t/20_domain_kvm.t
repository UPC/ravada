use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::KVM');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada = Ravada->new( connector => $test->connector);

my $cont = 0;

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

    ok(!search_domain_db($name),"Domain $name still in db");
}

sub test_remove_domain_by_name {
    my $name = shift;

    diag("Removing domain $name");
    $ravada->remove_domain($name);

    my $domain = $ravada->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

}

sub search_domain_db {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_new_domain {
    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$cont++;

    test_remove_domain($name);

    diag("Creating domain $name");
    my $domain = $ravada->create_domain(name => $name, id_iso => 1);

    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $row =  search_domain_db($domain->name);
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");

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



sub test_domain{

    my ($name) = $0 =~ m{.*/(.*)\.t};
    test_remove_domain($name);

    my $n_domains = scalar $ravada->list_domains();
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {
        my @list = $ravada->list_domains();
        ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
            .($n_domains+1)
            ." "
            .join(",", sort map { $_->name } @list)
        );
        ok(!$domain->is_base,"Domain shouldn't be base "
            .Dumper($domain->_select_domain_db()));

        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );

        test_remove_domain($domain->name);
    }
}

sub test_domain_by_name {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {
        test_remove_domain_by_name($domain->name);
    }
}

sub test_prepare_import {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {

        my $sth = $test->connector->dbh->prepare("DELETE FROM domains WHERE id=?");
        $sth->execute($domain->id);

        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );

        test_remove_domain($domain);
    }

}

sub remove_old_domains {
    my ($name) = $0 =~ m{.*/(.*)\.t};
    for ( 0 .. 10 ) {
        test_remove_domain($name."_".$_);
    }
}

################################################################

test_vm_kvm();

remove_old_domains();
test_domain();
test_domain_by_name();
test_prepare_import();

done_testing();
