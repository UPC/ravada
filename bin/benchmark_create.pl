#!/usr/bin/perl

use warnings;
use strict;

use Benchmark;
use Carp qw(confess);
use Getopt::Long;
use Net::Ping;
use Data::Dumper;
use Ravada;
use Ravada::Domain;
use Ravada::Utils;
use Sys::Virt;

my ($HELP);
my $PORT = 3000;
my $HOST = 'localhost';
my $N_REQUESTS;
my $TIMEOUT = 60;
my $KEEP = 0;
my $CONSOLE = 1;
my $START = 1;
my $PING = 1;
my $DEBUG;
my $REMOTE_VIEWER = `which remote-viewer`;
chomp $REMOTE_VIEWER;

my $CONT = 0;

$|=1;

my $RVD_BACK = Ravada->new();
my $RVD_FRONT = Ravada::Front->new();

my $USER_DAEMON = Ravada::Utils->user_daemon();

GetOptions(
    help => \$HELP
    ,debug => \$DEBUG
    ,'requests=s' => \$N_REQUESTS
    ,'timeout=s' => \$TIMEOUT
    ,'keep' => \$KEEP
    ,'console!' => \$CONSOLE
    ,'start!' => \$START
    ,'ping!' => \$PING
) or exit;

my ($ID_BASE) = shift @ARGV;

if ($HELP || !$ID_BASE) {
    if (!$ID_BASE) {
        warn "ERROR: I need the id of a domain to use as base for the benchmark.\n"
        ."    You can use any virtual machine id, but it will be converted to base if\n"
        ."    it already hasn't.\n";
        my $rvd_back = Ravada->new();
        for my $machine ($rvd_back->list_domains) {
            next if $machine->is_volatile;
            print $machine->id."\t".$machine->name;
            print " (base)" if $machine->is_base;
            print "\n";
        }
    }
    die "$0 [--help] [--requests=X] [--timeout=$TIMEOUT] [--keep] [--console] "
            ." [--start] [--ping] id-base\n"
        ."  - requests: Number of requests for create machines.\n"
        ."  - timeout: Max waiting time for machine to create.\n"
        ."  - keep: Keep the machines created after run the test.\n"
        ."          Machines are cleaned up by default unless this is enabled.\n"
        ."  - console: Show the console of virtual machines.\n"
        ."  - noconsole: Do not show de console, default is to show.\n"
        ."  - start: Start the machines after creation.\n"
        ."  - nostart: Do not start the machines, default is to start.\n"
        ."  - ping: Ping the machines after startup.\n"
        ."  - noping: Do not ping the machines, default is to ping.\n"
            .".\n"
        ;
}

##################################################################################

sub domain_ip {
    my $id = shift;

    my $domain;
    eval { $domain = Ravada::Domain->open($id) };
    warn $@ if $@;
    return if !$domain;
    my @ip;
    eval { @ip = $domain->domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_LEASE) };
    warn $@ if $@;
    return $ip[0]->{addrs}->[0]->{addr} if $ip[0];
    return;
}

sub new_domain_name {
    my $cont = ++$CONT;
    $cont ="0$cont" while length($cont)<3;
    return "bench_".$$."_".$cont;
}

sub request_create {
    my @requests;
    for ( 1 .. $N_REQUESTS ) {
        my $name = new_domain_name();
        my $user = Ravada::Auth::SQL::add_user(
            name => "user_$name"
            ,is_temporary => 0
        );

        my @args = (
                id_base => $ID_BASE
                ,id_owner => $user->id
                ,name => $name
                ,remote_ip => '127.0.0.1'
        );
        push @args,(start => 1) if $START;
        push @requests,(Ravada::Request->create_domain(@args));
        print "Request create machine $name\n" if $DEBUG;
    }
    return map{ $_->id => $_ } @requests;
}

sub show_console {
    return if !$REMOTE_VIEWER || !$CONSOLE || !$ENV{XAUTHORITY};
    my $domain = shift;
    my $display = $domain->display($USER_DAEMON);
    if (!$domain->spice_password && $display) {
        $domain->_vm->disconnect();
        warn "Show console for domain ".$domain->name."\n";
        my $pid = fork();
        if(!$pid) {
            my $cmd="$REMOTE_VIEWER -z 50 $display";
            print `$cmd`;
            exit 0;
        }
        $domain->_vm->connect();
    }
}

