use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use POSIX ":sys_wait_h";
use Test::More;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;
use Sys::Statistics::Linux;

use_ok('Ravada');

my $RVD_BACK = rvd_back( );

my $USER = create_user('foo','bar', 1);

sub test_new_domain {
    my $vm = shift;

    my $name = new_domain_name();

    my $freemem = _check_free_memory();
    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                                        , id_iso => search_id_iso('Alpine')
                                        ,vm => $vm->type
                                        ,id_owner => $USER->id
                                        ,memory => 4*1024*1024
                                        ,disk => 1 * 1024*1024
            ) 
    };
    if ($freemem < 1 ) {
        ok($@,"Expecting failed because we ran out of free RAM");
        return;
    }
    ok(!$@,"Domain $name not created: $@");

    ok($domain,"Domain not created") or return;
    eval { $domain->start($USER); sleep 1; };

    if ($freemem < 1 || $@ =~ /free memory/) {
        ok($@,"Expecting failed start because we ran out of free RAM ($freemem MB Free)");
        return;
    }
    ok(!$@,"Expected start domain with $freemem MB Free $@");

    
    #Ckeck free memory
    
    #virsh setmaxmem $name xG --config
    #virsh setmem $name xG --config

    return $domain;
}

sub test_new_domain_req {
    my $vm = shift;

    my $base;
    eval { $base= $vm->create_domain(name => new_domain_name()
                                        , id_iso => search_id_iso('Alpine')
                                        ,vm => $vm->type
                                        ,id_owner => $USER->id
                                        ,memory => (_check_free_memory() * 2) * 1024 * 1024
                                        ,disk => 1 * 1024*1024
            )
    };
    is(''.$@,'') or return;
    $base->prepare_base(user_admin);
    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_base => $base->id
        ,id_owner => user_admin->id
        ,remote_ip => '127.0.0.1'
    );
    ok($req) or return;
    wait_request($req);

    my $domain = rvd_back->search_domain($name);
    ok($domain) or return;

    my $req_start = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => '127.0.0.1'
    );
    rvd_back->_process_requests_dont_fork();
    ok($req_start->status, 'done');
    is($domain->is_active, 0 );
    like($req_start->error,qr(.));

    $domain->remove(user_admin);
    $base->remove(user_admin);

}

sub _check_free_memory{
    my $lxs  = Sys::Statistics::Linux->new( memstats => 1 );
    my $stat = $lxs->get;
    my $freemem = $stat->memstats->{realfree};
    #die "No free memory" if ( $stat->memstats->{realfree} < 500000 );
    my $free = int( $freemem / 1024 );
    $free = $free / 1024;
    $free =~ s/(\d+\.\d+)/$1/;
    return $free;
}



################################################################
my $vm;

remove_old_domains();
remove_old_disks();

for my $vm_name (vm_names()) {
SKIP: {
    my $msg = "SKIPPED test: No $vm_name backend found";
    my $vm = $RVD_BACK->search_vm($vm_name);
    #    $msg = "SKIPPED: todo review overcommitting issue #1164";
    #$vm = undef;

    if ($vm_name eq 'KVM' && $>) {
        $msg = "SKIPPED test: $vm_name must be run from root";
        $vm = undef;
    }
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok("Ravada::Domain::$vm_name");

    my $freemem = _check_free_memory();
    my $n_domains = int($freemem)*2+2;

    if ($n_domains > 50 ) {
        my $msg = "Skipped freemem check, too many memory in this host";
        diag($msg);
        skip($msg,10);
        next;
    }

    $freemem =~ s/(\d+\.\d)\d+/$1/;

    diag("Checking it won't start more than $n_domains domains with $freemem free memory");

    my @domains;
    for ( 0 .. $n_domains ) {
#        diag("Creating domain $_");
        my $domain = test_new_domain($vm) or last;
        push @domains,($domain) if $domain;
    }

    test_new_domain_req($vm) if $vm_name ne 'Void';
    for (@domains) {
        $_->shutdown_now($USER);
    }
    for (@domains) {
        $_->remove($USER);
    }
};
}

end();

done_testing();
