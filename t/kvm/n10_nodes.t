use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

my $REMOTE_CONFIG;
##########################################################

sub test_node {
    my $vm_name = shift;

    die "Error: missing host in remote config\n ".Dumper($REMOTE_CONFIG)
        if !$REMOTE_CONFIG->{host};

    my $vm = rvd_back->search_vm($vm_name);

    my $node;
    eval { $node = $vm->new(%{$REMOTE_CONFIG}) };
    ok(!$@,"Expecting no error connecting to $vm_name at ".Dumper($REMOTE_CONFIG).", got :'"
        .($@ or '')."'");
    ok($node) or return;

    is($node->host,$REMOTE_CONFIG->{host});
    like($node->name ,qr($REMOTE_CONFIG->{host}));
    ok($node->vm,"[$vm_name] Expecting a VM in node");

    ok($node->id) or exit;

    my $node2 = Ravada::VM->open($node->id);
    is($node2->id, $node->id);
    is($node2->name, $node->name);
    is($node2->public_ip, $node->public_ip);
    return $node;
}

sub test_sync {
    my ($vm_name, $node, $base, $clone) = @_;

    eval { $clone->rsync($node) };
    like($@,'.') or return;
    is($@,'') or return;
    # TODO test synced files

    eval { $base->rsync($node) };
    is($@,'') or return;

    eval { $clone->rsync($node) };
    is($@,'') or return;
}

sub test_domain {
    my $vm_name = shift;
    my $node = shift or die "Missing node";

    my $vm = rvd_back->search_vm($vm_name);

    my $base = create_domain($vm_name);
    is($base->_vm->host, 'localhost');

    $base->prepare_base(user_admin);
    $base->rsync($node);
    my $clone = $base->clone(name => new_domain_name
        ,user => user_admin
    );

    test_sync($vm_name, $node, $base, $clone);

    eval { $clone->migrate($node) };
    is(''.$@ , '') or exit;

    eval { $clone->start(user_admin) };
    ok(!$@,$node->name." Expecting no error, got ".($@ or ''));
    is($clone->is_active,1) or return;

    my $ip = $node->ip;
    like($clone->display(user_admin),qr($ip));

    if ($REMOTE_CONFIG->{public_ip}) {
        my $public_ip = $REMOTE_CONFIG->{public_ip};
        like($clone->display(user_admin),qr($public_ip));
        isnt($vm->host, $public_ip);
    } else {
        diag("SKIPPED: Add public_ip to remote_vm.conf to test nodes with 2 IPs");
    }
    return $clone;
}


sub test_domain_no_remote {
    my ($vm_name, $node) = @_;

    my $domain;
    eval {
        $domain = $node->create_domain(
            name => new_domain_name
            ,id_owner => user_admin->id
            ,id_iso => 1
        );
    };
    like($@,qr'.',"Expecting no domain in remote node by now");

    $domain->remove(user_admin) if $domain;
}

sub test_remove_domain_from_local {
    my ($vm_name, $node, $domain_orig) = @_;
    $domain_orig->shutdown_now(user_admin)   if $domain_orig->is_active;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_orig->name);

    my @volumes = $domain->list_volumes();

    eval {$domain->remove(user_admin); };
    is(''.$@,'',"Expecting no errors removing domain ".$domain_orig->name);

    my $domain2 = $vm->search_domain($domain->name);
    ok(!$domain2,"Expecting no domain in local");

    my $domain3 = $node->search_domain($domain->name);
    ok(!$domain3,"Expecting no domain ".$domain->name." in node ".$node->name) or exit;

    test_remove_domain_node($node, $domain, \@volumes);

    test_remove_domain_node($vm, $domain, \@volumes);
}


sub test_remove_domain {
    my ($vm_name, $node, $domain) = @_;

    my @volumes = $domain->list_volumes();

    eval {$domain->remove(user_admin); };
    is($@,'');

    test_remove_domain_node($node, $domain, \@volumes);

    my $vm = rvd_back->search_vm($vm_name);
    isnt($vm->name, $node->name) or return;

    test_remove_domain_node($vm, $domain, \@volumes);
}