sub open_domain {
    my $req = shift;
    confess "Req is not request" if ref($req) !~ /Request/i;
    my $domain_name = $req->args('name');
    my $domain;
    my $t0 = time;
    my $t1 = time;
    for ( ;; ) {
        exit_timeout($domain_name) if time-$t0 > $TIMEOUT;
        $domain = $RVD_BACK->search_domain($domain_name);
        confess "Domain $domain_name not a domain " if ref($domain) !~ /Domain/;
        return $domain if $domain;
        if ($t1 - time > 1 ) {
            $t1 = time;
        }
    }
    return;
}

sub wait_domain_active {
    my $domain = shift;
    my $t0 = time;

    my $t1 = time;
    for ( ;; ) {
        my $t3 = time;
        last if $domain->is_active;
        last if !check_free_memory($domain->_vm);
        exit_timeout($domain->name) if time-$t0 > $TIMEOUT;
        if (time - $t1 > 1 ) {
            print ".";
            $t1 = time;
        }
    }
    print "\n";
    show_console($domain);
}

sub check_free_memory {
    my $vm = shift;

    my $free_mem = $vm->free_memory / 1024 / 1024;
    $free_mem =~ s/(\d+\.\d?).*/$1/;
    return $free_mem >= 1;

}

sub wait_domain_up{
    my $domain = shift;

    print "Waiting for machine ".$domain->name;

    my $p = Net::Ping->new('icmp');
    my $p_tcp = Net::Ping->new('tcp');
    my $t0 = time;
    my $t1 = time;
    my $ip_showed = 0;
    for ( ;; ) {
        if ( time  - $t1 > 1) {
            print ".";
            $t1 = time;
        }

        exit_timeout($domain->name) if time-$t0 > $TIMEOUT;
        last if !check_free_memory($domain->_vm);

        my $is_active;
        eval { $is_active = $domain->is_active };
        warn $@ if $@;
        last if $@;
        my ($ip) = domain_ip($domain->id);
        if ($ip) {
            print " ".$ip."\n";
            last if $p->ping($ip,1) || $p_tcp->ping($ip,1);
        }
    }
    print "\n";
}

sub shutdown_all {
    my $verbose = shift;
    my @machines = $RVD_BACK->list_domains(active => 1);
    my @reqs;
    my $n = 0;
    for my $machine( @machines ) {
        push @reqs,(Ravada::Request->force_shutdown_domain(
            uid => $USER_DAEMON->id
            ,id_domain => $machine->id
        ));
        print "Shutting down ".$machine->name."\n" if $verbose;
        $n++;
    }
    return if !$n;
    print "Waiting for $n machines to shut down\n" if $n;
    for ( 1 .. $TIMEOUT * $n ) {
        my $pending = 0;
        for my $req(@reqs) {
            $pending++ if $req->status ne 'done';
        }
        last if !$pending;
        print ".";
        sleep 1;
    }

    for ( 1 .. $TIMEOUT * $n) {
        my $still_there = 0;
        for my $machine( @machines ) {
            my $domain;
            eval { $domain = Ravada::Domain->open($machine->id) };
            warn $@ if $@ && $@ !~ /Domain not found/;
            $still_there++ if $domain && $domain->is_active;
        }
        last if !$still_there;
        print ".";
        sleep 1;
    }
    print "\n";
}

sub remove_old {
    remove_old_machines();
    remove_old_users();
}
sub remove_old_users {
    for my $user_f ( @{$RVD_FRONT->list_users} ) {
        next if $user_f->{name} !~ /^user_bench/;
        my $user = Ravada::Auth::SQL->search_by_id($user_f->{id});
        $user->remove();
    }
}

sub remove_old_machines {
    my @machines = $RVD_BACK->list_domains();
    my @reqs;
    for my $machine( @machines ) {
        next if $machine->name !~ /^bench/;
        warn "Removing ".$machine->name."\n";
        push @reqs,(Ravada::Request->remove_domain(
            uid => $USER_DAEMON->id
            ,name => $machine->name
        ));
    }
    return if !scalar @reqs;
    print "Waiting for ".scalar(@reqs)." machines to be removed.\n";
    for ( 1 .. $TIMEOUT * scalar(@reqs) ) {
        my $pending = 0;
        for my $req(@reqs) {
            $pending++ if $req->status ne 'done';
        }
        last if !$pending;
        print ".";
        sleep 1;
    }

}

