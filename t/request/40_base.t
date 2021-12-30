use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user("foo","bar", 1);
my $USER_REGULAR = create_user(new_domain_name,$$);

rvd_back();
my $ID_ISO = search_id_iso('Alpine');
my @ARG_CREATE_DOM = (
        id_iso => $ID_ISO
        ,id_owner => $USER->id
);

$Ravada::CAN_FORK = 1;

#######################################################################

sub test_empty_request {
    my $request = rvd_back()->request();
    ok($request);
}

sub test_swap {
    my $vm_name = shift;

    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,vm => $vm_name
        ,@ARG_CREATE_DOM
        ,swap => 1024*1024
        ,disk => 1024*1024
    );
    ok($req);
    rvd_back()->_process_all_requests_dont_fork();
    wait_request($req);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".($req->error or '')." creating domain ".$name)
        or return;

    my $domain = rvd_back->search_domain($name);
    ok($domain,"Expecting domain $name created") or return;
    ok(!$domain->is_active,"Expecting domain no alive, got : "
            .($domain->is_active or 0));

    for my $file ($domain->list_volumes) {
        ok(-e $file,"[$vm_name] Expecting file $file")
    }
}

sub test_req_create_domain_iso {
    my $vm_name = shift;

    my $name = new_domain_name();

    $USER->mark_all_messages_read();
    is($USER->unshown_messages,0, "[$vm_name] create domain $name");

    is($USER->unread_messages,0, "[$vm_name] create domain $name");

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

    my $rvd_back = rvd_back();
#    $rvd_back->process_requests(1);
    $rvd_back->process_requests();
    wait_request(background => 1);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".($req->error or '')." creating domain ".$name)
        or return;

#    test_unread_messages($USER,1, "[$vm_name] create domain $name");
    test_message_new_domain($vm_name, $USER, "[$vm_name] create domain $name");

    my $req2 = Ravada::Request->open($req->id);
    ok($req2->{id} == $req->id,"req2->{id} = ".$req2->{id}." , expecting ".$req->id);

    my $vm = rvd_front()->search_vm($vm_name);
    my $domain =  $vm->search_domain($name);

    ok($domain,"[$vm_name] I can't find domain $name");
    ok(!$domain->is_locked,"Domain $name should not be locked");

    $USER->mark_all_messages_read();

    return $domain->name;
}

sub test_message_new_domain {
    my ($vm_name, $user, $test) = @_;

    my @unshown = $USER->unshown_messages;
    my $n_expected = 1;
    is(scalar @unshown, $n_expected , $test." ".Dumper(\@unshown));
    is($USER->unshown_messages,0, $test);
    is($USER->unread_messages, $n_expected, $test." ".Dumper($USER->unread_messages));

    my @messages = $user->unread_messages();
    my $message = $user->show_message($messages[0]->{id});

    ok($message->{message} && $message->{message} =~ /\w+/
            , "Expecting message content not empty, got ''") or exit;

    $USER->mark_all_messages_read();
}

sub test_req_create_domain {
    my $vm_name = shift;

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

    my $rvd_back = rvd_back();
    $rvd_back->process_requests();
    wait_request(background => 1);

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error '".($req->error or '')."' creating domain ".$name);

    my $rvd_front = rvd_front();
    my $domain =  $rvd_front->search_domain($name);

    ok($domain,"Searching for domain $name") or return;
    ok($domain->name eq $name,"Expecting domain name '$name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting domain not base , got: ".$domain->is_base());

    return $name;
}