sub test_remove_domain_node {
    my ($node, $domain, $volumes) = @_;

    diag("checking removed volumes from ".$node->name);
    my %found = map { $_ => 0 } @$volumes;

    $node->_refresh_storage_pools();
    for my $pool ($node->vm->list_all_storage_pools()) {
        for my $vol ($pool->list_all_volumes()) {
            my $path = $vol->get_path();
            $found{$path}++ if exists $found{$path};
        }
    }
    for my $path (keys %found) {
        ok(!$found{$path},$node->name." Expecting vol $path removed")
            or exit;
    }

}

sub test_domain_starts_in_same_vm {
    my ($vm_name, $node) = @_;

    my $domain = test_domain($vm_name, $node);

    my $display = $domain->display(user_admin);
    $domain->shutdown_now(user_admin)   if $domain->is_active;

    unlike($domain->_vm->host, qr/localhost/)   or return;
    is($domain->_vm->host, $node->host)         or return;

    my $domain2 = rvd_back->search_domain($domain->name);
    ok($domain2,"Expecting a domain called ".$domain->name) or return;

    $domain2->start(user => user_admin);
    is($domain2->_vm->host, $node->host);
    is($domain2->display(user_admin), $display);

    $domain->remove(user_admin);
}

sub test_sync_base {
    my ($vm_name, $node) = @_;

    my $vm =rvd_back->search_vm($vm_name);
    my $base = create_domain($vm_name);
    my $clone = $base->clone(
        name => new_domain_name
       ,user => user_admin
    );

    eval { $clone->migrate($node); };
    like($@, qr'.');

    eval { $base->rsync($node); };
    is(''.$@,'');

    eval { $clone->migrate($node); };
    is(''.$@,'');

    is($clone->_vm->host, $node->host);
    $clone->shutdown_now(user_admin);

    my $clone2 = $vm->search_domain($clone->name);
    is($clone2->_vm->host, $vm->host);

    eval { $clone2->migrate($node); };
    is(''.$@,'');

    $clone->remove(user_admin);
    $base->remove(user_admin);

}

sub test_start_twice {
    my ($vm_name, $node) = @_;

    my $vm =rvd_back->search_vm($vm_name);
    my $base = create_domain($vm_name);
    my $clone = $base->clone(
        name => new_domain_name
       ,user => user_admin
    );

    eval { $base->rsync($node); };
    is(''.$@,'');

    eval { $clone->migrate($node); };
    is(''.$@,'');

    is($clone->_vm->host, $node->host);

    my $clone2 = $vm->search_domain($clone->name);
    is($clone2->_vm->host, $vm->host);
    $clone2->domain->create();
    warn $clone2->display(user_admin);

    eval { $clone->start(user => user_admin ) };
    is($@,'');
    is($clone->_vm->host, $vm->ip);
    warn $clone->display;
    is($clone->display(user_admin), $clone2->display(user_admin));

    $clone->remove(user_admin);
    $base->remove(user_admin);

}

sub test_rsync_newer {
    my ($vm_name, $node) = @_;

    my $domain = test_domain($vm_name, $node) or return;
    $domain->shutdown_now(user_admin)   if $domain->is_active;

    my ($volume) = $domain->list_volumes();
    my ($vol_name) = $volume =~ m{.*/(.*)};

    my $vm = rvd_back->search_vm($vm_name);

    my $capacity;
    { # vols equal, then resize
    my $vol = $vm->search_volume($vol_name);
    my $vol_remote = $node->search_volume($vol_name);
    is($vol_remote->get_info->{capacity}, $vol->get_info->{capacity});

    $capacity = int ($vol->get_info->{capacity} *1.1 );
    $vol->resize($capacity);
    }

    { # vols different
    my $vol2 = $vm->search_volume($vol_name);
    my $vol2_remote = $node->search_volume($vol_name);

    is($vol2->get_info->{capacity}, $capacity);
    isnt($vol2_remote->get_info->{capacity}, $capacity);
    isnt($vol2_remote->get_info->{capacity}, $vol2->get_info->{capacity});
    }

    # on starting it should sync
    is($domain->_vm->host, $node->host);
    $domain->start(user => user_admin);
    is($domain->_vm->host, $node->host);

    { # syncs for start, so vols should be equal
    my $vol3 = $vm->search_volume($vol_name);
    my $vol3_remote = $node->search_volume($vol_name);
    is($vol3_remote->get_info->{capacity}, $vol3->get_info->{capacity});
    }


}

