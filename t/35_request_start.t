use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');
use lib 't/lib';

use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $RAVADA = rvd_back($test->connector, 't/etc/ravada.conf');

my @ARG_CREATE_DOM;

sub test_request_start {
}

sub test_remove_domain {
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $RAVADA->search_domain($name,1);

    my $disks_not_removed = 0;

    if ($domain) {
        diag("Removing domain $name");
        my @disks = $domain->list_disks();
        eval { 
            $domain->remove(user_admin->id);
        };
        ok(!$@ , "Error removing domain $name ".ref($domain).": $@") or exit;

        ok(! -e $domain->file_base_img ,"Image file was not removed "
                    . $domain->file_base_img )
                if  $domain->file_base_img;
        for (@disks) {
            ok(!-e $_,"Disk $_ should be removed") or $disks_not_removed++;
        }

    }
    $domain = $RAVADA->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;
    ok(!$disks_not_removed,"$disks_not_removed disks not removed from domain $name");
}

sub test_new_domain {
    my $name = shift;

    test_remove_domain($name);

    diag("Creating domain $name");
    my $domain = $RAVADA->create_domain(name => $name, @ARG_CREATE_DOM, active => 0);

    ok($domain,"Domain not created");

    return $domain;
}


sub test_start {
    my $name = new_domain_name();
    test_remove_domain($name);


    my $req = Ravada::Request->start_domain(
        "does not exists"
    );
    $RAVADA->_process_requests_dont_fork();

    ok($req->status eq 'done', "Req ".$req->{id}." expecting status done, got ".$req->status);
    ok($req->error && $req->error =~ /unknown/i
            ,"Req ".$req->{id}." expecting unknown domain error , got "
                .($req->error or '<NULL>')) or return;
    $req = undef;

    #####################################################################3
    #
    # start
    test_new_domain($name);

    my $domain = $RAVADA->search_domain($name);
    ok(!$domain->is_active,"Domain $name should be inactive") or return;

    my $req2 = Ravada::Request->start_domain($name);
    $RAVADA->process_requests();

    ok($req2->status eq 'done');
    $domain->start()    if !$domain->is_active();

    ok($domain->is_active);

    my $domain2 = $RAVADA->search_domain($name);
    ok($domain2->is_active);

    $req2 = undef;

    #####################################################################3
    #
    # stop

    my $req3 = Ravada::Request->shutdown_domain($name);
    $RAVADA->process_requests();
    ok($req3->status eq 'done');

    ok(!$domain->is_active);

    my $domain3 = $RAVADA->search_domain($name);
    ok(!$domain3->is_active);

    return $domain3;

}

###############################################################
#

remove_old_domains();
remove_old_disks();

my $vmm;

eval { 
    $vmm = $RAVADA->search_vm('kvm');
    @ARG_CREATE_DOM = ( id_iso => 1, vm => 'kvm', id_owner => 1 )  if $vmm;

    if (!$vmm) {
        $vmm = $RAVADA->search_vm('lxc');
        @ARG_CREATE_DOM = ( id_template => 1, vm => 'LXC', id_owner => 1 );
    }

} if $RAVADA;

SKIP: {
    my $msg = "SKIPPED: No virtual managers found";
    diag($msg) if !$vmm;
    skip($msg,10) if !$vmm;

    remove_old_domains();
    remove_old_disks();
    my $domain = test_start();

    $domain->shutdown_now() if $domain;
    $domain->remove(user_admin())       if $domain;
};
done_testing();