sub test_req_prepare_base {
    my $vm_name = shift;
    my $name = shift;

    my $rvd_back = rvd_back();
    {
        my $domain = $rvd_back->search_domain($name);
        $domain->shutdown_now($USER)    if $domain->is_active();
        is($domain->is_active(),0);
    }
    my $req;
    {
        my $vm = rvd_front()->search_vm($vm_name);
        my $domain = $vm->search_domain($name);
        ok($domain, "Searching for domain $name, got ".ref($name)) or return;
        ok(!$domain->is_base, "Expecting domain base=0 , got: '".$domain->is_base."'");
        $req = Ravada::Request->prepare_base(
            id_domain => $domain->id
            ,uid => user_admin->id
        );
        ok($req);
        ok($req->status);

        ok($domain->is_locked,"Domain $name should be locked when preparing base");
    }

    rvd_back->_process_all_requests_dont_fork();
    rvd_back->process_long_requests(0,1);
    wait_request(background => 1);
    ok(!$req->error,"Expecting error='', got '".($req->error or '')."'");

    my $vm = rvd_front()->search_vm($vm_name);
    my $domain2 = $vm->search_domain($name);
    ok($domain2->is_base, "Expecting domain base=1 , got: '".$domain2->is_base."'");# or exit;
    $domain2->is_public(1);
    my @unread_messages = $USER->unread_messages;
    like($unread_messages[-1]->{subject}, qr/done$/i);

    my @messages = $USER->messages;
    like($messages[-1]->{subject}, qr/done|downloaded/i);

    {
        my $domain = $rvd_back->search_domain($name);
        is($domain->is_active(),0);
    }

}

sub test_req_create_from_base {
    my $vm_name = shift;
    my $base_name = shift;

    my $clone_name = new_domain_name();
    my $id_base;
    {
    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);
    my $domain_base = $vm->search_domain($base_name);
    $id_base = $domain_base->id
    }

    {
        my $req = Ravada::Request->create_domain(
            name => $clone_name
            , vm => $vm_name
            , id_base => $id_base
            , id_owner => $USER->id
        );
        ok($req->status eq 'requested'
            ,"Status of request is ".$req->status." it should be requested");


        rvd_back->process_requests();
        wait_request(background => 1);

        ok($req->status eq 'done'
            ,"Status of request is ".$req->status." it should be done");
        ok(!$req->error,"Expecting error '' , got '"
                        .($req->error or '')."' creating domain ".$clone_name);

    }
    my $domain =  rvd_front()->search_domain($clone_name);

    ok($domain,"Searching for domain $clone_name") or return;
    ok($domain->name eq $clone_name
        ,"Expecting domain name '$clone_name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting clone not base , got: "
        .$domain->is_base()." ".$domain->name);

    return $clone_name;

}
sub test_req_create_from_base_novm {
    my $vm_name = shift;
    my $base_name = shift;

    my $clone_name = new_domain_name();
    my $id_base;
    {
    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);
    my $domain_base = $vm->search_domain($base_name);
    $id_base = $domain_base->id
    }

    {
        my $req = Ravada::Request->create_domain(
            name => $clone_name
            , id_base => $id_base
            , id_owner => $USER->id
        );
        ok($req->status eq 'requested'
            ,"Status of request is ".$req->status." it should be requested");


        rvd_back->process_requests();
        wait_request(background => 1);

        ok($req->status eq 'done'
            ,"Status of request is ".$req->status." it should be done");
        ok(!$req->error,"Expecting error '' , got '"
                        .($req->error or '')."' creating domain ".$clone_name);

    }
    my $domain =  rvd_front()->search_domain($clone_name);

    ok($domain,"Searching for domain $clone_name") or return;
    ok($domain->name eq $clone_name
        ,"Expecting domain name '$clone_name', got ".$domain->name);
    ok(!$domain->is_base,"Expecting clone not base , got: "
        .$domain->is_base()." ".$domain->name);

    $domain = Ravada::Domain->open($domain->id);
    $domain->remove(user_admin);

}

