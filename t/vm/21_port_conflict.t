use warnings;
use strict;

use Carp qw(confess cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json);
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
my $TLS;

###############################################################################

sub test_display_conflict_next($vm) {
    delete $Ravada::Request::CMD_NO_DUPLICATE{refresh_machine};
    delete $Ravada::Request::CMD_NO_DUPLICATE{refresh_machine_ports};
    delete $Ravada::Request::CMD_NO_DUPLICATE{open_exposed_ports};

    rvd_back->setting("/backend/expose_port_min" => 5900 );
    my $domain0 = $BASE->clone(name => new_domain_name, user => user_admin, memory =>512*1024);
    $domain0->_reset_free_port() if $vm->type eq 'Void';
    my $next_port_builtin = _next_port_builtin($domain0);
    rvd_back->setting('/backend/expose_port_min' => $next_port_builtin+3);

    my $domain1 = $BASE->clone(name => new_domain_name, user => user_admin, memory => 512*1024);
    _add_hardware($domain1, 'display', { driver => 'x2go'} );
    # conflict x2go with previous builtin display
    _set_public_exposed($domain1, $next_port_builtin);

    $domain1->start(user => user_admin, remote_ip => '2.3.4.5');
    delete_request('set_time','enforce_limits');
    for ( 1 .. 30 ) {
        my $ip_info = $domain1->ip_info;
        last if exists $ip_info->{addr} && $ip_info->{addr};
        sleep 1;
    }
    wait_request(debug => 0);
    my $displays1;
    my $port_conflict;

    for my $n ( 1 .. 10 ) {
        $displays1 = $domain1->info(user_admin)->{hardware}->{display};
        if ($vm->type eq 'KVM') {
            isnt($displays1->[1+$TLS]->{port}, $next_port_builtin) or die Dumper($displays1);
        }

        # Now conflict x2go with next builtin display
        my ($display_x2go) = grep { $_->{driver} eq 'x2go' } @$displays1;
        $port_conflict = $display_x2go->{port};
        last if $port_conflict;
        my $req = Ravada::Request->open_exposed_ports(
            uid => user_admin->id
            ,id_domain => $domain1->id
            ,_force => 1
        );

        wait_request(debug=>1);
    }
    confess if !defined $port_conflict;

    my @domains = _conflict_port($domain1, $port_conflict);

    my $display_x2go_b;
    my $displays1b;
    for ( 1 .. 10 ) {
        $displays1b = $domain1->info(user_admin)->{hardware}->{display};

        ($display_x2go_b) = grep { $_->{driver} eq 'x2go' } @$displays1b;
        last if $display_x2go_b->{port};
        Ravada::Request->refresh_machine(id_domain => $domain1->id, uid => user_admin->id);
        sleep 1;
        wait_request();
    }

    my %ports;

    for my $domain ( $domain0,$domain1, @domains) {
        my $display_curr = $domain->info(user_admin)->{hardware}->{display};

        my %ports_curr = map { $_->{port} => 1 } @$display_curr;
        for my $i (keys %ports_curr ) {
            ok(!exists $ports{$i});
            $ports{$i}++;
        }
        for my $display (@$display_curr) {
            if ($display->{is_builtin}) {
                _check_iptables_port($vm, $display->{port}) if !$<;
            } else {
                _check_iptables_prerouting($vm, $display->{port}) if !$<;
            }
        }
    }

    for (@domains) {
        $_->remove(user_admin);
    }
    $domain1->remove(user_admin);
    $domain0->remove(user_admin);

    rvd_back->setting("/backend/expose_port_min" => 60000 );
}

sub _next_port_builtin($domain0) {
    $domain0->start(user => user_admin, remote_ip => '1.2.3.4');
    my $displays = $domain0->info(user_admin)->{hardware}->{display};
    my $next_port_builtin = 0;
    for my $display (@$displays) {
        $next_port_builtin = $display->{port}
        if $display->{port} > $next_port_builtin;
    }

    my $listening_ports = _listening_ports();
    for (;;) {
        $next_port_builtin++;
        last if !$listening_ports->{$next_port_builtin};
    }
    diag("Next port builtin will  be $next_port_builtin");

    return $next_port_builtin;
}

sub _listening_ports {
    my ($in, $out, $err);
    my @cmd = ("ss","-tlnp");
    run3(\@cmd,\$in,\$out,\$err);
    my %port;
    for my $line ( split /\n/,$out ) {
        my @local= split(/\s+/, $line);
        my ($listen_port) = $local[3] or die Dumper($line,\@local);
        $listen_port =~ s/.*:(\d+).*/$1/;
        $port{$listen_port}++;
    }
    return \%port;
}

