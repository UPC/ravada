use warnings;
use strict;

use utf8;
use Carp qw(confess);
use Data::Dumper;
use JSON::XS;
use Test::More;

use Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user("foo","bar", 1);

#######################################################################

sub test_create_domain {
    my $vm_name = shift;
    my $name = ( shift or new_domain_name());

    my $ravada = rvd_back();
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"Expecting VM $vm_name") or return;

    #diag("[$vm_name] creating domain $name");
    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };
    is(''.$@,'') or confess;

    ok($domain,"[$vm_name] Expecting VM $name created with ".ref($vm)." ".($@ or '')) or confess;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $name;
}

sub test_rename_domain {
    my ($vm_name, $domain_name) = @_;


    my $new_domain_name = new_domain_name();
    {
        my $rvd_back = rvd_back();
        my $vm = $rvd_back->search_vm($vm_name);
        my $domain = $vm->search_domain($domain_name);
        ok($domain,"[$vm_name] Expecting found $domain_name") 
            or return;

        eval { $domain->rename(name => $new_domain_name, user => $USER) };
        ok(!$@,"Expecting error='' , got ='".($@ or '')."'") or return;
    }

    my $vm= rvd_front->search_vm($vm_name);
    my $domain0 = $vm->search_domain($domain_name);
    ok(!$domain0,"[$vm_name] Expecting not found $domain_name");

    my $domain1 = $vm->search_domain($new_domain_name);
    ok($domain1,"[$vm_name] Expecting renamed domain $new_domain_name") 
        or return;

    return $new_domain_name;
}

sub _change_hardware_ram($domain) {
    Ravada::Request->shutdown_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,timeout => 1
    );
    wait_request();

    my $max_mem = $domain->info(user_admin)->{max_mem};
    my $mem = $domain->info(user_admin)->{memory};

    my $new_max_mem = int($max_mem * 1.7 ) + 1;
    my $new_mem = int($mem * 1.6 ) + 1;

    Ravada::Request->change_hardware (
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => { max_mem => $new_max_mem , memory => $new_mem }
    );
    wait_request(debug => 0);
    my $domain2 = Ravada::Front::Domain->open($domain->id);
    like($domain2->_data('config_no_hd'),qr/./) or die $domain->name;
}

sub _add_hardware_disk($domain) {
    diag("add disk");
    Ravada::Request->shutdown_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,timeout => 1
    );
    wait_request();

    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'disk'
        ,data => { size => 1*1024*1024, type => 'data' }
    );
    wait_request();
    my $domain2 = Ravada::Front::Domain->open($domain->id);
    diag($domain2->_data('config_no_hd'));
}

sub test_req_rename_domain {
    my ($vm_name, $domain_name, $dont_fork, $change_hardware) = @_;
    my $debug = 0;
    $change_hardware = 0 if !defined $change_hardware;

    my $domain_id;
    {
        my $rvd_back = rvd_back();
        my $vm = $rvd_back->search_vm($vm_name);
        my $domain = $vm->search_domain($domain_name);
        ok($domain,"[$vm_name-req] Expecting found $domain_name") or return;
        $domain_id = $domain->id;
        if ($change_hardware == 1 ) {
            _add_hardware_disk($domain);
        } elsif($change_hardware == 2) {
            _change_hardware_ram($domain);
        }
    }
    my $new_domain_name = new_domain_name();
    {
        my $req = Ravada::Request->rename_domain(
              uid => $USER->id,
             name => $new_domain_name,
        id_domain => $domain_id,
        );
        ok($req);
        my $rvd_back = rvd_back();

        $rvd_back->process_requests($debug,$dont_fork);
        for ( 1 .. 5 ) {
            wait_request($req) if $req->status ne 'done';
        }
        $rvd_back->_wait_pids();
        ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done") or exit;
        ok(!$req->error,"Error ".($req->error or'')
                        ." renaming domain ".$domain_name)
            or return;
    }
    {
        my $vm = rvd_front->search_vm($vm_name);

        my $domain0 = $vm->search_domain($domain_name);
        ok(!$domain0,"[$vm_name-req] Expecting not found $domain_name");

        my $domain1 = $vm->search_domain($new_domain_name);
        ok($domain1,"[$vm_name-req] Expecting renamed domain "
                        ."$new_domain_name") or return;

    }
    my $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain_id
    );
    wait_request(debug => 0);
    Ravada::Request->force_shutdown_domain(
        uid => user_admin->id
        ,id_domain => $domain_id
    );
    wait_request();

    return $new_domain_name;
}

