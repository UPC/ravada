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
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

#######################################################

sub search_password {
}

sub test_domain_password {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $net = Ravada::Network->new(address => '127.0.0.1/32');

    ok(!$net->requires_password) or return;
    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , id_iso => 1 , id_owner => $USER->id);

    $domain->prepare_base($USER);

    $domain->start(user => $USER, remote_ip => '127.0.0.1');

    my $password = search_password($domain);
    is($password,undef
        ,"Expecting no password, got '".($password or '')."'");

    $domain->shutdown_now($USER);
    for ( 1 .. 10 ) {
        sleep 1;
        last if !$domain->is_active();
    }
    is($domain->is_active,0) or return;
    add_network_10();

    my $net2 = Ravada::Network->new(address => '10.0.0.1/32');
    ok($net2->requires_password,"Expecting net requires password ")
        or return;

    $domain->start(user => $USER, remote_ip => '10.0.0.1');

    my $vm2 = rvd_back->search_vm($vm_name);
    my $domain2 = $vm2->search_domain($domain->name);
    $password = $domain2->spice_password();
    like($password,qr/./,"Expecting a password, got '".($password or '')."'");

    $password = $domain->spice_password();
    like($password,qr/./,"Expecting a password, got '".($password or '')."'")   or exit;

    return $domain;
}

sub add_network_10 {
    my $sth = $test->connector->dbh->prepare(
        "INSERT INTO networks (name,address,all_domains,requires_password)"
        ."VALUES('10','10.0.0.0/24',1,1)"
    );
    $sth->execute();
}

#######################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    my $domain = test_domain_password($vm_name);
}

clean();

done_testing();