sub test_bases_node {
    my ($vm_name, $node) = @_;

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = create_domain($vm_name);

    is($domain->base_in_vm($domain->_vm->id),undef);
    is($domain->base_in_vm($node->id), undef);

    $domain->prepare_base(user_admin);
    is($domain->base_in_vm($domain->_vm->id), 1);
    is($domain->base_in_vm($node->id), undef);

    $domain->migrate($node);
    is($domain->base_in_vm($node->id), 1);

    $domain->set_base_vm(vm => $node, value => 0, user => user_admin);
    is($domain->base_in_vm($node->id), 0);

    $domain->set_base_vm(vm => $vm, value => 0, user => user_admin);
    is($domain->is_base(),0);
    is($domain->base_in_vm($vm->id), 0);
    is($domain->base_in_vm($node->id), 0);

    my $req = Ravada::Request->set_base_vm(
                uid => user_admin->id
             ,id_vm => $vm->id
         ,id_domain => $domain->id
    );
    rvd_back->_process_all_requests_dont_fork();
    is($req->status,'done') or die Dumper($req);
    is($req->error,'');
    is($domain->base_in_vm($vm->id), 1);

    $req = Ravada::Request->remove_base_vm(
                uid => user_admin->id
             ,id_vm => $vm->id
         ,id_domain => $domain->id
    );
    rvd_back->_process_all_requests_dont_fork();
    is($domain->base_in_vm($vm->id), 0);

    $domain->remove(user_admin);
}

sub test_clone_not_in_node {
    my ($vm_name, $node) = @_;

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = create_domain($vm_name);

    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node, user => user_admin);

    is($domain->base_in_vm($node->id), 1);

    {
    my $clone1 = $domain->clone(name => new_domain_name, user => user_admin);
    is($clone1->_vm->host, 'localhost');
    eval { $clone1->start(user_admin) };
    is(''.$@,'') or exit;
    is($clone1->is_active,1);
    is($clone1->_vm->host, 'localhost');

    # search the domain in the underlying VM
    my $virt_domain;
    eval { $virt_domain = $clone1->_vm->vm->get_domain_by_name($clone1->name) };
    is(''.$@,'');
    ok($virt_domain,"Expecting ".$clone1->name." in ".$clone1->_vm->host);

    }

    {
    my $clone2 = $domain->clone(name => new_domain_name, user => user_admin);
    is($clone2->_vm->host, 'localhost');
    eval { $clone2->start(user_admin) };
    is(''.$@,'') or exit;
    is($clone2->is_active,1);
    is($clone2->_vm->host, 'localhost');

    # search the domain with underlying VM
    my $virt_domain;
    eval { $virt_domain = $clone1->_vm->vm->get_domain_by_name($clone1->name) };
    is(''.$@,'');
    ok($virt_domain,"Expecting ".$clone1->name." in ".$clone1->_vm->host);
    }
}
#############################################################

clean();

for my $vm_name ('KVM') {
my $vm;
eval { $vm = rvd_back->search_vm($vm_name) };

SKIP: {

    my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
    $REMOTE_CONFIG = remote_config($vm_name);
    if (!keys %$REMOTE_CONFIG) {
        my $msg = "skipped, missing the remote configuration for $vm_name in the file "
            .$Test::Ravada::FILE_CONFIG_REMOTE;
        diag($msg);
        skip($msg,10);
    }

    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip($msg,10)   if !$vm;

    my $node = test_node($vm_name)  or next;

    next if !$node || !$node->vm;

    test_bases_node($vm_name, $node);

    test_clone_not_in_node($vm_name, $node);

    test_rsync_newer($vm_name, $node);

    test_domain_no_remote($vm_name, $node);

    test_sync_base($vm_name, $node);
    test_start_twice($vm_name, $node);

    my $domain2 = test_domain($vm_name, $node);
    test_remove_domain_from_local($vm_name, $node, $domain2)    if $domain2;

    my $domain3 = test_domain($vm_name, $node);
    test_remove_domain($vm_name, $node, $domain3)               if $domain3;

        test_domain_starts_in_same_vm($vm_name, $node);
}

}

clean();

done_testing();
