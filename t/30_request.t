use warnings;
use strict;

use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $ravada;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

my $RVD_BACK = rvd_back( $test->connector , 't/etc/ravada.conf');
my $USER = create_user("foo","bar");

my @ARG_CREATE_DOM = (
        id_iso => 1
        ,id_owner => $USER->id
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
        eval { $domain->remove(user_admin()) };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        ok(! -e $domain->file_base_img ,"Image file was not removed "
                    . $domain->file_base_img )
                if  $domain->file_base_img;

    }
    $domain = $ravada->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;

}

sub wait_request {
    my $req = shift;
    my $status = '';
    for ( 1 .. 100 ) {
        last if $req->status eq 'done';
        next if $req->status eq $status;
        diag("Request ".$req->command." ".$req->status);
        $status=$req->status;
        sleep 1;
    }

}
sub test_req_create_domain_iso {

    my $name = new_domain_name();
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

    $ravada->_process_requests_dont_fork();

    wait_request($req);
    $ravada->_wait_pids();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $req2 = Ravada::Request->open($req->id);
    ok($req2->{id} == $req->id,"req2->{id} = ".$req2->{id}." , expecting ".$req->id);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"I can't find domain $name");
    return $domain;
}

sub test_req_create_base {

    my $name = new_domain_name();

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

    $ravada->_process_requests_dont_fork();

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

    my $req = Ravada::Request->remove_domain(name => $domain->name, uid => user_admin->id);
    $ravada->_process_requests_dont_fork();

    my $domain2 =  $ravada->search_domain($domain->name);
    ok(!$domain2,"Domain ".$domain->name." should be removed");
    ok(!$req->error,"Error ".$req->error." removing domain ".$domain->name);

}

sub test_req_remove_domain_name {
    my $name = shift;

    my $req = Ravada::Request->remove_domain(name => $name, uid => user_admin()->id);

    $ravada->_process_requests_dont_fork();

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

################################################
eval { $ravada = Ravada->new(connector => $test->connector) };

ok($ravada,"I can't launch a new Ravada");# or exit;

my ($vm_kvm, $vm_lxc);
eval { $vm_kvm = $ravada->search_vm('kvm')  if $ravada;
    @ARG_CREATE_DOM = ( id_iso => 1, vm => 'kvm', id_owner => 1 )       if $vm_kvm;
};
eval { $vm_lxc = $ravada->search_vm('lxc')  if $ravada;
    @ARG_CREATE_DOM = ( id_template => 1, vm => 'LXC', id_owner => 1 )  if $vm_lxc;
};

SKIP: {
    my $msg = "SKIPPED: No KVM nor LXC virtual managers found";
    diag($msg) if !$vm_kvm && !$vm_lxc;
    skip($msg,10) if !$vm_kvm && !$vm_lxc;

    diag("Testing requests with ".(ref $ravada->vm->[0] or '<UNDEF>'));
    remove_old_domains();
    remove_old_disks();

    my $domain_iso0 = test_req_create_domain_iso();
    test_req_remove_domain_obj($domain_iso0)         if $domain_iso0;

    my $domain_iso = test_req_create_domain_iso();
    test_req_remove_domain_name($domain_iso->name)  if $domain_iso;

    my $domain_base = test_req_create_base();
    test_req_remove_domain_name($domain_base->name)  if $domain_base;

    test_list_vm_types();
};

done_testing();