sub test_clone_domain {
    my $vm_name = shift;
    my $domain_name = shift;

    my $clone_name = new_domain_name;

    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    ok($domain,"[$vm_name] Expecting domain $domain_name") or exit;

    $domain->shutdown_now($USER);
    $domain->is_public(1);
    my $clone = $domain->clone(name => $clone_name, user=>user_admin );
    ok($clone) or return;
    return $clone_name;
}

sub test_rename_clone {
    my $vm_name = shift;

    my $domain_name = test_create_domain($vm_name);
    my $clone1_name = test_clone_domain($vm_name, $domain_name);
    test_rename_domain($vm_name, $clone1_name)
        if $clone1_name;
}

sub test_req_rename_utf_ca($vm_name) {

    my $domain = create_domain_v2(
        vm_name => $vm_name
        ,name => new_domain_name()
    );

    my $name = new_domain_name();
    my $new_name = $name."-ç";

    my $req = Ravada::Request->rename_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $new_name
    );
    wait_request();

    my $dom2 =Ravada::Front::Domain->open($domain->id);
    is($dom2->name,$name."-c");
    is($dom2->_data('name'),$name."-c");
    is($dom2->alias(),$new_name);

}

sub test_req_rename_utf_from_ca($vm_name) {

    my $domain = create_domain_v2(
        vm_name => $vm_name
        ,name => new_domain_name()."-ç"
    );

    my $new_name = new_domain_name();

    my $req = Ravada::Request->rename_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $new_name
    );
    wait_request();

    my $dom2 =Ravada::Front::Domain->open($domain->id);
    is($dom2->name,$new_name);
    is($dom2->_data('name'),$new_name);
    is($dom2->alias(),$new_name);
}

sub test_req_rename_utf_ru($vm_name) {

    my $domain = create_domain_v2(
        vm_name => $vm_name
        ,name => new_domain_name()
    );

    my $name = new_domain_name();
    my $new_name = $name."-Саша";

    my $req = Ravada::Request->rename_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $new_name
    );
    wait_request();

    my $dom2 =Ravada::Front::Domain->open($domain->id);
    like($dom2->name,qr/^[a-z0-9_\-]+$/);
    like($dom2->_data('name'), qr/^[a-z0-9_\-]+$/);
    is($dom2->alias(),$new_name);

}

sub test_req_rename_utf_from_ru($vm_name) {

    my $domain = create_domain_v2(
        vm_name => $vm_name
        ,name => new_domain_name()."-Саша"
    );

    my $new_name = new_domain_name();

    my $req = Ravada::Request->rename_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $new_name
    );
    wait_request();

    my $dom2 =Ravada::Front::Domain->open($domain->id);
    is($dom2->name,$new_name);
    is($dom2->_data('name'),$new_name);
    is($dom2->alias(),$new_name);
}

sub test_req_rename_utf_ar($vm_name) {

    my $domain = create_domain_v2(
        vm_name => $vm_name
        ,name => new_domain_name()
    );

    my $name = new_domain_name();
    my $new_name = $name ."-جميل";

    my $req = Ravada::Request->rename_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $new_name
    );
    wait_request();

    my $dom2 =Ravada::Front::Domain->open($domain->id);

    like($dom2->name,qr/^[a-z0-9_\-]+$/);
    like($dom2->_data('name'), qr/^[a-z0-9_\-]+$/);
    is($dom2->alias(),$new_name);

}

