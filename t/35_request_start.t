use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use_ok('Ravada');
use_ok('Ravada::Request');
use lib 't/lib';

no warnings "experimental::signatures";
use feature qw(signatures);

use Test::Ravada;

my $RAVADA = rvd_back();
my $USER = create_user('foo','bar', 1);

my @ARG_CREATE_DOM = ( id_owner => $USER->id , id_iso => search_id_iso('Alpine') );

sub test_remove_domain {
    my $vm_name = shift;
    my $name = shift;

    my $vm = rvd_back->search_vm($vm_name) 
        or confess "I can't find vm $vm_name";

    diag("[$vm_name] removing domain $name");
    my $domain = $vm->search_domain($name,1);

    my $disks_not_removed = 0;

    if ($domain) {
        diag("Removing domain $name");
        my @disks = $domain->list_disks();
        eval { 
            $domain->remove(user_admin->id);
        };
        ok(!$@ , "Error removing domain $name ".ref($domain).": $@") or exit;

        for (@disks) {
            ok(!-e $_,"Disk $_ should be removed") or $disks_not_removed++;
        }

    }
    $domain = $vm->search_domain($name,1);
    ok(!$domain, "Removing old domain $name") or exit;
    ok(!$disks_not_removed,"$disks_not_removed disks not removed from domain $name");
}

sub test_new_domain($vm_name, $name, $vm) {

#    test_remove_domain($vm_name, $name);

    diag("[$vm_name] Creating domain $name");
    $vm->connect();
    my $domain = $vm->create_domain(name => $name, @ARG_CREATE_DOM, active => 0, disk => 1024 * 1024);

    ok($domain,"Domain not created");

    return $domain;
}