sub set_base_volatile_anon {
    my $domain = Ravada::Domain->open($ID_BASE);
    if ( !$domain->is_base ) {
        print "Preparing base for ".$domain->name."\n";
        $domain->prepare_base($USER_DAEMON);
    }
    $domain->is_public(1);
    $domain->volatile_clones(0);

}

sub init {
    my $base = Ravada::Domain->open($ID_BASE);
    my $free_memory = $base->_vm->free_memory();
    my $info = $base->get_info();
    #chomp(my $cpu_count = `grep -c -P '^processor\\s+:' /proc/cpuinfo`);
    my $rec_n_requests = int($free_memory / $info->{memory})-1;
    $rec_n_requests = $self->_vm->check_cpu_limits if($self->_vm->check_cpu_limits && $self->_vm->check_cpu_limits < int($free_memory / $info->{memory})-1 && int($cpu_count));

    $N_REQUESTS = $rec_n_requests if !$N_REQUESTS;

    if ( $N_REQUESTS != $rec_n_requests) {
        warn "WARNING: You requested the creation of $N_REQUESTS machines.\n"
            ."But with ".int($free_memory / 1024 /1024)." Gb free it is recommended"
            ." the creation of $rec_n_requests\n";
    }

    print "Benchmarking the creation of $N_REQUESTS machines cloned from "
    .$base->name
    ."\n";
}

sub exit_timeout {
    my $name = shift;
    print "ERROR: Timeout exhausted waiting";
    print " for domain $name\n";
    shutdown_all();
    exit -1;
}

sub check_rvd_back {
    my $req = Ravada::Request->ping_backend();
    for ( 1 .. 5 ) {
        last if $req->status eq 'done';
        sleep 1;
    }
    die "ERROR: I couldn't connect to rvd_back. "
        .($req->error or '')
        ."\n"
        if $req->status ne 'done' || $req->error();

    print "rvd_back connected.\n";
}

sub remove_old_requests {
    my $sth = $RVD_BACK->connector->dbh->prepare(
        "SELECT id FROM requests "
        ." WHERE "
        ."    ( command = 'create'  OR command = 'ping_backend' )"
        ."    AND status <> 'done' "
    );
    my $sth_del = $RVD_BACK->connector->dbh->prepare("DELETE FROM requests WHERE id=?");
    $sth->execute();
    while (my ($id) = $sth->fetchrow) {
        my $request = Ravada::Request->open($id);
        next if $request->command eq 'create'
            && $request->args('name') !~ /^bench_/;
        $sth_del->execute($id);
    }
    $sth->finish;
}
#####################################################################################

remove_old_requests();
check_rvd_back();
remove_old()    if !$KEEP;
shutdown_all(1);
init();
set_base_volatile_anon();

my %requests = request_create();

my $t0 = Benchmark->new();
my @clones;

print "Waiting for ".scalar (keys %requests)." requests to run";
for ( ;; ) {
    my $n_pending = 0;
    for my $id_req (sort { $requests{$a}->args('name') cmp $requests{$b}->args('name') } keys %requests) {
        my $req = $requests{$id_req};
        $n_pending++ if $req->status ne 'done';
        if ($req->status eq 'done') {
            if ( $req->error ) {
                warn $req->error
            } else {
                my $domain = open_domain($req);
                push @clones,($domain)  if $domain;
                last if !check_free_memory($domain->_vm);
            }
            delete $requests{$id_req};
            print ".";
        }
    }
    last if !$n_pending;
}
print "\n";

if ($START) {
    print "Waiting for domains to start\n";
    for my $domain (@clones) {
        wait_domain_active($domain);
        last if !check_free_memory($domain->_vm);
    }
}

if ($START && $PING) {
    print "Waiting for domains to ping\n";
    for my $domain (@clones) {
        wait_domain_up($domain);
        last if !check_free_memory($domain->_vm);
    }
}

print timestr(timediff(Benchmark->new,$t0))." to create ".scalar(@clones)." machines.\n";
remove_old() if !$KEEP;
shutdown_all();
remove_old_requests();