sub test_req_rename_utf_from_ar($vm_name) {

    my $domain = create_domain_v2(
        vm_name => $vm_name
        ,name => new_domain_name()."-جميل"
    );

    my $new_name = new_domain_name();

    my $req = Ravada::Request->rename_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => $new_name
    );
    wait_request();

    my $dom2 =Ravada::Front::Domain->open($domain->id);
    is($dom2->name,$new_name);
    is($dom2->_data('name'),$new_name);
    is($dom2->alias(),$new_name);
}


sub test_req_rename_clone {

    # TODO : this makes the test loose STDOUT or STDERR and ends with
    # t/vm/55_rename.t (Wstat: 13 Tests: 71 Failed: 0)
    #  Non-zero wait status: 13

#    return;

    my $vm_name = shift;

    my $domain_name = test_create_domain($vm_name);
    my $clone2_name = test_clone_domain($vm_name, $domain_name);

    my $dont_fork = 1;
    test_req_rename_domain($vm_name, $clone2_name, $dont_fork)
        if $clone2_name;
}

sub test_rename_twice {
    my $vm_name = shift;

    my $name = test_create_domain($vm_name);
    my $new_name1=test_rename_domain($vm_name, $name) or return;

    my $new_name2=test_rename_domain($vm_name, $new_name1);
    ok($new_name2,"Expecting rename twice $name -> $new_name1 -> ")
        or return;

    my $new_name3=test_rename_domain($vm_name, $new_name2);
    ok($new_name3,"Expecting rename thrice") or return;

}

sub test_rename_and_base($vm) {
    my $base = create_domain($vm,undef, undef, 1);

    my $new_domain_name = new_domain_name();
    $base->rename(name => $new_domain_name, user => user_admin);
    is($base->name , $new_domain_name);

    $base->prepare_base(user_admin);
    for my $vol ($base->list_files_base) {
        next if $vol =~ /iso$/;
        like($vol,qr{/$new_domain_name});
    }

}

sub test_req_rename_base_failed($vm) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);

    my $old_name = $base->_data('name');

    my $sth = connector->dbh->prepare(
        "UPDATE domains set alias=? WHERE id=?"
    );
    $sth->execute(new_domain_name, $base->id);

    my $req = Ravada::Request->rename_domain(
        id_domain => $base->id
        ,uid => user_admin->id
        ,name => $old_name

    );
    wait_request();
}

#######################################################################

clean();

for my $vm_name ( vm_names()) {

    my $vm_ok;
    eval {
        $vm_ok = rvd_back()->search_vm($vm_name);
    };
    diag($@) if $@;
    
    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm_ok && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm_ok = undef;
        }

        diag($msg)      if !$vm_ok;
        skip $msg,10    if !$vm_ok;

        diag("Testing rename domains with $vm_name");
    
        test_req_rename_base_failed($vm_name);

        test_req_rename_utf_ca($vm_name);
        test_req_rename_utf_ru($vm_name);
        test_req_rename_utf_ar($vm_name);

        test_req_rename_utf_from_ca($vm_name);
        test_req_rename_utf_from_ru($vm_name);
        test_req_rename_utf_from_ar($vm_name);

        test_rename_and_base($vm_ok);
        test_rename_twice($vm_name);

        my $domain_name = test_create_domain($vm_name);
        test_rename_domain($vm_name, $domain_name)  or next;
        test_create_domain($vm_name, $domain_name);
    
        $domain_name = test_create_domain($vm_name);

        my $name2=test_req_rename_domain($vm_name, $domain_name);
        next if !$name2;
        my $name3 = test_req_rename_domain($vm_name, $name2, undef, 1);
        next if !$name3;
        my $name4 = test_req_rename_domain($vm_name, $name3, undef, 2);
        next if !$name4;
        test_create_domain($vm_name, $domain_name);
    
        test_rename_clone($vm_name);
        test_req_rename_clone($vm_name);

    };
}
    

end();
done_testing();