sub test_volumes {
    my ($vm_name, $domain1_name , $domain2_name) = @_;

    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);

    my $domain1 = $vm->search_domain($domain1_name);
    my $domain2 = $vm->search_domain($domain2_name);

    my @volumes1 = $domain1->list_volumes();
    my @volumes2 = $domain2->list_volumes();

    my %volumes1 = map { $_ => 1 } grep { !/iso$/} @volumes1;
    my %volumes2 = map { $_ => 1 } @volumes2;

    ok(scalar keys %volumes1 == scalar keys %volumes2
        ,"[$vm_name] Domain $domain2_name Expecting ".scalar(keys %volumes1)
        ." , got ".scalar(keys %volumes2)." "
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


sub test_req_remove_base_fail {
    my ($vm_name, $name_base, $name_clone) = @_;

    my @files_base;
    my $req;

    {
        my $rvd_back = rvd_back();
        my $vm = $rvd_back->search_vm($vm_name);

        my $domain_base = $vm->search_domain($name_base);
        my $domain_clone= $vm->search_domain($name_clone);

        ok($domain_base->is_base,"[$vm_name] expecting domain ".$domain_base->id
            ." is base , got ".$domain_base->is_base) or return;

        @files_base = $domain_base->list_files_base();
        ok(scalar @files_base,"Expecting files base, got none") or return;

        ok($domain_base->has_clones,"Expecting domain base has clones, got :".$domain_base->has_clones);
        $domain_base->_vm->disconnect();
        $domain_clone->_vm->disconnect();

        $req = Ravada::Request->remove_base(
            id_domain => $domain_base->id
            , uid => $USER->id
        );
    }

    ok($req->status eq 'requested' || $req->status eq 'done');
    rvd_back->_process_all_requests_dont_fork();

    ok($req->status eq 'done', "Expected req->status 'done', got "
                                ."'".$req->status."'");

    ok($req->error =~ /has \d+ clones/i, "[$vm_name] Expected error 'has X clones'"
            .", got : '".$req->error."'");

    check_files_exist(@files_base);

}

sub test_req_remove_base {
    my ($vm_name, $name_base, $name_clone) = @_;

    my @files_base;
    my $req;

    {
        my $rvd_back = rvd_back();
        my $vm = $rvd_back->search_vm($vm_name);

        my $domain_base = $vm->search_domain($name_base);
        my $domain_clone= $vm->search_domain($name_clone);
        @files_base = $domain_base->list_files_base();

        $domain_clone->remove($USER);
        check_files_exist(@files_base);
        ok(!$domain_clone->is_base());

        $domain_base->_vm->disconnect();
        $domain_clone->_vm->disconnect();
        $req = Ravada::Request->remove_base(
            id_domain => $domain_base->id
            , uid => $USER->id
        );
    }

    {
        my $rvd_back = rvd_back();
        rvd_back->process_requests();
        rvd_back->process_long_requests(0,1);
        wait_request(background => 1);
    }
    ok($req->status eq 'done', "[$vm_name] Expected req->status 'done', got "
                                ."'".$req->status."'");

    ok(!$req->error, "Expected error ''"
            .", got : '".$req->error."'");

    {
        my $domain_base = rvd_front->search_vm($vm_name)
                            ->search_domain($name_base);
        ok($domain_base,"[$vm_name] I can't find domain $name_base")
            or return;
        ok(!$domain_base->is_base());
    }
    check_files_removed(@files_base);
}

sub test_req_remove {
    my ($vm_name, $name_domain ) = @_;
    my $vm = rvd_back->search_vm($vm_name);

    my $req = Ravada::Request->remove_domain(
        uid => $USER->id
        , name => $name_domain
    );

    rvd_back->_process_all_requests_dont_fork();
    is($req->status,'done');
    is($req->error,'');

    my $clone_gone = $vm->search_domain($name_domain);
    ok(!$clone_gone);
}

sub test_shutdown_by_name {
    my ($vm_name, $domain_name) = @_;

    my $id_domain;
    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    $id_domain = $domain->id;
    $domain->start($USER);

    is($domain->is_active,1);

    my $req;
    eval { $req = Ravada::Request->shutdown_domain(
        name => $domain_name
        ,uid => $USER->id
        ,timeout => 1
        );
    };
    is($@,'') or return;
    ok($req);
    wait_request(debug => 0, request => $req);
    is($req->status(),'done');

    for ( 1 .. 2 ) {
        wait_request(debug => 0, request => $req);
        last if !$domain->is_active || ! scalar($domain->list_requests);
        sleep 1;
    }

    my $domain2 = $vm->search_domain($domain_name);
    is($domain2->is_active,0,"Expecting $domain_name down") or exit;
}

sub test_shutdown_by_id {
    my ($vm_name, $domain_name) = @_;

    my $id_domain;
    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    $id_domain = $domain->id;
    $domain->start($USER);

    is($domain->is_active,1);

    my $req;
    eval { $req = Ravada::Request->shutdown_domain(
        id_domain => $id_domain
        ,uid => $USER->id
        ,timeout => 1
        );
    };
    is($@,'') or return;
    ok($req);
    rvd_back->_process_all_requests_dont_fork();
    is($req->status(),'done');
    is($req->error(),'');

    for ( 1 .. 2 ) {
        rvd_back->_process_all_requests_dont_fork();
        last if !$domain->is_active;
        sleep 1;
    }

    my $domain2 = $vm->search_domain($domain_name);
    is($domain2->is_active,0);
}

sub test_req_deny($vm, $base_name) {
    test_req_clone_deny($vm, $base_name);

    test_req_create_deny($vm);
}

sub test_req_create_deny($vm) {
    my $name = new_domain_name();
    my $user = create_user();

    my @args = (
        id_owner => $user->id
        ,vm => $vm->type
        ,id_iso => $ID_ISO
    );
    my $req = Ravada::Request->create_domain(@args,name => $name);
    is($req->status(),'done');
    like($req->error,qr/access denied/);
    wait_request();

    my $domain= $vm->search_domain($name);
    ok(!$domain);

    user_admin->grant($user,'create_machine');
    $name = new_domain_name();
    $req = Ravada::Request->create_domain(@args, name => $name);
    is($req->status(),'requested');
    wait_request();

    my $domain2 = $vm->search_domain($name);
    ok($domain2);

    $domain->remove(user_admin)  if $domain;
    $domain2->remove(user_admin) if $domain2;
    $user->remove();

}


sub test_req_clone_deny($vm, $base_name) {

    my $base = $vm->search_domain($base_name);
    $base->is_public(0),

    my $name = new_domain_name();

    my $req = Ravada::Request->clone(
        name => $name
        ,uid => $USER_REGULAR->id
        ,id_domain => $base->id
    );
    is($req->status(),'done');
    like($req->error,qr/is not public/) or exit;

    $req = Ravada::Request->clone(
        name => $name
        ,uid => -1
        ,id_domain => $base->id
    );
    is($req->status(),'done');
    like($req->error,qr/user.* does not exist/) or exit;

    $base->is_public(1),
    $req = Ravada::Request->clone(
        name => $name
        ,uid => $USER_REGULAR->id
        ,id_domain => $base->id
    );
    is($req->status(),'requested');
    wait_request(debug => 0);
    my $clone = $vm->search_domain($name);
    ok($clone,"Expecting clone $name");

    $base->is_public(0);
    $req = Ravada::Request->clone(
        name => $name
        ,uid => $USER_REGULAR->id
        ,id_domain => $base->id
    );
    is($req->status(),'done');
    like($req->error,qr/is not public/) or exit;

    $clone->remove(user_admin);

}

################################################

{
my $rvd_back = rvd_back();
ok($rvd_back,"Launch Ravada");# or exit;
}

ok($Ravada::CONNECTOR,"Expecting conector, got ".($Ravada::CONNECTOR or '<unde>'));

remove_old_domains();
remove_old_disks();

for my $vm_name ( vm_names ) {
    my $vm_connected;
    eval {
        my $rvd_back = rvd_back();
        my $vm;
        $vm= $rvd_back->search_vm($vm_name)  if rvd_back();
        $vm_connected = $vm if $vm;
        @ARG_CREATE_DOM = ( id_iso => search_id_iso('Alpine'), vm => $vm_name, id_owner => $USER->id, disk => 1024 * 1024 );

    };

    SKIP: {
        my $msg = "SKIPPED: virtual manager $vm_name not found";
        if ($vm_connected && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm_connected = undef;
        }

        skip($msg,10)   if !$vm_connected;

        diag("Testing requests with $vm_name");
        if ($vm_name eq 'KVM') {
            my $iso = $vm_connected->_search_iso($ID_ISO);
            $vm_connected->_iso_name($iso, undef);
        }
        test_swap($vm_name);

        my $domain_name = test_req_create_domain_iso($vm_name);
        test_shutdown_by_name($vm_name, $domain_name);
        test_shutdown_by_id($vm_name, $domain_name);

        my $base_name = test_req_create_domain($vm_name) or next;

        test_req_prepare_base($vm_name, $base_name);
        test_req_create_from_base_novm($vm_name, $base_name);
        my $clone_name = test_req_create_from_base($vm_name, $base_name);

        test_req_deny($vm_connected, $base_name);

        ok($clone_name) or next;

        test_volumes($vm_name,$base_name, $clone_name);

        test_req_remove_base_fail($vm_name, $base_name, $clone_name);
        test_req_remove_base($vm_name, $base_name, $clone_name);
        test_req_remove($vm_name, $base_name);

    };
}

end();

done_testing();
