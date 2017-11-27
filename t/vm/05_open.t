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

init($test->connector);

clean();

#############################################################

sub test_create_domain {
    my $vm_type = shift;

    my $domain = create_domain($vm_type);
    my $domain_open = Ravada::Domain->open($domain->id);

    is(ref($domain_open),"Ravada::Domain::$vm_type"
        ,"Expecting domain in $vm_type");

    my $id_domain = $domain->id;
    like($id_domain,qr/^\d+/);
    $domain->remove(user_admin);

    if (defined $id_domain) {
        my $domain_gone;
        eval { $domain_gone = Ravada::Domain->open($id_domain)};
        is($domain_gone,undef,"Expecting no domain ".$id_domain);
    }
}

my $id = 10;
for my $vm_type( @{rvd_front->list_vm_types}) {
    diag($vm_type);
    my $exp_class = "Ravada::VM::$vm_type";

    my $sth = $test->connector->dbh->prepare(
        "INSERT INTO vms (id, name, vm_type, hostname) "
        ." VALUES(?,?,?,?)"
    );
    $sth->execute($id, $vm_type, $vm_type, 'localhost');
    $sth->finish;

    my $vm = Ravada::VM->open($id);
    is(ref($vm),$exp_class);

    test_create_domain($vm_type) if rvd_back->search_vm($vm_type);

    $id++;
}

done_testing();
