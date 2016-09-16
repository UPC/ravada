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

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my $RAVADA;
my $VMM;
my $CONT = 0;

sub test_req_prepare_base {
    my $name = shift;

    my $domain0 =  $RAVADA->search_domain($name);
    ok(!$domain0->is_base,"Domain $name should not be base");

    my $req = Ravada::Request->prepare_base($name);
    $RAVADA->process_requests();

    my $domain =  $RAVADA->search_domain($name);
    ok($domain->is_base,"Domain $name should be base");

}

sub test_remove_domain {
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $VMM->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove() };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        ok(! -e $domain->file_base_img ,"Image file was not removed "
                    . $domain->file_base_img )
                if  $domain->file_base_img;

    }
    $domain = $RAVADA->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;

}


sub test_req_clone {
    my $domain_father = shift;
    my $name = new_domain_name();#_new_name();

    diag("requesting create domain $name, cloned from ".$domain_father->name);
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_base => $domain_father->id
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


    $RAVADA->process_requests();

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

    $RAVADA->process_requests();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $RAVADA->search_domain($name);

    ok($domain,"I can't find domain $name");
    return $domain;
}

sub test_force_kvm {
    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_iso => 1
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

    $RAVADA->process_requests();

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

sub remove_old_domains {
    my ($name) = $0 =~ m{.*/(.*/.*)\.t};
    $name =~ s{/}{_}g;
    for ( 0 .. 10 ) {
        test_remove_domain($name."_".$_);
    }

}

#########################################################################
eval { $RAVADA = rvd_back( $test->connector) };

ok($RAVADA,"I can't launch a new Ravada");# or exit;

my ($vm_kvm);
eval { $vm_kvm = $RAVADA->search_vm('kvm')  if $RAVADA };

SKIP: {
    my $msg = "SKIPPED: No KVM virtual machines manager found";
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
            test_remove_domain($domain->name);
            test_remove_domain($domain_clon->name);
        }
    }

    {
        my $domain = test_force_kvm();
        test_remove_domain($domain->name)       if $domain;
    }
}

done_testing();
