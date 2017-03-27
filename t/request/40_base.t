use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, 't/etc/ravada.conf');

my $USER = create_user("foo","bar");

my @ARG_CREATE_DOM = (
        id_iso => 1
        ,id_owner => $USER->id
);

$Ravada::CAN_FORK = 1;

#######################################################################

sub test_empty_request {
    my $request = rvd_back()->request();
    ok($request);
}

sub test_unread_messages {
    my ($user, $n_unread, $test) = @_;
    confess "Missing test name" if !$test;

    my @messages = $user->unread_messages();

    ok(scalar @messages == $n_unread,"$test: Expecting $n_unread unread messages , got "
        .scalar@messages." ".Dumper(\@messages));

}

sub test_unshown_messages {
    my ($user, $n_unread, $test) = @_;
    confess "Missing test name" if !$test;

    my @messages = $user->unshown_messages();

    ok(scalar @messages == $n_unread,"$test: Expecting $n_unread unshown messages , got "
        .scalar@messages." ".Dumper(\@messages));

}

sub test_swap {
    my $vm_name = shift;

    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,vm => $vm_name
        ,@ARG_CREATE_DOM
        ,swap => 128*1024*1024
    );
    ok($req);
    rvd_back()->process_requests();
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
    test_unshown_messages($USER,0, "[$vm_name] create domain $name");
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

    my $rvd_back = rvd_back();
#    $rvd_back->process_requests(1);
    $rvd_back->process_requests();
    wait_request($req);

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

    test_unshown_messages($USER,1, $test);
    test_unshown_messages($USER,0, $test);
    test_unread_messages($USER,1, $test);

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
    wait_request($req);

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
    my $req;
    {
        my $vm = rvd_front()->search_vm($vm_name);
        my $domain = $vm->search_domain($name);
        ok($domain, "Searching for domain $name, got ".ref($name)) or return;
        ok(!$domain->is_base, "Expecting domain base=0 , got: '".$domain->is_base."'");

        $req = Ravada::Request->prepare_base(
            id_domain => $domain->id
            ,uid => $USER->id
        );
        ok($req);
        ok($req->status);

        ok($domain->is_locked,"Domain $name should be locked when preparing base");
    }

    rvd_back->process_requests();
    rvd_back->process_long_requests(0,1);
    wait_request($req);
    ok(!$req->error,"Expecting error='', got '".($req->error or '')."'");

    my $vm = rvd_front()->search_vm($vm_name);
    my $domain2 = $vm->search_domain($name);
    ok($domain2->is_base, "Expecting domain base=1 , got: '".$domain2->is_base."'");# or exit;

    my @unread_messages = $USER->unread_messages;
    like($unread_messages[-1]->{subject}, qr/done$/i);

    my @messages = $USER->messages;
    like($messages[-1]->{subject}, qr/done$/i);

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
        wait_request($req);

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

sub test_volumes {
    my ($vm_name, $domain1_name , $domain2_name) = @_;

    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);

    my $domain1 = $vm->search_domain($domain1_name);
    my $domain2 = $vm->search_domain($domain2_name);

    my @volumes1 = $domain1->list_volumes();
    my @volumes2 = $domain2->list_volumes();

    my %volumes1 = map { $_ => 1 } @volumes1;
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
    rvd_back->process_requests();
    rvd_back->process_long_requests(0,1);
    wait_request($req);

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
        wait_request($req);
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

################################################

{
my $rvd_back = rvd_back();
ok($rvd_back,"Launch Ravada");# or exit;
}

ok($Ravada::CONNECTOR,"Expecting conector, got ".($Ravada::CONNECTOR or '<unde>'));

remove_old_domains();
remove_old_disks();

for my $vm_name ( qw(Void KVM)) {
    my $vm_connected;
    eval {
        my $rvd_back = rvd_back();
        my $vm= $rvd_back->search_vm($vm_name)  if rvd_back();
        $vm_connected = 1 if $vm;
        @ARG_CREATE_DOM = ( id_iso => 1, vm => $vm_name, id_owner => $USER->id );
    };

    SKIP: {
        my $msg = "SKIPPED: virtual manager $vm_name not found";
        if ($vm_connected && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm_connected = undef;
        }

        skip($msg,10)   if !$vm_connected;

        diag("Testing requests with $vm_name");
        test_swap($vm_name);

        test_req_create_domain_iso($vm_name);

        my $base_name = test_req_create_domain($vm_name) or next;

        test_req_prepare_base($vm_name, $base_name);
        my $clone_name = test_req_create_from_base($vm_name, $base_name);

        ok($clone_name) or next;

        test_volumes($vm_name,$base_name, $clone_name);

        test_req_remove_base_fail($vm_name, $base_name, $clone_name);
        test_req_remove_base($vm_name, $base_name, $clone_name);

    };
}

remove_old_domains();
remove_old_disks();

done_testing();
