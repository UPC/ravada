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

my @VMS = vm_names();
init($test->connector);
my $USER = create_user("foo","bar");

#######################################################

sub test_domain_no_password {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $net = Ravada::Network->new(address => '127.0.0.1/32');

    ok(!$net->requires_password);
    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start(user => $USER, remote_ip => '127.0.0.1');

    my $password = $domain->spice_password();
    is($password,undef
        ,"Expecting no password, got '".($password or '')."'");

    $domain->shutdown_now($USER);
    for ( 1 .. 10 ) {
        sleep 1;
        last if !$domain->is_active();
    }
    is($domain->is_active,0) or return;

    my $net2 = Ravada::Network->new(address => '10.0.0.1/32');
    ok(!$net2->requires_password,"Expecting net requires password ");

    $domain->start(user => $USER, remote_ip => '10.0.0.1');

    my $vm2 = rvd_back->search_vm($vm_name);
    my $domain2 = $vm2->search_domain($domain->name);
    $password = $domain2->spice_password();
    is($password,undef,"Expecting no password, got '".($password or '')."'");

    $password = $domain->spice_password();
    is($password,undef,"Expecting no password, got '".($password or '')."'")   or exit;

    my $domain_f = rvd_front()->search_domain($domain->name);
    my $password_f;
    eval { $password_f = $domain_f->spice_password() };
    is($@,'');
    is($password_f , $password,"Expecting password : '".($password or '')."'"
                                ." got : '".($password_f or '')."'");
    $domain->shutdown_now($USER)    if $domain->is_active();
}

sub test_domain_password2 {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $net = Ravada::Network->new(address => '127.0.0.1/32');

    ok(!$net->requires_password) or return;
    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start(user => $USER, remote_ip => '127.0.0.1');

    my $password = $domain->spice_password();
    is($password,undef
        ,"Expecting no password, got '".($password or '')."'");

    $domain->shutdown_now($USER);
    for ( 1 .. 10 ) {
        sleep 1;
        last if !$domain->is_active();
    }
    is($domain->is_active,0) or return;

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

    my $domain_f = rvd_front()->search_domain($domain->name);
    my $password_f;
    eval { $password_f = $domain_f->spice_password() };
    is($@,'');
    is($password_f , $password,"Expecting password : '".($password or '')."'"
                                ." got : '".($password_f or '')."'");
    $domain->shutdown_now($USER);
    return $domain;
}

