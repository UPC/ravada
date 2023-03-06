use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use feature qw(signatures);
no warnings "experimental::signatures";

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

init();

clean();

#############################################################

sub test_create_domain {
    my $vm = shift;
    my $vm_type = shift;

    my $domain = create_domain($vm);
    my $domain_open = Ravada::Domain->open($domain->id);
    ok($domain_open,"Expecting domain id ".$domain->id);
    is(ref($domain_open),"Ravada::Domain::$vm_type"
        ,"Expecting domain in $vm_type");

    my $id_domain = $domain->id;
    like($id_domain,qr/^\d+/);

    my $domain2 = $vm->search_domain($domain->name);
    ok($domain2);

    is(ref($domain2),"Ravada::Domain::$vm_type"
        ,"Expecting domain in $vm_type");

    $domain->remove(user_admin);

    if (defined $id_domain) {
        my $domain_gone;
        eval { $domain_gone = Ravada::Domain->open($id_domain)};
        is($domain_gone,undef,"Expecting no domain ".$id_domain);
    }
}

sub test_which($vm) {
    my $ls = $vm->_which("ls");
    ok($ls);
}

###############################################################

clean();
my $id = 10;

for my $vm_type( vm_names() ) {
    diag($vm_type);

    my $vm = rvd_back->search_vm($vm_type);
    my $exp_class = "Ravada::VM::$vm_type";

    SKIP: {
        skip("Skipping $exp_class on this system",10)   if !$vm;

    my $sth = connector->dbh->prepare("DELETE FROM vms WHERE vm_type=?");
    $sth->execute($vm_type);
    $sth->finish;

    $sth = connector->dbh->prepare(
        "INSERT INTO vms (id, name, vm_type, hostname) "
        ." VALUES(?,?,?,?)"
    );
    eval {$sth->execute(++$id, $vm_type, $vm_type, 'localhost') };
    is($@,'',"[$vm_type] Expecting no errors insert $vm_type in db");
    $sth->finish;

    my $vm = Ravada::VM->open($id);
    is(ref($vm),$exp_class);

    if (!$< || $vm_type ne 'KVM') {
        init_vm($vm);
        test_which($vm);
        test_create_domain($vm, $vm_type) if rvd_back->search_vm($vm_type);
    }

    $id++;
    };
}

end();
done_testing();
