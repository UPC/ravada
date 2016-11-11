use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use POSIX ":sys_wait_h";
use Test::More;
use Test::SQL::Data;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;
use Sys::Statistics::Linux;

my $BACKEND = 'KVM';

use_ok('Ravada');
use_ok("Ravada::Domain::$BACKEND");

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
my $RVD_BACK = rvd_back( $test->connector , 't/etc/ravada.conf');

my $USER = create_user('foo','bar');

sub test_new_domain {
    my $vm = shift;

    my $name = new_domain_name();

    my $freemem = _check_free_memory();
    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                                        , id_iso => 1
                                        ,vm => $vm->type
                                        ,id_owner => $USER->id
                                        ,memory => 1.5*1024*1024
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

SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    my $vm = $RVD_BACK->search_vm('KVM');
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    my $freemem = _check_free_memory();
    my $n_domains = int($freemem)+2;

    $freemem =~ s/(\d+\.\d)\d+/$1/;

    diag("Checking it won't start more than $n_domains domains with $freemem free memory");

    my @domains;
    for ( 0 .. $n_domains ) {
        diag("Creating domain $_");
        my $domain = test_new_domain($vm) or last;
        push @domains,($domain) if $domain;
    }

    for (@domains) {
        $_->shutdown_now($USER);
    }
    for (@domains) {
        $_->remove($USER);
    }
};

remove_old_domains();
remove_old_disks();

done_testing();
