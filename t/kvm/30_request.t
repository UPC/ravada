use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::Request');

my $BACKEND = 'KVM';

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $RAVADA;
my $VMM;
my $CONT = 0;
my $USER;

sub test_req_prepare_base {
    my $name = shift;

    my $domain0 =  $RAVADA->search_domain($name);
    ok(!$domain0->is_base,"Domain $name should not be base");

    my $req = Ravada::Request->prepare_base(id_domain => $domain0->id, uid => $USER->id);
    $RAVADA->_process_all_requests_dont_fork();

    ok($req->status('done'),"Request should be done, it is".$req->status);
    ok(!$req->error(),"Request error ".$req->error);

    my $domain =  $RAVADA->search_domain($name);
    ok($domain->is_base,"Domain $name should be base");
    ok(scalar $domain->list_files_base," Domain $name should have files_base, got ".
        scalar $domain->list_files_base);

}

sub test_remove_domain {
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $VMM->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove($USER) };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        for my $file ( $domain->list_files_base ) {
            ok(! -e $file,"Image file $file should be removed");
        }
    }
    $domain = $RAVADA->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;

}

sub test_dont_remove_father {
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $VMM->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove($USER) };
        ok($@ , "Error removing domain $name with clones should not be allowed");

        for my $file ( $domain->list_files_base ) {
            ok( -e $file,"Image file $file should not be removed") or exit;
        }


    }
    $domain = $RAVADA->search_domain($name,1);
    ok($domain, "Domain $name with clones should not be removed");

}


sub test_req_clone {
    my $domain_father = shift;
    my $name = new_domain_name();#_new_name();

    diag("requesting create domain $name, cloned from ".$domain_father->name);
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_base => $domain_father->id
       ,id_owner => $USER->id
        ,vm => $BACKEND
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");


    $RAVADA->_process_requests_dont_fork();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $RAVADA->search_domain($name);

    ok($domain,"I can't find domain $name");

    my $ref_expected = 'Ravada::Domain::KVM';
    ok(ref $domain && ref $domain eq $ref_expected
        ,"Domain $name ref not $ref_expected , got ".ref($domain)) or exit;
    return $domain;

}

sub test_req_create_domain_iso {
    my $name = new_domain_name();

    diag("requesting create domain $name");
    my $req = Ravada::Request->create_domain( 
            name => $name
         ,id_iso => 1
       ,id_owner => $USER->id
             ,vm => $BACKEND
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $RAVADA->_process_requests_dont_fork();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error '".$req->error."' creating domain ".$name);

    my $domain =  $RAVADA->search_domain($name);

    ok($domain,"I can't find domain $name");
    return $domain;
}

sub test_force_kvm {
    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_iso => 1
      ,id_owner => $USER->id
        ,vm => 'kvm'
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $RAVADA->_process_requests_dont_fork();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $RAVADA->search_domain($name);

    ok($domain,"I can't find domain $name");

    my $vm = $RAVADA->search_vm('kvm');
    my $domain2 = $ vm->search_domain($name);
    ok($domain2,"I can't find $name in the KVM backend");
    return $domain;

}

#########################################################################
eval { $RAVADA = rvd_back( $test->connector , 't/etc/ravada.conf') };
$USER = create_user('foo','bar')    if $RAVADA;

ok($RAVADA,"I can't launch a new Ravada");# or exit;

my ($vm_kvm);
eval { $vm_kvm = $RAVADA->search_vm('kvm')  if $RAVADA };

SKIP: {
    my $msg = "SKIPPED: No KVM virtual machines manager found";
    if ($vm_kvm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm_kvm = undef;
    }

    diag($msg) if !$vm_kvm ;
    skip($msg,10) if !$vm_kvm;

    $VMM = $vm_kvm;

    remove_old_domains();
    remove_old_disks();

    {
        my $domain = test_req_create_domain_iso();

        if ($domain ) {
            test_req_prepare_base($domain->name);
            my $domain_clon = test_req_clone($domain);
            test_dont_remove_father($domain->name);
            test_remove_domain($domain_clon->name);
            test_remove_domain($domain->name);
        }
    }

    {
        my $domain = test_force_kvm();
        test_remove_domain($domain->name)       if $domain;
    }
}

remove_old_domains();
remove_old_disks();

done_testing();
