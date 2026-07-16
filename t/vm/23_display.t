use warnings;
use strict;

use Carp qw(confess cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json);
use Socket;
use XML::LibXML;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $FILE_CONFIG = 't/etc/ravada.conf';

my $USER;

my $DISPLAY_IP = '99.1.99.1';
my $BASE;

########################################################################

sub test_display_conflict($vm) {
    diag("Test display conflict");
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain->start( remote_ip => '1.1.1.1' , user => user_admin);
    my ($display_builtin) = @{$domain->info(user_admin)->{hardware}->{display}};
    $domain->shutdown_now(user_admin);

    for my $driver ('x2go','rdp') {

        my $req = Ravada::Request->add_hardware(
            uid => user_admin->id
            ,name => 'display'
            ,data => { driver => $driver }
            ,id_domain =>$domain->id
        );
        wait_request(check_error => 0);
        is($req->status,'done');
        is($req->error,'');
    }

    my $port = $domain->exposed_port(22);
    my $sth = connector->dbh->prepare("UPDATE domain_ports SET public_port=NULL "
        ." WHERE public_port=?");
    $sth->execute($display_builtin->{port});

    $sth = connector->dbh->prepare("UPDATE domain_ports SET public_port=? "
        ." WHERE id=?");
    $sth->execute($display_builtin->{port},$port->{id});

    $sth = connector->dbh->prepare("UPDATE domain_displays SET port=? "
        ." WHERE id_domain=? AND driver=?");
    $sth->execute($display_builtin->{port},$domain->id, 'x2go');

    my $port2 = $domain->exposed_port(22);
    is($port2->{public_port},$display_builtin->{port});

    $domain->shutdown(user => user_admin, timeout => 30);
    wait_request(debug => 0);

    $domain->start( remote_ip => '1.1.1.1' , user => user_admin);
    wait_request(debug => 0);
    wait_ip($domain);

    for my $n ( 1 .. 3 ) {
        my $display = $domain->info(user_admin)->{hardware}->{display};
        last if defined $display->[0]->{port}
            && defined $display->[1]->{port}
            && defined $display->[2]->{port}
            && $display->[0]->{port} ne $display->[1]->{port};
        Ravada::Request->refresh_machine(uid => user_admin->id
            ,id_domain=> $domain->id
            ,_force => 1
        );
        wait_request(debug => 0);
    }

    my $display = $domain->info(user_admin)->{hardware}->{display};

    isnt($display->[0]->{port}, $display->[1]->{port}) or die Dumper($display);
    is($display->[0]->{is_active},1);
    is($display->[1]->{is_active},1);

    $domain->start(user_admin);
    my @drivers;
    for my $entry (@$display) {
        push @drivers,($entry->{driver});
    }
    my $hostname = _get_hostname($vm->ip);
    for my $driver ( @drivers ) {
        my $display2 = $domain->_get_display($driver);
        next if !keys %$display2;
        is($display2->{hostname},$hostname) or die Dumper($display2);

        _check_display_file($domain, $display2);
    }

    my $port3;
    for ( 1 .. 10 ) {
        $port3 = $domain->exposed_port(22);
        last if $port3->{public_port} && $port3->{public_port} != $display_builtin->{port};
        Ravada::Request->refresh_machine(uid => user_admin->id ,id_domain => $domain->id
            , _force => 1);
        wait_request(debug => 0);
    }
    ok($port3->{public_port});
    isnt($port3->{public_port},$display_builtin->{port}) or die $domain->id." ".$domain->name;

    $domain->remove(user_admin);

}

sub _check_display_file_rdp($domain, $display) {
    my $driver = $display->{driver};
    my $address;
    for ( 1 .. 10 ) {
        my $display2 = $domain->_get_display($driver);
        my $file = $domain->_display_file_rdp($display2);
        ($address) = $file =~ m{^full address:.:(.*?)\:\d+$}ms;
        last if $address;
        my $req = Ravada::Request->open_exposed_ports(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        $req->status('requested') if $req->status() eq 'done';
        my $req2 = Ravada::Request->refresh_machine(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        $req2->status('requested') if $req2->status() eq 'done';

        wait_request(debug => 1, request => $req);
        sleep 1;
    }


    is($address, _get_hostname($domain->_vm->ip)) or exit;
}

sub _check_display_file_spice($domain, $display) {
    my $file = $domain->_display_file_spice($display);
    my ($address) = $file =~ m{^host=(.*?)$}ms;

    is($address, _get_hostname($domain->_vm->ip));

}


sub _check_display_file($domain, $display) {
    my $driver = $display->{driver};
    if ($driver =~ /^spice/) {
        _check_display_file_spice($domain, $display);
    } elsif ($driver eq 'rdp') {
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(debug => 0);
        wait_ip($domain);
        _check_display_file_rdp($domain, $display);
    } else {
        diag("No test for display $driver");
    }
}

sub _get_hostname($ip) {

    return $ip if $ip !~ /^\d+\.\d+\.\d+\.\d+$/;

    my ($in, $out, $err);
    run3(['host',$ip], \$in, \$out, \$err);
    my ($hostname) = $out =~ /pointer (.*)\./;
    ($hostname) = $out =~ /pointer (.*)\./;
    die "I can't fetch hostname from $out" if !$hostname;

    return $hostname;
}

######################################################################

for my $db ( 'mysql', 'sqlite' ) {
    next if $> && $db eq 'mysql';
    if ($db eq 'mysql') {
        init('/etc/ravada.conf',0, 1);
        if ( !ping_backend() ) {
            diag("SKIPPED: no backend running");
            next;
        }
        $Test::Ravada::BACKGROUND=1;
        remove_old_domains_req(1,1);
        wait_request( debug => 0);
    } elsif ( $db eq 'sqlite') {
        init(undef, 1,1); # flush
        $Test::Ravada::BACKGROUND=0;
    }
    clean();

    $USER = create_user(new_domain_name(),"bar");

    for my $vm_name ( vm_names() ) {

        diag("Testing $vm_name VM $db");
        my $CLASS= "Ravada::VM::$vm_name";

        my $vm;

        eval { $vm = rvd_back->search_vm($vm_name) };

        SKIP: {
            my $msg = "SKIPPED test: No $vm_name VM found ";
            if ($vm && $vm_name =~ /kvm/i && $>) {
                $msg = "SKIPPED: Test must run as root";
                $vm = undef;
            }

            diag($msg)      if !$vm;
            skip $msg,10    if !$vm;

            use_ok($CLASS);
            if ($vm_name eq 'KVM' ) {
                my $name = 'zz-test-base-alpine-q35-uefi';
                $BASE = rvd_back->search_domain($name);
                $BASE = import_domain($vm,$name) if !$BASE;
            } else {
                $BASE = create_domain($vm);
            }
            flush_rules() if !$<;

            test_display_conflict($vm);
        }
    }
}
end();
done_testing();
