use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

my $RVD_BACK = rvd_back( $test->connector , 't/etc/ravada.conf');
my $RVD_FRONT = rvd_front( $test->connector , 't/etc/ravada.conf');
my $USER = create_user("foo","bar");

my @ARG_CREATE_DOM = (
        id_iso => 1
        ,id_owner => $USER->id
);


#######################################################################

sub test_empty_request {
    my $request = $RVD_BACK->request();
    ok($request);
}

sub test_unread_messages {
    my ($user, $n_unread, $test) = @_;
    confess "Missing test name" if !$test;

    my @messages = $user->unread_messages();

    ok(scalar @messages == $n_unread,"$test: Expecting $n_unread unread messages , got "
        .scalar@messages." ".Dumper(\@messages));

    $user->mark_all_messages_read();
}

sub test_req_create_domain_iso {
    my $vm_name = shift;

    my $name = new_domain_name();
    diag("Requesting create domain $name");

    $USER->mark_all_messages_read();
    test_unread_messages($USER,0, "[$vm_name] create domain $name");

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

    $RVD_BACK->process_requests();
    wait_request($req);

    $RVD_BACK->_wait_pids();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

#    test_unread_messages($USER,1, "[$vm_name] create domain $name");
    test_message_new_domain($vm_name, $USER);

    my $req2 = Ravada::Request->open($req->id);
    ok($req2->{id} == $req->id,"req2->{id} = ".$req2->{id}." , expecting ".$req->id);

    my $vm = $RVD_FRONT->search_vm($vm_name);
    my $domain =  $vm->search_domain($name);

    ok($domain,"[$vm_name] I can't find domain $name");
    ok(!$domain->is_locked,"Domain $name should not be locked");

    $USER->mark_all_messages_read();

    $domain->_vm->disconnect();
    ok(!$domain->_vm->vm) or exit;
    return $domain;
}

sub test_message_new_domain {
    my ($vm_name, $user) = @_;
    my @messages = $user->unread_messages();
    ok(scalar(@messages) == 1,"Expecting 1 new message , got ".Dumper(\@messages));
    
    my $message = $user->show_message($messages[0]->{id});

    ok($message->{message} && $message->{message} =~ /\w+/
            , "Expecting message content not empty, got ''") or exit;
}

sub test_req_create_domain {

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

    $RVD_BACK->process_requests();
    wait_request($req);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $RVD_FRONT->search_domain($name);

    ok($domain,"Searching for domain $name") or return;
    ok($domain->name eq $name,"Expecting domain name '$name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting domain not base , got: ".$domain->is_base());

    ok(!$domain->_vm->vm) or exit;
    $domain->_vm->disconnect();

    return $domain;
}

sub test_req_prepare_base {
    my $vm_name = shift;
    my $name = shift;

    my $req;
    { 
        my $vm = $RVD_FRONT->search_vm($vm_name);
        my $domain = $vm->search_domain($name);
        ok($domain, "Searching for domain $name, got ".ref($name)) or return;
        ok(!$domain->is_base, "Expecting domain base=0 , got: '".$domain->is_base."'");

        ok(!$domain->_vm->vm);
        $req = Ravada::Request->prepare_base(
            id_domain => $domain->id
            ,uid => $USER->id
        );
        ok($req);
        ok($req->status);

        ok($domain->is_locked,"Domain $name should be locked when preparing base");
    }

    $RVD_BACK->process_requests();
    wait_request($req);
    ok(!$req->error,"Expecting error='', got '".($req->error or '')."'");

    wait_request($req);

    my $vm = $RVD_FRONT->search_vm($vm_name);
    my $domain2 = $vm->search_domain($name);
    ok($domain2->is_base, "Expecting domain base=1 , got: '".$domain2->is_base."'") or exit;
    ok(!$domain2->_vm->vm) or exit;
}

sub test_req_create_from_base {
    my $vm_name = shift;
    my $domain_base = shift;

    diag("create from base");

    my $clone_name = new_domain_name();

    my $req = Ravada::Request->create_domain(
        name => $clone_name
        , vm => $vm_name
        , id_base => $domain_base->id
        , id_owner => $USER->id
    );
    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $RVD_BACK->process_requests(1);
    wait_request($req);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$clone_name);

    my $domain =  $RVD_FRONT->search_domain($clone_name);

    ok($domain,"Searching for domain $clone_name") or return;
    ok($domain->name eq $clone_name
        ,"Expecting domain name '$clone_name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting domain not base , got: ".$domain->is_base());

    ok(!$domain_base->_vm->vm) or exit;
    ok(!$domain->_vm->vm) or exit;
    return $domain;

}

