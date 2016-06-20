use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::LXC');
use_ok('Ravada::VM::LXC');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $RAVADA= Ravada->new( connector => $test->connector);
my $vm_lxc;

my $CONT= 0;


sub test_remove_domain {
    my $name = shift;
    diag("Removing domain $name");
    my $domain = $vm_lxc->search_domain($name);
    $domain->remove() if $domain;
    diag ("$@");
    ok(!$@ , "Error removing domain $name : $@") or exit;
  
    $domain = $RAVADA->search_domain($name);
    ok(!$domain, "I can't remove old domain $name") or exit;
}

sub test_remove_domain_by_name {
    my $name = shift;

    diag("Removing domain: $name");
    $vm_lxc->remove_domain($name);

    my $domain = $vm_lxc->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;
}

sub search_domain_db {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
 diag("search_domain_db -> $sth ");
    $sth->execute($name);
 diag("search_domain_db -> $sth ");

    my $row =  $sth->fetchrow_hashref;
 diag("search_domain_db -> $row ");
    return $row;
}

sub test_new_domain {
    my $active = shift;
    
    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$CONT++;
    diag ("Test remove domain");
    test_remove_domain($name);

    diag("Creating container $name. It may take looong time the very first time.");
    my $domain = $vm_lxc->create_domain(name => $name, id_iso => 1, active => $active);
    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::LXC';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('lxc-info','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    return $name;
}

sub test_domain_inactive {
    my $domain = test_domain(0);
}

sub test_domain{
    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $RAVADA->list_domains();
    
    diag("Test new domain n_domains= $n_domains");
    my $domain = test_new_domain($active);
}

################################################################
eval { $vm_lxc = Ravada::VM::LXC->new() };
SKIP: {

    my $msg = ($@ or "No LXC vitual manager found");

    my $vm = $RAVADA->search_vm('lxc');

    if (!$vm_lxc) {
        ok(!$vm,"There should be no LXC backends");
        diag("SKIPPING LXC tests: $msg");
        skip $msg,10;
    } else {
        $Ravada::VM::LXC::CMD_LXC_LS = '';
        # twice to ignore warnings
        $Ravada::VM::LXC::CMD_LXC_LS = '';
        diag("Testing missing LXC");

        my $ravada2 = Ravada->new();
        my $vm2 = $ravada2->search_vm('lxc');
        ok(!$vm2,"No LXC virtual manager should be found withoud LXC_LS defined");
    }
    ok($vm,"I can't find a LXC virtual manager from ravada");

my $domain = test_domain();
test_remove_domain($domain);
}

done_testing();