sub test_domain_password1 {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $net2 = Ravada::Network->new(address => '10.0.0.1/32');

    ok($net2->requires_password,"Expecting net requires password ")
        or return;
    my $domain = $vm->create_domain( name => new_domain_name
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start(user => $USER, remote_ip => '10.0.0.1');

    my $vm2 = rvd_back->search_vm($vm_name);
    my $domain2 = $vm2->search_domain($domain->name);
    my $password = $domain2->spice_password();
    like($password,qr/./,"Expecting a password, got '".($password or '')."'");

    $password = $domain->spice_password();
    like($password,qr/./,"Expecting a password, got '".($password or '')."'");

    my $domain_f = rvd_front()->search_domain($domain->name);
    my $password_f;
    eval { $password_f = $domain_f->spice_password() };
    ok(!$@, "Expecting no error, got : '".($@ or '')."'");
    is($password_f , $password,"Expecting password : '".($password or '')."'"
                                ." got : '".($password_f or '')."'");

    $domain->shutdown_now($USER);
    return $domain;
}

sub test_any_network_password {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    add_network_10(0);
    add_network_any(1);

    my $domain = $vm->create_domain( name => new_domain_name
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start(user => $USER, remote_ip => '127.0.0.1');

    my $password = $domain->spice_password();
    is($password, undef ,"Expecting no password, got '".($password or '')."'") or exit;
    $domain->shutdown_now($USER);

    $domain->start(user => $USER, remote_ip => '10.0.0.1');

    $password = $domain->spice_password();
    is($password, undef ,"Expecting no password, got '".($password or '')."'");
    $domain->shutdown_now($USER);

    $domain->start(user => $USER, remote_ip => '1.2.3.4');

    $password = $domain->spice_password();
    like($password,qr/./,"Expecting a password, got '".($password or '')."'");
    $domain->shutdown_now($USER);

}

sub test_any_network_password_hybernate{
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    add_network_10(0);
    add_network_any(1);

    my $domain = $vm->create_domain( name => new_domain_name
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start(user => $USER, remote_ip => '127.0.0.1');

    my $password = $domain->spice_password();
    is($password, undef ,"Expecting no password, got '".($password or '')."'");

    $domain->hibernate($USER);
    is($domain->is_active(),0);
    is($domain->is_hibernated(),1,"Domain should be hybernated");

    eval { $domain->start(user => $USER, remote_ip => '10.0.0.1') };
    ok(!$@,"Expecting no error start hybernated domain, got : '".($@ or '')."'");
    is($domain->is_active(),1,"Expecting domain active");

    my $password2 = $domain->spice_password();
    is($password2, undef ,"Expecting no password, got '".($password2 or '')."' after hybernate");

    is($password2,$password);

    # create another domain to start from far away
    $domain = $vm->create_domain( name => new_domain_name
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    eval {
        $domain->start($USER)   if !$domain->is_active;
        for ( 1 .. 10 ){
            last if $domain->is_active;
            sleep 1;
        }
        $domain->hybernate($USER);
    };
    ok(!$@,"Expecting no error after \$domain->hybernate, got : '".($@ or '')."'");
    is($domain->is_active(),0,"Domain should not be active, got :".$domain->is_active);
    is($domain->is_hibernated(),1,"Domain should be hybernated");

    eval { $domain->start(user => $USER, remote_ip => '1.2.3.4') };
    ok(!$@,"Expecting no error after \$domain->start, got : '".($@ or '')."'");

    eval { $password = $domain->spice_password() };
    is($@,'',"Expecting no error after \$domain->spice_password hybernate/start");
    is($password, undef ,"Expecting no password, got '".($password2 or '')."' after hybernate");
    is($domain->spice_password,$password);

    $domain->shutdown_now($USER);
    is($domain->is_active(),0);

    eval { $domain->start(user => $USER, remote_ip => '1.2.3.4') };
    ok(!$@,"Expecting no error after \$domain->start, got : '".($@ or '')."'");
    eval { $password = $domain->spice_password() };
    like($password,qr/./,"Expecting a password, got '".($password2 or '')."'");

    $domain->hybernate($USER);
    is($domain->is_hibernated(),1,"Domain should be hybernated");

    eval { $password2 = $domain->spice_password() };
    is($@,'',"Expecting no error after \$domain->spice_password hybernate/start");
    like($password2,qr/./,"Expecting a password, got '".($password2 or '')."'");

    is($password2,$password);

    eval { $domain->start(user => $USER, remote_ip => '1.2.3.4') };
    ok(!$@,"Expecting no error after \$domain->start, got : '".($@ or '')."'");

    my $password3;
    eval { $password3 = $domain->spice_password() };
    like($password3,qr/./,"Expecting a password, got '".($password3 or '')."'");
    is($password3,$password2);

    $domain->shutdown_now($USER)    if $domain->is_active;

}

sub add_network_10 {
    my $requires_password = shift;
    $requires_password = 1 if !defined $requires_password;

    my $sth = $test->connector->dbh->prepare(
        "DELETE FROM networks where address='10.0.0.0/24'"
    );
    $sth->execute;
    $sth = $test->connector->dbh->prepare(
        "INSERT INTO networks (name,address,all_domains,requires_password)"
        ."VALUES('10','10.0.0.0/24',1,?)"
    );
    $sth->execute($requires_password);
}

sub add_network_any {
    my $requires_password = shift;
    $requires_password = 1 if !defined $requires_password;

    my $sth = $test->connector->dbh->prepare(
        "DELETE FROM networks where address='0.0.0.0/0'"
    );
    $sth->execute;

    $sth = $test->connector->dbh->prepare(
        "INSERT INTO networks (name,address,all_domains,requires_password,n_order)"
        ."VALUES('any','0.0.0.0/0',1,?,999)"
    );
    $sth->execute($requires_password);
}

sub remove_network_10 {
    my $sth = $test->connector->dbh->prepare(
        "DELETE FROM networks where name='10'"
    );
    $sth->execute();

}

sub remove_network_default {
    my $sth = $test->connector->dbh->prepare(
        "DELETE FROM networks where name='default'"
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

    add_network_10();
    my $domain1 = test_domain_password1($vm_name);
    my $domain2 = test_domain_password2($vm_name);
    remove_network_10();

    $domain1->start(user => $USER, remote_ip => '10.0.0.1');
    my $password = $domain1->spice_password();
    ok($password,"Expecting password, got : '".($password or '')."'");

    remove_network_default();
    $domain1->shutdown_now($USER);
    $domain1->start(user => $USER, remote_ip => '10.0.0.1');
    $password = $domain1->spice_password();

    is($password,undef,"Expecting no password, got : '".($password or '')."'");
    $domain1->shutdown_now($USER)   if $domain1->is_active;

    $domain2->start(user => $USER, remote_ip => '10.0.0.1');
    $password = $domain2->spice_password();
    is($password,undef,"Expecting no password, got : '".($password or '')."'");
    $domain2->shutdown_now($USER)   if $domain2->is_active;

    test_domain_no_password($vm_name);

    test_any_network_password($vm_name);
    test_any_network_password_hybernate($vm_name);
}

clean();

done_testing();
