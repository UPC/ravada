use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

use_ok('Ravada::Route');

#######################################################

sub test_domain_no_password {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $net = Ravada::Route->new(address => '127.0.0.1/32');

    ok(!$net->requires_password);
    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , disk => 1024 * 1024
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

    my $net2 = Ravada::Route->new(address => '10.0.0.1/32');
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

    my $net = Ravada::Route->new(address => '127.0.0.1/32');

    ok(!$net->requires_password) or return;
    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , disk => 1024 * 1024
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

    my $net2 = Ravada::Route->new(address => '10.0.0.1/32');
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

sub test_domain_password1($vm_name, $requires_password=1) {
    my $vm = rvd_back->search_vm($vm_name);

    my $net2 = Ravada::Route->new(address => '10.0.0.1/32');

    ok($net2->requires_password,"Expecting net requires password ")
        or return;

    if (!$requires_password) {
        rvd_back->setting("/backend/display_password" => 0);
    }
    my $domain = $vm->create_domain( name => new_domain_name
                , disk => 1024 * 1024
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

    $domain->start(user => $USER, remote_ip => '10.0.0.1');

    my $vm2 = rvd_back->search_vm($vm_name);
    my $domain2 = $vm2->search_domain($domain->name);
    my $password = $domain2->spice_password();
    if ($requires_password) {
        like($password,qr/./,"Expecting a password, got '".($password or '')."'") or die $domain2->name;

        $password = $domain->spice_password();
        like($password,qr/./,"Expecting a password, got '".($password or '')."'");
    } else {
        is($password, undef);
    }


    my $domain_f = rvd_front()->search_domain($domain->name);
    my $password_f;
    eval { $password_f = $domain_f->spice_password() };
    ok(!$@, "Expecting no error, got : '".($@ or '')."'");
    is($password_f , $password,"Expecting password : '".($password or '')."'"
                                ." got : '".($password_f or '')."'");

    my $domain3 = Ravada::Domain->open($domain->id);
    test_password_xml($domain3,$password);

    $domain->shutdown_now($USER);

    # default is display password = 1
    rvd_back->setting("/backend/display_password" => 1);
    return $domain;
}

sub test_password_xml($domain, $exp_password) {
    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description(Sys::Virt::Domain::XML_SECURE));
    my $found = 0;
    for my $graphics ( $xml->findnodes("/domain/devices/graphics") ) {
        next if $graphics->getAttribute('type') ne 'spice';
        $found++;
        is($graphics->getAttribute('passwd'),$exp_password,$domain->name) or exit;
    }
    ok($found,"Expecting a graphics type='spice' found in ".$domain->name);
}


sub test_any_network_password {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    add_network_10(0);
    add_network_any(1);

    my $domain = $vm->create_domain( name => new_domain_name
                , disk => 1024 * 1024
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
                , disk => 1024 * 1024
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
                , disk => 1024 * 1024
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
    is($password, undef,"Expecting password, got '".($password or '')."' after hybernate");
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

    my $sth = connector->dbh->prepare(
        "DELETE FROM networks where address='10.0.0.0/24'"
    );
    $sth->execute;
    $sth = connector->dbh->prepare(
        "INSERT INTO networks (name,address,all_domains,requires_password)"
        ."VALUES('10','10.0.0.0/24',1,?)"
    );
    $sth->execute($requires_password);
}

sub add_network_any {
    my $requires_password = shift;
    $requires_password = 1 if !defined $requires_password;

    my $sth = connector->dbh->prepare(
        "DELETE FROM networks where address='0.0.0.0/0'"
    );
    $sth->execute;

    $sth = connector->dbh->prepare(
        "INSERT INTO networks (name,address,all_domains,requires_password,n_order)"
        ."VALUES('any','0.0.0.0/0',1,?,999)"
    );
    $sth->execute($requires_password);
}

sub remove_network_10 {
    my $sth = connector->dbh->prepare(
        "DELETE FROM networks where name='10'"
    );
    $sth->execute();

}

sub remove_network_default {
    my $sth = connector->dbh->prepare(
        "DELETE FROM networks where name='default'"
    );
    $sth->execute();

}

sub _remove_network {
    my $name = shift;
    my $sth = connector->dbh->prepare(
        "DELETE FROM networks where name=?"
    );
    $sth->execute($name);

}
# When a domain is started in network that requires password, then
# the password won't show in password-less networks.
sub test_reopen {
    my $vm_name = shift;
    my $domain1 = create_domain($vm_name);

    add_network_any(1); # with password
    $domain1->start(user => user_admin
        ,remote_ip => '8.8.8.8'
    );
    my $password1;
    eval { $password1 = $domain1->spice_password };
    is($@,'');
    like($password1,qr'.+');

    my $domain2 = create_domain($vm_name);
    $domain2->start(user => user_admin
        ,remote_ip => '127.0.0.1'
    );
    my $password2;
    eval { $password2 = $domain2->spice_password };
    is($@,'');
    is($password2,undef);

    $domain1->start(user => user_admin
        , remote_ip => '127.0.0.1'
    );
    my $password1b;
    eval { $password1b = $domain1->spice_password };
    is($@,'');
    like($password1b,qr'.+');
    is($password1, $password1b);

    $domain1->remove(user_admin);
    $domain2->remove(user_admin);

    _remove_network('any');
}

#######################################################
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP:{
        skip($msg,10);
    }
    done_testing();
    exit;
}

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
    my $domain1 = test_domain_password1($vm_name, 0);
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

    test_reopen($vm_name);
    test_domain_no_password($vm_name);

    test_any_network_password($vm_name);
    test_any_network_password_hybernate($vm_name);
}

end();

done_testing();
