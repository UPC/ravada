use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my $ravada;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

my @ARG_CREATE_DOM = (
        id_iso => 1
);


#######################################################################

sub test_empty_request {
    my $request = $ravada->request();
    ok($request);
}

sub test_remove_domain {
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $ravada->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove() };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        ok(! -e $domain->file_base_img ,"Image file was not removed "
                    . $domain->file_base_img )
                if  $domain->file_base_img;

    }
    $domain = $ravada->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;

}

sub test_req_create_domain_iso {

    my $name = $DOMAIN_NAME."_iso";
    diag("Requesting create domain $name");
    my $req = Ravada::Request->create_domain( 
        name => $name
        ,@ARG_CREATE_DOM
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->process_requests();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"I can't find domain $name");
    return $domain;
}

sub test_req_create_base {

    my $name = $DOMAIN_NAME."_base";
    my $req = Ravada::Request->create_domain( 
        name => $name
        ,@ARG_CREATE_DOM
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->process_requests();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"I can't find domain $name") && do {
        $domain->prepare_base();
        ok($domain && $domain->is_base,"Domain $name should be base");
    };
    return $domain;
}


sub test_req_remove_domain_obj {
    my $domain = shift;

    my $req = Ravada::Request->remove_domain($domain);
    $ravada->process_requests();

    my $domain2 =  $ravada->search_domain($domain->name);
    ok(!$domain2,"Domain ".$domain->name." should be removed");
    ok(!$req->error,"Error ".$req->error." removing domain ".$domain->name);

}

sub test_req_remove_domain_name {
    my $name = shift;

    my $req = Ravada::Request->remove_domain($name);

    $ravada->process_requests();

    my $domain =  $ravada->search_domain($name);
    ok(!$domain,"Domain $name should be removed");
    ok(!$req->error,"Error ".$req->error." removing domain $name");

}

sub test_list_vm_types {
    my $req = Ravada::Request->list_vm_types();
    $ravada->process_requests();
    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".($req->error or '')." requesting VM types ");

    my $result = $req->result();
    ok(ref $result eq 'ARRAY',"Expecting ARRAY , got ".ref($result));

}

sub remove_old_disks {
    my ($name) = $0 =~ m{.*/(.*)\.t};

    my $vm = $ravada->search_vm('kvm');
    diag("remove old disks");
    return if !$vm;
    ok($vm,"I can't find a KVM virtual manager");

    my $dir_img = $vm->dir_img();
    ok($dir_img," I cant find a dir_img in the KVM virtual manager") or return;

    for my $count ( 0 .. 10 ) {
        my $disk = $dir_img."/$name"."_$count.img";
        if ( -e $disk ) {
            unlink $disk or die "I can't remove $disk";
        }
    }
    for (qw(iso base)) {
        my $disk = $dir_img."/$name".'_'."$_.img";
        unlink $disk or die "I can't remove $disk"
            if -e $disk;
    }

    $vm->storage_pool->refresh();
}


################################################
eval { $ravada = Ravada->new(connector => $test->connector) };

ok($ravada,"I can't launch a new Ravada");# or exit;

my ($vm_kvm, $vm_lxc);
eval { $vm_kvm = $ravada->search_vm('kvm')  if $ravada;
    @ARG_CREATE_DOM = ( id_iso => 1, vm => 'kvm' )       if $vm_kvm;
};
eval { $vm_lxc = $ravada->search_vm('lxc')  if $ravada;
    @ARG_CREATE_DOM = ( id_template => 1, vm => 'LXC' )  if $vm_lxc;
};

SKIP: {
    my $msg = "SKIPPED: No KVM nor LXC virtual managers found";
    diag($msg) if !$vm_kvm && !$vm_lxc;
    skip($msg,10) if !$vm_kvm && !$vm_lxc;

    diag("Testing requests with ".(ref $ravada->vm->[0] or '<UNDEF>'));
    test_remove_domain($DOMAIN_NAME."_iso");
    test_remove_domain($DOMAIN_NAME."_base");
    remove_old_disks();

    {
    my $domain = test_req_create_domain_iso();
    test_req_remove_domain_obj($domain)         if $domain;
    }

    {
    my $domain = test_req_create_domain_iso();
    test_req_remove_domain_name($domain->name)  if $domain;
    }

    {
    my $domain = test_req_create_base();
    test_req_remove_domain_name($domain->name)  if $domain;
    }


    test_remove_domain($DOMAIN_NAME."_iso");

    test_list_vm_types();
};

done_testing();
