use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;# tests => 82;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $ravada;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

init($test->connector, 't/etc/ravada.conf');

my $RVD_BACK = rvd_back();# $test->connector , 't/etc/ravada.conf');
my $USER = create_user("foo","bar");
$RVD_BACK = undef;

my @ARG_CREATE_DOM = (
        id_iso => 1
        ,id_owner => $USER->id
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

    my $domain = $name if ref($name);
    $domain = $vm->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
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
    $ravada->process_requests();
    $ravada->_wait_pids();
    wait_request($req);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done") 
            or return ;
    ok(!$req->error,"Error ".$req->error." creating domain ".$name) 
            or return ;
    test_unread_messages($USER,1, "[$vm_name] create domain $name");
    
}

sub test_req_create_domain_iso {
    my $vm_name = shift;

    my $name = new_domain_name();
    diag("Requesting create domain $name");

    $USER->mark_all_messages_read();
    test_unread_messages($USER,0, "[$vm_name] create domain $name");

    my $req;
    eval { $req = Ravada::Request->create_domain( 
        name => $name
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

    $ravada->process_requests();

    $ravada->_wait_pids();
    wait_request($req);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done") or return ;
    ok(!$req->error,"Error ".$req->error." creating domain ".$name) or return ;
    test_unread_messages($USER,1, "[$vm_name] create domain $name");

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
        $domain->prepare_base($USER);
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
        .scalar@messages." ".Dumper(\@messages));

    $user->mark_all_messages_read();
}


################################################
eval { $ravada = Ravada->new(connector => $test->connector) };

ok($ravada,"I can't launch a new Ravada");# or exit;
remove_old_domains();
remove_old_disks();

for my $vm_name ( qw(Void KVM)) {
    my $vm;
    eval {
        $vm= $ravada->search_vm($vm_name)  if $ravada;
        @ARG_CREATE_DOM = ( id_iso => 1, vm => $vm_name, id_owner => $USER->id )       if $vm;
    };

    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }
        skip($msg,10)   if !$vm;
    
        diag("Testing requests with ".(ref $vm or '<UNDEF>'));
    
        my $domain_iso0 = test_req_create_domain_iso($vm_name);
        test_req_remove_domain_obj($vm, $domain_iso0)         if $domain_iso0;
    
        my $domain_iso = test_req_create_domain_iso($vm_name);
        test_req_remove_domain_name($vm, $domain_iso->name)  if $domain_iso;
    
        my $domain_base = test_req_create_base($vm);
        if ($domain_base) {
            test_req_start_domain($vm,$domain_base->name);
            test_req_remove_domain_name($vm, $domain_base->name);
        }
    };
}

remove_old_domains();
remove_old_disks();

done_testing();
