use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $RAVADA;

eval { $RAVADA = Ravada->new(connector => $test->connector) };

my @ARG_CREATE_DOM;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $CONT = 0;

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
            $domain->remove();
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
    my $name = $DOMAIN_NAME."_".$CONT++;
    test_remove_domain($name);

    test_new_domain($name);

    my $domain = $RAVADA->search_domain($name);
    ok(!$domain->is_active,"Domain $name should be inactive") or return;


    my $req = Ravada::Request->start_domain(
        "does not exists"
    );
    $RAVADA->process_requests();

    ok($req->status eq 'done', "Expecting status done, got ".$req->status);
    ok($req->error && $req->error =~ /unknown/i
            ,"Expecting unknown domain error , got "
                .($req->error or '<NULL>'));
    $req = undef;

    #####################################################################3
    #
    # start

    my $req2 = Ravada::Request->start_domain($name);
    $RAVADA->process_requests();

    ok($req2->status eq 'done');

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
sub remove_old_domains {
    my ($name) = $0 =~ m{.*/(.*)\.t};
    for ( 0 .. 10 ) {
        my $dom_name = $name."_$_";
        my $domain = $RAVADA->search_domain($dom_name);
        $domain->shutdown_now() if $domain;
        test_remove_domain($dom_name);
    }
}

sub remove_old_disks {
    my ($name) = $0 =~ m{.*/(.*)\.t};

    my $vm = $RAVADA->search_vm('kvm');
    ok($vm,"I can't find a KVM virtual manager") or return;

    my $dir_img = $vm->dir_img();
    ok($dir_img," I cant find a dir_img in the KVM virtual manager") or return;

    for my $count ( 0 .. 10 ) {
        my $disk = $dir_img."/$name"."_$count.img";
        if ( -e $disk ) {
            unlink $disk or die "I can't remove $disk";
        }
    }
    $vm->storage_pool->refresh();
}


###############################################################
#

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

    $domain->shutdown_now();
    $domain->remove();
};
done_testing();

