use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

my $BASE_NAME = "zz-test-base-alpine";
my $BASE;

##############################################################

sub _import_base($vm) {
    if ($vm->type eq 'KVM') {
        $BASE = rvd_back->search_domain($BASE_NAME);
        $BASE = import_domain($vm->type, $BASE_NAME, 1) if !$BASE;
        confess "Error: domain $BASE_NAME is not base" unless $BASE->is_base;

        confess "Error: domain $BASE_NAME has exported ports that conflict with the tests"
        if $BASE->list_ports;
    } else {
        $BASE = create_domain($vm);
        Ravada::Request->prepare_base(uid => user_admin->id
            ,id_domain => $BASE->id
        );
        wait_request();
    }
}

sub test_expose_port($vm) {

    my $req_clone = Ravada::Request->clone(
        uid => user_admin->id
        ,id_domain => $BASE->id
        ,name => new_domain_name()
    );
    wait_request();
    my ($domain0) = $BASE->clones();
    my $domain = Ravada::Domain->open($domain0->{id});
    my ($internal_port, $name_port) = (22, 'ssh');
    $domain->expose(
        port => $internal_port
        , name => $name_port
        , restricted => 1
    );

    my $remote_ip1 = '10.0.0.1';
    my $remote_ip2 = '10.0.0.2';
    my $local_ip = $vm->ip;

    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip1
    );
    wait_request();

    my $internal_ip = _wait_ip2($vm->type, $domain) or die "Error: no ip for ".$domain->name;

    my ($port) = $domain->list_ports();

    Ravada::Request->open_exposed_ports(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,remote_ip => $remote_ip2
    );
    wait_request();

    my @out_nat = split /\n/, `iptables-save -t nat`;
    my @prerouting= (grep /--to-destination $internal_ip:22/, @out_nat);
    is(scalar(@prerouting),1);
    my @out= split /\n/, `iptables-save`;
    my @forward = (grep /-s $remote_ip2\/32 -d $internal_ip.* --dport 22.*-j ACCEPT/, @out);
    is(scalar(@forward),1,"-s $remote_ip2\/32 -d $internal_ip.* --dport 22.*-j ACCEPT") or die Dumper([grep /FORWARD/,@out]);
}

sub _wait_ip2($vm_name, $domain) {
    confess if !ref($domain) || ref($domain) !~ /Domain/;
    $domain->start(user => user_admin, remote_ip => '1.2.3.5') unless $domain->is_active();
    for ( 1 .. 30 ) {
        return $domain->ip if $domain->ip;
        diag("Waiting for ".$domain->name. " ip") if !(time % 10);
        sleep 1;
    }
    confess "Error : no ip for ".$domain->name;
}

##############################################################

clean();
flush_rules() if !$<;

for my $vm_name ( reverse vm_names() ) {

SKIP: {
          my $vm = rvd_back->search_vm($vm_name);

          my $msg = "SKIPPED test: No $vm_name VM found ";
          if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
          }

          diag($msg)      if !$vm;
          skip $msg,10    if !$vm;

          _import_base($vm);
          test_expose_port($vm);
      }
}

flush_rules() if !$<;
end();
done_testing();
