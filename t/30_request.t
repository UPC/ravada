use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::Moose::More;
use Test::More;# tests => 82;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $ravada;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

init();

my $RVD_BACK = rvd_back();# $test->connector , 't/etc/ravada.conf');
my $USER = create_user("foo","bar", 1);
$RVD_BACK = undef;

my @ARG_CREATE_DOM = (
        id_owner => $USER->id
        ,disk => 1024 * 1024
);

$Ravada::CAN_FORK = 0;

#######################################################################

sub test_empty_request {
    my $request = $ravada->request();
    ok($request);
}

sub test_remove_domain {
    my $vm = shift;
    my $name = shift;

    my $domain;
    $domain = $name if ref($name);
    $domain = $vm->search_domain($name,1);

    if ($domain) {
#        diag("Removing domain $name");
        eval { $domain->remove(user_admin()) };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        # TODO check remove files base

    }
    $domain = $vm->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name");

}

sub test_req_start_domain {
    my $vm_name = shift;
    my $name = shift;

    $USER->mark_all_messages_read();
    test_unread_messages($USER,0, "[$vm_name] start domain $name");

    my $req = Ravada::Request->start_domain( 
        name => $name
        ,uid => $USER->id
        ,remote_ip => '127.0.0.1'
    );
    ok($req);
    ok($req->status);
    $ravada->_process_requests_dont_fork();
    $ravada->_wait_pids();
    wait_request($req);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done") 
            or return ;
    ok(!$req->error,"Error ".$req->error." creating domain ".$name) 
            or return;

    my $n_expected = 1;
    test_unread_messages($USER, $n_expected, "[$vm_name] create domain $name");

}

sub test_req_create_domain_iso {
    my $vm_name = shift;

    my $name = new_domain_name();
#    diag("Requesting create domain $name");

    $USER->mark_all_messages_read();
    test_unread_messages($USER,0, "[$vm_name] create domain $name");

    my $req;
    eval { $req = Ravada::Request->create_domain( 
        name => $name
        ,id_iso => search_id_iso('Alpine')
        ,disk => 1024 * 1024
        ,@ARG_CREATE_DOM
        );
    };
    ok(!$@,"Expecting \$@=''  , got='".($@ or '')."'") or return;
    ok($req);
    ok($req->status);
    ok($req->args('id_owner'));

    
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"$$ Status of request is ".$req->status." it should be requested");

    wait_request(request => $req, debug => 0);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done") or return ;
    ok(!$req->error,"Error ".$req->error." creating domain ".$name) or return ;

    my $n_expected = 1;
    test_unread_messages($USER, $n_expected, "[$vm_name] create domain $name");

    my $req2 = Ravada::Request->open($req->id);
    ok($req2->{id} == $req->id,"iso req2->{id} = ".$req2->{id}." , expecting ".$req->id);

    my $vm = $ravada->search_vm($vm_name);
    my $domain =  $vm->search_domain($name);

    ok($domain,"[$vm_name] I can't find domain $name");

    $USER->mark_all_messages_read();
    return $domain;
}

sub test_req_create_base {

    my $name = new_domain_name();

    my $req = Ravada::Request->create_domain( 
        name => $name
        ,disk => 1024 * 1024
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

    wait_request();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"I can't find domain $name") && do {
        $domain->prepare_base(user_admin);
        ok($domain && $domain->is_base,"Domain $name should be base");
    };
    return $domain;
}


sub test_req_remove_domain_obj {
    my $vm = shift;
    my $domain = shift;

    my $domain_name = $domain->name;
    my $req = Ravada::Request->remove_domain(name => $domain->name, uid => user_admin->id);
    $ravada->_process_requests_dont_fork();

    ok($req->status eq 'done',ref($vm)." status ".$req->status." should be done");
    ok(!$req->error ,ref($vm)." error : '".$req->error."' , should be ''");
    my $domain2;
    eval { $domain2 =  $vm->search_domain($domain->name) };
    ok(!$domain2,ref($vm)." Domain $domain_name should be removed ");


}

sub test_req_remove_domain_name {
    my $vm = shift;
    my $name = shift;

    my $req = Ravada::Request->remove_domain(name => $name, uid => user_admin()->id);

    rvd_back->_process_all_requests_dont_fork();

    ok($req->status eq 'done',ref($vm)." status ".$req->status." should be done");
    ok(!$req->error ,ref($vm)." error : '".$req->error."' , should be ''");

    my $domain =  $vm->search_domain($name);
    ok(!$domain,ref($vm)." Domain $name should be removed") or exit;
    ok(!$req->error,"Error ".$req->error." removing domain $name");

}

sub test_unread_messages {
    my ($user, $n_unread, $test) = @_;
    confess "Missing test name" if !$test;

    my @messages = $user->unread_messages();

    ok(scalar @messages == $n_unread,"$test: Expecting $n_unread unread messages , got "
        .scalar@messages." ".Dumper(\@messages)) or confess;

    $user->mark_all_messages_read();
}

