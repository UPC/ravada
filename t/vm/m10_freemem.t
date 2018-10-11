#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();
clean();

#################################################################################

sub test_min_freemem {
    my $vm = shift;

    my $sth = connector->dbh->prepare(
        "UPDATE vms SET min_free_memory=? "
        ." WHERE id=?"
    );

    my $min_free_memory = $vm->free_memory * 2;

    ok($min_free_memory > 0
        && $min_free_memory !~ /^0+\.0+$/
        ,"[".$vm->type."] Expecting some free memory on the VM , got $min_free_memory");
    $sth->execute( $min_free_memory, $vm->id );
    $sth->finish;

    my $type = $vm->type;
    $type = 'KVM'   if $type =~ /qemu/i;

    $vm->disconnect;
    delete $vm->{_data};


    ok($vm) or return;
    is($vm->min_free_memory, $min_free_memory) or exit;

    my $domain = create_domain($vm->type);
    my $req = Ravada::Request->start_domain(
               uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => 'localhost'
    );
    ok($req);
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    like($req->error, qr'memory'i);

    $domain->remove(user_admin);
}
#################################################################################

for my $vm_name ( vm_names() ) {

    init('t/etc/ravada_freemem.conf');
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

        test_min_freemem($vm);

    }
}

clean();

done_testing();