sub _check_iptables_port($vm, $port) {
    #the $port should be in chain RAVADA accept because it is builtin
    # and not on the pre-routing
    my ($out,$err) = $vm->run_command("iptables-save");
    die $err if $err;
    my @iptables_ravada = grep { /^-A RAVADA/ } split /\n/,$out;
    my @accept = grep /^-A RAVADA -s.*--dport $port .*-j ACCEPT/, @iptables_ravada;
    is(scalar(@accept),1,"Expecting --dport $port ") or die Dumper(\@iptables_ravada,\@accept);

    my @drop = grep /^-A RAVADA -d.*--dport $port .*-j DROP/, @iptables_ravada;
    is(scalar(@drop),1) or die Dumper(\@iptables_ravada,\@drop);

    my @iptables_prerouting = grep(/^-A PREROUTING .*--dport $port/, split(/\n/,$out));
    is(scalar(@iptables_prerouting),0) or die Dumper(\@iptables_prerouting);
}

sub _check_iptables_prerouting($vm, $port) {
    #the $port should be in chain RAVADA accept because it is builtin
    # and not on the pre-routing
    my ($out,$err) = $vm->run_command("iptables-save");
    die $err if $err;
    my @iptables_ravada = grep { /^-A RAVADA/ } split /\n/,$out;
    my @accept = grep /^-A RAVADA -s.*--dport $port .*-j ACCEPT/, @iptables_ravada;
    is(scalar(@accept),0,"Expecting --dport $port ") or die Dumper(\@iptables_ravada,\@accept);

    my @drop = grep /^-A RAVADA -d.*--dport $port .*-j DROP/, @iptables_ravada;
    is(scalar(@drop),0) or die Dumper(\@iptables_ravada,\@drop);

    my @iptables_prerouting = grep(/^-A PREROUTING .*--dport $port/, split(/\n/,$out));
    is(scalar(@iptables_prerouting),1) or die Dumper(\@iptables_prerouting);
}


sub _add_hardware($domain, $name, $data) {
    my $req = Ravada::Request->add_hardware(
          uid => user_admin->id
        ,name => $name
        ,data => $data
        ,id_domain =>$domain->id
    );
    wait_request(check_error => 0);
}

sub _set_public_exposed($domain, $port) {
    my $sth = $domain->_dbh->prepare("UPDATE domain_ports set public_port=NULL "
        ." WHERE public_port=?");
    $sth->execute($port);

    $sth =$domain->_dbh->prepare("UPDATE domain_displays set port=NULL"
        ." WHERE port=?");
    $sth->execute($port);


    $sth = $domain->_dbh->prepare("UPDATE domain_ports "
        ." SET public_port=? "
        ." WHERE id_domain=?"
    );
    $sth->execute($port, $domain->id);

    $sth = $domain->_dbh->prepare("UPDATE domain_displays "
        ." SET port=? "
        ." WHERE id_domain=? AND is_builtin=0 "
    );
    $sth->execute($port, $domain->id);
}

sub _conflict_port($domain1, $port_conflict) {
    my @domains;
    COUNT:
    for my $n ( 1 .. 100) {
        my $domain = $BASE->clone(name => new_domain_name, user => user_admin, memory => 128*1024);
        push @domains,($domain);
        $domain->start(user => user_admin, remote_ip => '2.3.4.'.$n);
        delete_request('set_time','enforce_limits');
        wait_request( debug => 0 );
        for my $d (@{$domain->info(user_admin)->{hardware}->{display}}) {
            last COUNT if $d->{port} >= $port_conflict;
        }
    }
    my $req;
    for ( 1 .. 100 ) {
        $req = Ravada::Request->refresh_machine_ports(uid => user_admin->id
            ,id_domain => $domain1->id
            ,_force => 1
        );
        last if $req;
        sleep 1;
    }
    wait_request( debug => 0 );

    return @domains;
}

###############################################################################

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
    is(user_admin->can_grant(),1) or die user_admin->name." ".user_admin->id;
    clean();
    is(user_admin->can_grant(),1) or die user_admin->name." ".user_admin->id;

    $USER = create_user(new_domain_name(),"bar");

    for my $vm_name (reverse vm_names() ) {

        diag("Testing $vm_name VM $db");
        my $CLASS= "Ravada::VM::$vm_name";

        my $vm;

        $TLS = 0;
        eval { $vm = rvd_back->search_vm($vm_name) };
        $TLS = 1 if check_libvirt_tls() && $vm_name eq 'KVM';

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

          test_display_conflict_next($vm);
      }
    }
}

end();
done_testing();
