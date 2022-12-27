#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

init();
clean();
###################################################################

sub test_change_memory {
	my $vm = shift;
	my $max_memoryGB = shift;
	my $use_mem_GB = shift;
    my $start = (shift or 0);

	my $factor = 1024*1024;#kb<-Gb
	
	my $domain = create_domain($vm->type);

    $domain->start(user_admin) if $start;
	
	eval {
		$domain->set_max_mem($max_memoryGB*$factor)
	};
	is(''.$@,'',"set max mem [start=$start]") or return;
    if ($start) {
        $domain->shutdown_now(user_admin);
        $domain->start(user_admin);
    }

	my $info;
	eval { $info = $domain->get_info() };
    is($info->{max_mem} , $max_memoryGB * $factor);

    if ($start) {
        $domain->shutdown_now(user_admin);
	    eval { $info = $domain->get_info() };
        is($info->{max_mem} , $max_memoryGB * $factor);

        $domain->start(user_admin);
	    eval { $info = $domain->get_info() };
        is($info->{max_mem} , $max_memoryGB * $factor);
    }

    my $domain_f = rvd_front->search_domain($domain->name);
    my $info_f = $domain_f->get_info();
    is($info_f->{max_mem} , $max_memoryGB * $factor);

	eval {
		$domain->set_memory($use_mem_GB*$factor)
	};
	is(''.$@,'');
	
	eval {
		$info = $domain->get_info()
	};
	my $nvalue = $info->{memory};
    is($nvalue , $use_mem_GB * $factor,"set current memory [start=$start]");

    $domain_f = rvd_front->search_domain($domain->name);
    $info_f = $domain_f->get_info();
    is($info_f->{memory} , $use_mem_GB * $factor,"get current memory frontend [start=$start]");

    $domain->remove(user_admin);
}

sub test_change_memory_base {
	my $vm = shift;
	
	my $domain = create_domain($vm->type);
	$domain->shutdown_now(user_admin)    if $domain->is_active();

    eval { $domain->prepare_base( user_admin ) };
    ok(!$@, $@);
    ok($domain->is_base);
    
    eval { $domain->set_max_mem(1024*1024*3) };
    ok(!$@,$@);

    $domain->remove(user_admin);
}

sub test_change_max_mem_active($vm) {
    my $domain = create_domain($vm);
    my $max_mem = $domain->info(user_admin)->{max_mem};
    my $mem = $domain->info(user_admin)->{memory};

    my $new_max_mem = int($max_mem * 1.5 ) + 1;
    my $new_mem = int($mem * 1.5 ) + 1;
    $domain->start(user_admin);

    my $req1 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => { max_mem => $new_max_mem }
    );
    wait_request();

    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->info(user_admin)->{max_mem},$new_mem);

    is($domain2->_data('needs_restart'),1);
    $domain->remove(user_admin);
}

sub test_req_change_mem($vm) {
    my $domain = create_domain($vm);
    my $max_mem = $domain->info(user_admin)->{max_mem};
    my $mem = $domain->info(user_admin)->{memory};

    my $new_max_mem = int($max_mem * 1.5 ) + 1;
    my $new_mem = int($mem * 1.5 ) + 1;

    my $req1 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => { max_mem => $new_max_mem }
    );

    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => { memory => $new_mem }
    );

    wait_request(check_error => 1, background => 0);

    is($req1->status,'done');
    is($req2->status,'done');

    is($req1->error,'');
    is($req2->error,'');

    my $max_mem2 = $domain->info(user_admin)->{max_mem};
    my $mem2 = $domain->info(user_admin)->{memory};

    is($max_mem2, $new_max_mem);
    is($mem2, $new_mem);

    $domain->remove(user_admin);
}

sub test_change_max_mem_base($vm) {
    my $base = create_domain($vm);
    my $max_mem = $base->info(user_admin)->{max_mem};
    my $mem = $base->info(user_admin)->{memory};

    my $new_max_mem = int($max_mem * 1.5 ) + 1;
    Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request();
    $base->_refresh_db();
    is($base->is_base,1);

    my $clone = $base->clone(user => user_admin, name => new_domain_name);
    $new_max_mem = int($new_max_mem * 1.5 ) + 1;

    my $req1 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $base->id
        ,hardware => 'memory'
        ,data => { max_mem => $new_max_mem }
    );
    wait_request(debug => 0);

    my $domain3 = Ravada::Domain->open($base->id);
    is($domain3->info(user_admin)->{max_mem},$new_max_mem);

    is($clone->info(user_admin)->{max_mem},$new_max_mem) or exit;

    my $clone2 = $domain3->clone(user => user_admin, name => new_domain_name);
    is($clone2->info(user_admin)->{max_mem},$new_max_mem) or
    die Dumper({base => $base->name
            ,max_mem => $max_mem,new_max_mem => $new_max_mem});
}

####################################################################

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
        skip $msg,10    if !$vm;

        diag("Testing free mem on $vm_name");

        test_change_max_mem_active($vm);
        test_change_max_mem_base($vm);

        test_req_change_mem($vm);

        test_change_memory($vm, 2, 2);
        test_change_memory($vm, 2, 2, 1);

        test_change_memory($vm, 2, 1);
        test_change_memory($vm, 2, 1, 1);

        test_change_memory_base($vm);

    }
}

end();
done_testing();