sub test_volumes {
    my ($vm_name, $domain1 , $domain2) = @_;

    diag("test volumes");

    my @volumes1 = $domain1->list_volumes();
    my @volumes2 = $domain2->list_volumes();

    my %volumes1 = map { $_ => 1 } @volumes1;
    my %volumes2 = map { $_ => 1 } @volumes2;

    ok(scalar keys %volumes1 == scalar keys %volumes2
        ,"[$vm_name] Expecting ".scalar(keys %volumes1)." , got ".scalar(keys %volumes2)
        .Dumper(\%volumes1,\%volumes2)) or exit;

}

sub check_files_exist {
    my $vm_name = shift;
    for my $file (@_) {
        ok(-e $file
            ,"[$vm_name] File '$file' , expected exists , got ".(-e $file));
    }
}

sub check_files_removed {
    my $vm_name = shift;
    for my $file (@_) {
        ok(!-e $file
            ,"[$vm_name] File '$file' , expected removed, got ".(-e $file));
    }
}


sub test_req_remove_base {
    my ($vm_name, $domain_base, $domain_clone) = @_;

    diag("remove base");

    ok($domain_base->is_base,"[$vm_name] expecting domain ".$domain_base->id
        ." is base , got ".$domain_base->is_base) or return;

    my @files_base = $domain_base->list_files_base();
    ok(scalar @files_base,"Expecting files base, got none") or return;

    ok(!$domain_base->_vm->vm,"Expecting no vm in base");
    ok(!$domain_clone->_vm->vm,"Expecting no vm in clone");

    my $req = Ravada::Request->remove_base(id_domain => $domain_base->id
        , uid => $USER->id
    );

    ok($req->status eq 'requested');
    $RVD_BACK->process_requests();
    wait_request($req);

    ok($req->status eq 'done', "Expected req->status 'done', got "
                                ."'".$req->status."'");

    ok($req->error =~ /has \d+ clones/i, "[$vm_name] Expected error 'has X clones'"
            .", got : '".$req->error."'");

    check_files_exist(@files_base);
    $domain_clone->remove($USER);
    check_files_exist(@files_base);

    $req->status('requested');

    ok(!$domain_base->_vm->vm);
    ok(!$domain_clone->_vm->vm);

    $RVD_BACK->process_requests();
    wait_request($req);

    ok($req->status eq 'done', "[$vm_name] Expected req->status 'done', got "
                                ."'".$req->status."'");

    ok(!$req->error, "Expected error ''"
            .", got : '".$req->error."'");

    ok(!$domain_base->is_base());
    ok(!$domain_clone->is_base());
    check_files_removed(@files_base);
}

################################################
eval { $RVD_BACK = Ravada->new(connector => $test->connector) };

ok($RVD_BACK,"I can't launch a new Ravada");# or exit;

remove_old_domains();
remove_old_disks();

for my $vm_name ( qw(KVM Void)) {
    my $vm;
    eval {
        $vm= $RVD_BACK->search_vm($vm_name)  if $RVD_BACK;
        @ARG_CREATE_DOM = ( id_iso => 1, vm => $vm_name, id_owner => $USER->id )       if $vm;
    };

    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        skip($msg,10)   if !$vm;
    
        diag("Testing requests with $vm_name");
        $vm = undef;
    
        test_req_create_domain_iso($vm_name);

        my $domain_base = test_req_create_domain($vm_name) or next;

        ok(!$domain_base->_vm->vm,"Expecting no vm in base");

        test_req_prepare_base($vm_name, $domain_base->name);
        my $domain_clone = test_req_create_from_base($vm_name, $domain_base) 
            or next;

        ok(!$domain_base->_vm->vm,"Expecting no vm in base");
        ok(!$domain_clone->_vm->vm,"Expecting no vm in clone");

        test_volumes($vm_name,$domain_base, $domain_clone);
    
        ok(!$domain_base->_vm->vm,"Expecting no vm in base before remove base");
        ok(!$domain_clone->_vm->vm,"Expecting no vm in clone before remove base");

        test_req_remove_base($vm_name, $domain_base, $domain_clone);

    };
}

remove_old_domains();
remove_old_disks();

done_testing();