sub test_start {
    my $vm_name = shift;
    my $fork = shift;
    my $vm = shift;

    my $name = new_domain_name();
#    test_remove_domain($vm_name, $name);


    my $remote_ip = '99.88.77.66';

    my $req = Ravada::Request->start_domain(
        name => "does not exists"
        ,uid => $USER->id
        ,remote_ip => $remote_ip
    );
    if ($fork) {
        $RAVADA->process_requests(0);
    } else {
        $RAVADA->_process_all_requests_dont_fork(0);
    }

    wait_request( background => $fork, check_error => 0 );

    ok($req->status eq 'done', "[$vm_name] Req ".$req->{id}." expecting status done, got ".$req->status);
    like($req->error , qr/unknown/i
            ,"[$vm_name] Req ".$req->{id}." expecting unknown domain error , got "
                .($req->error or '<NULL>')) or exit;
    $req = undef;

    #####################################################################3
    #
    # start
    test_new_domain($vm_name, $name, $vm);

    {
        my $domain = $vm->search_domain($name);
        ok(!$domain->is_active,"Domain $name should be inactive") or return;
        is(rvd_back->_domain_just_started($domain),0);
    }
    my $req2 = Ravada::Request->start_domain(name => $name, uid => $USER->id
        ,remote_ip => $remote_ip
    );
    $RAVADA->process_requests();

    wait_request($req2);
    ok($req2->status eq 'done',"Expecting request status 'done' , got "
                                .$req2->status);
    is($req2->error,'');
    my $id_domain;
    {
        my $domain = $RAVADA->search_domain($name);
        $id_domain = $domain->id;
        $domain->start($USER)    if !$domain->is_active();
        ok($domain->is_active);
        is($domain->is_volatile,0);

        my $vm = $RAVADA->search_vm($vm_name);
        my $domain2 = $vm->search_domain($name);
        ok($domain2->is_active);
        is($domain2->is_volatile,0);
        is(rvd_back->_domain_just_started($domain),1);
    }

    $req2 = undef;

    #####################################################################3
    #
    # stop

    my $req3 = Ravada::Request->force_shutdown_domain(id_domain => $id_domain, uid => $USER->id);
    $RAVADA->_process_all_requests_dont_fork(0);
    wait_request($req3);
    ok($req3->status eq 'done',"[$vm_name] expecting request done , got "
                            .$req3->status);
    ok(!$req3->error,"Error shutting down domain $name , expecting ''
                        . Got '".($req3->error or ''));

    my $domain3 = $vm->search_domain($name);
    ok($domain3,"[$vm_name] Searching for domain $name") or exit;
    for ( 1 .. 60 ) {
        last if !$domain3 || !$domain3->is_active;
        sleep 1;
    }
    ok(!$domain3->is_active,"Domain $name should not be active");

    return $domain3;

}

sub test_screenshot_db {
    my $vm_name = shift;
    my $domain_name = shift;

    my $domain = $RAVADA->search_domain($domain_name);
    $domain->start($USER) if !$domain->is_active();
    return if !$domain->can_screenshot();
    sleep 2;

    $domain->screenshot();
    $domain->shutdown(user => $USER, timeout => 1);
    my $sth = connector->dbh->prepare("SELECT screenshot FROM domains WHERE id=?");
    $sth->execute($domain->id);
    my @fields = $sth->fetchrow;

    ok($fields[0]);
}

sub test_screenshot {
    my $vm_name = shift;
    my $domain_name = shift;

    my $domain = $RAVADA->search_domain($domain_name);
    $domain->start($USER) if !$domain->is_active();
    return if !$domain->can_screenshot();

    unlink $domain->_file_screenshot or die "$! ".$domain->_file_screenshot
        if -e $domain->_file_screenshot;

    ok(!-e $domain->_file_screenshot,"File screenshot ".$domain->_file_screenshot
                                    ." should not exist");

    my $file_screenshot = $domain->_file_screenshot();
    my $domain_id = $domain->id;
    $domain = undef;

    my $req = Ravada::Request->screenshot_domain(id_domain => $domain_id );
    ok($req);

    my $dont_fork = 1;
    rvd_back->process_all_requests(0,$dont_fork);
    wait_request( background=> !$dont_fork );
    ok($req->status('done'),"Request should be done, it is ".$req->status);
    ok(!$req->error(''),"Error should be '' , it is ".$req->error);

    ok(-e $file_screenshot,"File screenshot ".$file_screenshot
                                    ." should exist");
}

sub test_screenshot_file {
    my $vm_name = shift;
    my $domain_name = shift;

    my $domain = $RAVADA->search_domain($domain_name);

    $domain->start($USER) if !$domain->is_active();
    return if !$domain->can_screenshot();

    unlink $domain->_file_screenshot or die "$! ".$domain->_file_screenshot
        if -e $domain->_file_screenshot;

    ok(!-e $domain->_file_screenshot,"File screenshot should not exist");

    my $file = "/var/tmp/screenshot.$$.png";
    my $domain_id = $domain->id;
    $domain = undef;

    my $req = Ravada::Request->screenshot_domain(
        id_domain => $domain_id
        ,filename => $file);
    ok($req);

    my $dont_fork = 1;
    rvd_back->process_all_requests(0,$dont_fork);
    wait_request( background => !$dont_fork );

    ok($req->status('done'),"Request should be done, it is ".$req->status);
    ok(!$req->error(),"Error should be '' , it is ".($req->error or ''));

    ok(-e $file,"File '$file' screenshot should exist");

}


###############################################################
#

init();
clean();

for my $vm_name ( vm_names() ) {
    my $vmm = rvd_back->search_vm($vm_name);

    SKIP: {
        my $msg = "SKIPPED: Virtual manager $vm_name not found";
        if ($vmm && $vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vmm = undef;
        }

        diag($msg) if !$vmm;
        skip($msg,10) if !$vmm;

#        $vmm->disconnect() if $vmm;
        diag("Testing VM $vm_name");
        my $domain = test_start($vm_name,0, $vmm);
        $domain = test_start($vm_name,1, $vmm);
#        $domain->_vm->disconnect;
        next if !$domain;
        my $domain_name = $domain->name;
        $domain = undef;

        test_screenshot_db($vm_name, $domain_name);
        wait_request();
    };
}
end();

done_testing();