sub test_requests_by_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = create_domain($vm_name, user_admin);
    ok($domain,"Expecting new domain created") or exit;

    my $req1 = Ravada::Request->prepare_base(uid => user_admin->id, id_domain => $domain->id);
    is($domain->list_requests,1) or die Dumper([$domain->list_requests]);

    my $req2 = Ravada::Request->remove_base(uid => user_admin->id, id_domain => $domain->id);
    ok($domain->list_requests == 2);

    my $clone_name = new_domain_name();
    my $req_clone = Ravada::Request->create_domain (
        name => $clone_name
        ,id_owner => user_admin->id
        ,id_base => $domain->id
        ,vm => $vm_name
    );

    my $req4 = Ravada::Request->prepare_base(uid => user_admin->id, id_domain => $domain->id);
    is($domain->list_requests,3,Dumper([map { $_->{command} } $domain->list_requests]));

    rvd_back->_process_all_requests_dont_fork();
    wait_request();

    is($req1->status , 'done');
    is($req2->status , 'done');

    is($req4->status , 'done');
    is($domain->is_base,1) or exit;

    my $req4b = Ravada::Request->open($req4->id);
    is($req4b->status , 'done') or exit;

    rvd_back->_process_all_requests_dont_fork();
    like($req_clone->status,qr(done)) or exit;
    is($req_clone->error, '') or exit;

    my $clone = $vm->search_domain($clone_name);
    ok($clone,"Expecting domain $clone_name created") or exit;
}

sub test_req_many_clones {
    my ($vm, $base) = @_;

    is(scalar $base->clones , 0, Dumper([$base->clones]));

    my ($name1, $name2) = (new_domain_name, new_domain_name);
    my $req1 = Ravada::Request->clone(
        name => $name1
        ,uid => user_admin->id
        ,id_domain => $base->id
    );
    my $req2 = Ravada::Request->clone(
        name => $name2
        ,uid => user_admin->id
        ,id_domain => $base->id
    );

    rvd_back->_process_all_requests_dont_fork();
    rvd_back->_process_all_requests_dont_fork();

    is($req1->status, 'done');
    is($req1->error, '');

    is($req2->status, 'done');
    is($req2->error, '');

    my $clone1 = rvd_back->search_domain($name1);
    ok($clone1,"Expecting clone $name1 created");

    my $clone2 = rvd_back->search_domain($name2);
    ok($clone2,"Expecting clone $name2 created");

    $clone1->remove(user_admin) if $clone1;
    $clone2->remove(user_admin) if $clone2;

    is(scalar $base->clones , 0, Dumper([$base->clones]));
}

sub test_force() {
    my $req = Ravada::Request->refresh_vms(uid => user_admin->id);
    ok($req);
    wait_request( debug => 0);
    is($req->error, '') or exit;

    my $req3 = Ravada::Request->refresh_vms(uid => user_admin->id);
    ok($req3);
    is($req3->id,$req->id) or exit;
    wait_request( debug => 0);

    my $req2 = Ravada::Request->refresh_vms(uid => user_admin->id, _force => 1);
    ok($req2);
    isnt($req2->id,$req->id);
    wait_request( debug => 0);

}

sub test_dupe_open_exposed($vm) {
    my $req1 = Ravada::Request->open_exposed_ports(
        id_domain => 1
        ,uid => user_admin->id
    );
    ok($req1);

    my $req2 = Ravada::Request->open_exposed_ports(
        id_domain =>2
        ,uid => user_admin->id
    );
    ok($req2);
    isnt($req2->id, $req1->id) or exit;

    delete_request($req1,$req2);

}

################################################
eval { $ravada = rvd_back () };

ok($ravada,"I can't launch a new Ravada");# or exit;
remove_old_domains();
remove_old_disks();

test_force();

for my $vm_name ( vm_names() ) {
    my $vm;
    eval {
        $vm= $ravada->search_vm($vm_name)  if $ravada;
        @ARG_CREATE_DOM = ( id_iso => search_id_iso('alpine'), vm => $vm_name, id_owner => $USER->id , disk => 1024 * 1024 )       if $vm;
    };

    SKIP: {
        my $msg = "SKIPPED: No $vm_name found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED $vm_name: Test must run as root";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;
    
        diag("Testing $vm_name requests with ".(ref $vm or '<UNDEF>'));
    
        test_dupe_open_exposed($vm);
        test_requests_by_domain($vm_name);
        my $domain_iso0 = test_req_create_domain_iso($vm_name);
        test_req_remove_domain_obj($vm, $domain_iso0)         if $domain_iso0;
    
        my $domain_iso = test_req_create_domain_iso($vm_name);
        test_req_remove_domain_name($vm, $domain_iso->name)  if $domain_iso;
    
        my $domain_base = test_req_create_base($vm);
        if ($domain_base) {
            $domain_base->is_public(1);
            is ($domain_base->_vm->readonly, 0) or next;

            my $domain_clone = $domain_base->clone(user => $USER, name => new_domain_name);
            $domain_clone = Ravada::Domain->open($domain_clone->id);
            meta_ok($domain_clone,'Ravada::Domain::KVM');
            does_ok($domain_clone, 'Ravada::Domain');
            role_wraps_after_method_ok 'Ravada::Domain',('remove');
            test_req_start_domain($vm,$domain_clone->name);
            $domain_clone->remove($USER);
            is(scalar @{rvd_front->list_domains( id => $domain_clone->id)}, 0) or exit;

            test_req_many_clones($vm, $domain_base);
            test_req_remove_domain_name($vm, $domain_base->name);
        }

    };
}

end();
done_testing();
