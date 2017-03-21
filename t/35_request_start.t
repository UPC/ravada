use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');
use lib 't/lib';

use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, 't/etc/ravada.conf');
my $RAVADA = rvd_back();
my $USER = create_user('foo','bar', 1);

my @ARG_CREATE_DOM = ( id_owner => $USER->id , id_iso => 1 );

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

sub test_new_domain {
    my $vm_name = shift;
    my $name = shift;

    my $vm = $RAVADA->search_vm($vm_name);

#    test_remove_domain($vm_name, $name);

    diag("[$vm_name] Creating domain $name");
    $vm->connect();
    my $domain = $vm->create_domain(name => $name, @ARG_CREATE_DOM, active => 0);

    ok($domain,"Domain not created");

    return $domain;
}


sub test_start {
    my $vm_name = shift;

    my $name = new_domain_name();
#    test_remove_domain($vm_name, $name);


    my $remote_ip = '99.88.77.66';

    my $req = Ravada::Request->start_domain(
        name => "does not exists"
        ,uid => $USER->id
        ,remote_ip => $remote_ip
    );
    $RAVADA->process_requests();

    wait_request($req);

    ok($req->status eq 'done', "[$vm_name] Req ".$req->{id}." expecting status done, got ".$req->status);
    ok($req->error && $req->error =~ /unknown/i
            ,"[$vm_name] Req ".$req->{id}." expecting unknown domain error , got "
                .($req->error or '<NULL>')) or return;
    $req = undef;

    #####################################################################3
    #
    # start
    test_new_domain($vm_name, $name);

    {
        my $vm = $RAVADA->search_vm($vm_name);
        my $domain = $vm->search_domain($name);
        ok(!$domain->is_active,"Domain $name should be inactive") or return;
    }
    my $req2 = Ravada::Request->start_domain(name => $name, uid => $USER->id
        ,remote_ip => $remote_ip
    );
    $RAVADA->process_requests();

    wait_request($req2);
    ok($req2->status eq 'done',"Expecting request status 'done' , got "
                                .$req2->status);

    {
        my $domain = $RAVADA->search_domain($name);
        $domain->start($USER)    if !$domain->is_active();
        ok($domain->is_active);

        my $vm = $RAVADA->search_vm($vm_name);
        my $domain2 = $vm->search_domain($name);
        ok($domain2->is_active);
    }

    $req2 = undef;

    #####################################################################3
    #
    # stop

    my $req3 = Ravada::Request->force_shutdown_domain(name => $name, uid => $USER->id);
    $RAVADA->process_requests();
    wait_request($req3);
    ok($req3->status eq 'done',"[$vm_name] expecting request done , got "
                            .$req3->status);
    ok(!$req3->error,"Error shutting down domain $name , expecting ''
                        . Got '".($req3->error or ''));

    my $vm = $RAVADA->search_vm($vm_name);
    my $domain3 = $vm->search_domain($name);
    for ( 1 .. 60 ) {
        last if !$domain3->is_active;
        sleep 1;
    }
    ok(!$domain3->is_active,"Domain $name should not be active");

    return $domain3;

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
    wait_request($req);
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
    wait_request($req);

    ok($req->status('done'),"Request should be done, it is ".$req->status);
    ok(!$req->error(),"Error should be '' , it is ".($req->error or ''));

    ok(-e $file,"File '$file' screenshot should exist");

}


###############################################################
#

remove_old_domains();
remove_old_disks();

for my $vm_name (qw(KVM Void)) {
    my $vmm = $RAVADA->search_vm($vm_name);

    SKIP: {
        my $msg = "SKIPPED: Virtual manager $vm_name not found";
        if ($vmm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vmm = undef;
        }

        diag($msg) if !$vmm;
        skip($msg,10) if !$vmm;

#        $vmm->disconnect() if $vmm;
        diag("Testing VM $vm_name");
        my $domain = test_start($vm_name);
#        $domain->_vm->disconnect;
        my $domain_name = $domain->name;
        $domain = undef;

        test_screenshot($vm_name, $domain_name);
        test_screenshot_file($vm_name, $domain_name);
    };
}
remove_old_domains();
remove_old_disks();

done_testing();

