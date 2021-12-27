use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use IPC::Run3 qw(run3);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE_NAME = "zz-test-base-alpine";

use_ok('Ravada');
init();


##################################################################################

sub test_reuse_vm($node) {
    my $domain = create_domain($node->type);
    $domain->add_volume(swap => 1, size => 512 * 1024);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node, user => user_admin);

    my $clone1 = $domain->clone(name => new_domain_name, user => user_admin);

    my $clone2 = $domain->clone(name => new_domain_name, user => user_admin);
    is($clone1->_vm, $clone2->_vm, $clone1->_vm->name);
    is($clone1->_vm->id, $clone2->_vm->id);

    is($clone1->list_instances,1);

    $clone1->migrate($node);
    is($clone1->_data('id_vm'), $node->id);
    $clone2->migrate($node);
    is($clone2->_data('id_vm'), $node->id);
    is($clone1->list_instances,2);

    is($clone1->_vm, $clone2->_vm);
    is($clone1->_vm, $clone2->_vm);
    is($clone1->_vm->{_ssh}, $clone2->_vm->{_ssh});

    is($clone1->is_local, 0 );
    test_remove($clone1, $node);

    my $vm_local = rvd_back->search_vm($node->type,'localhost');
    is($vm_local->is_local, 1);
    $clone2->migrate($vm_local);

    is($clone2->is_local, 1 );
    test_remove($clone2, $node);

}

sub test_remove_req($vm, $node) {
    my $domain = create_domain($vm);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node, user => user_admin);

    my $clone1 = $domain->clone(name => new_domain_name, user => user_admin);
    $clone1->migrate($node);

    my $req = Ravada::Request->remove_domain(
               uid => user_admin->id
             ,name => $clone1->name
    );

    rvd_back->_process_requests_dont_fork();

    is($req->status, 'done');
    is($req->error, '');

    $domain->remove(user_admin);
}

sub test_remove($clone, $node) {

    diag("Testing remove is_local = ".$clone->is_local);

    my @volumes = $clone->list_volumes();
    ok(scalar @volumes,"Expecting volumes in ".$clone->name);

    for my $file ( @volumes ) {
        ok( -e $file, "Expecting file '$file' in localhost");
        my ($out, $err) = $node->run_command("ls $file");
        ok($out, "Expecting file '$file' in ".$node->name) or exit;
    }

    is($clone->list_instances,2) or confess;
    $clone->remove(user_admin);
    for my $file ( @volumes ) {
        ok(! -e $file, "Expecting no file '$file' in localhost") or exit;
        my ($out, $err) = $node->run_command("ls $file");
        ok(!$out, "Expecting no file '$file' in ".$node->name) or exit;
    }
}

sub test_iptables($node, $node2) {
    my $domain = create_domain($node->type);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node, user => user_admin) if !$domain->base_in_vm($node->id);

    my $clone1 = $domain->clone(name => new_domain_name, user => user_admin);

    flush_rules_node($node);

    $clone1->migrate($node) if $clone1->_vm->id != $node->id;

    my $remote_ip1 = '1.1.1.1';
    $clone1->start(user => user_admin, remote_ip => $remote_ip1);
    is($clone1->is_active,1,"[".$node->type."] expecting ".$clone1->name." active "
                                    ." in ".$node->name) or exit;

    my ($local_ip, $local_port)
        = $clone1->display(user_admin) =~ m{(\d+\.\d+\.\d+\.\d+)\:(\d+)};

    # check iptabled added on node
    my @found = search_iptable_remote(
        node => $node
        ,remote_ip => $remote_ip1
        ,local_port => $local_port
    );
    is(scalar @found,1,$node->name." $remote_ip1:$local_port".Dumper(\@found)) or exit;
    @found = search_iptable_remote(
        node => $node
        ,local_port => $local_port
        ,jump => 'DROP'
    );
    is(scalar @found,1,Dumper(\@found));
    #
    # check iptabled NOT added on node2
    @found = search_iptable_remote(
        node => $node2
        ,remote_ip => $remote_ip1
        ,local_port => $local_port
    );
    is(scalar @found,0,$node2->name." $remote_ip1:$local_port".Dumper(\@found)) or exit;
    @found = search_iptable_remote(
        node => $node2
        ,local_port => $local_port
        ,jump => 'DROP'
    );
    is(scalar @found,0,Dumper(\@found));
    #    warn Dumper($list->{filter});

    $clone1->remove(user_admin);

    @found = search_iptable_remote(
        node => $node
        ,remote_ip => $remote_ip1
        ,local_port => $local_port
    );
    is(scalar @found,0,$node->name." $remote_ip1:$local_port".Dumper(\@found)) or exit;
    @found = search_iptable_remote( node => $node
        ,local_port => $local_port
        ,jump => 'DROP'
    );
    is(scalar @found,0,$node->name." ".Dumper(\@found)) or exit;
    $domain->remove(user_admin);
}
sub test_iptables_close($vm, $node) {

    flush_rules_node($vm);
    flush_rules_node($node);

    my $domain = create_domain($vm);

    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node, user => user_admin) if !$domain->base_in_vm($node->id);

    my ($remote_ip1, $remote_ip2) = ('1.1.1.1','2.2.2.2');
    my ($clone_local, $clone_remote) = _create_2_clones_same_port($vm, $node, $domain
                                , $remote_ip1, $remote_ip2);
    isnt($clone_local->_vm->id, $clone_remote->_vm->id);
    my ( $local_port1 ) = $clone_local->display(user_admin)=~ m{://.*:(\d+)};
    my ( $local_port2 ) = $clone_remote->display(user_admin)=~ m{://.*:(\d+)};

    my @found = search_iptable_remote(
       node => $vm
        ,remote_ip => $remote_ip1
        ,local_port => $local_port1
    );
    is(scalar @found,1,$vm->name." $remote_ip1:$local_port1 ".Dumper(\@found)) or exit;

    @found = search_iptable_remote(
       node => $node
        ,remote_ip => $remote_ip2
        ,local_port => $local_port2
    );
    is(scalar @found,1,$node->name." $remote_ip2:$local_port2".Dumper(\@found)) or exit;

    $clone_local->shutdown_now(user_admin);

    @found = search_iptable_remote(
       node => $vm
        ,remote_ip => $remote_ip1
        ,local_port => $local_port1
    );
    is(scalar @found,0,$vm->name." $remote_ip1:$local_port1".Dumper(\@found));

    @found = search_iptable_remote(
       node => $node
        ,remote_ip => $remote_ip2
        ,local_port => $local_port2
    );
    is(scalar @found,1,$node->name." $remote_ip2:$local_port2".Dumper(\@found));

    $clone_remote->shutdown_now(user_admin);

    @found = search_iptable_remote(
       node => $node
        ,remote_ip => $remote_ip2
        ,local_port => $local_port2
    );
    is(scalar @found,0,$node->name." $remote_ip2:$local_port2".Dumper(\@found));

    _remove_domain($domain);
}

sub _remove_clones($domain) {
    _remove_domain($domain,0);
}

sub _remove_domain($domain, $remove_base=0) {
    for my $clone0 ( $domain->clones) {
        Ravada::Request->remove_domain(
            uid => user_admin->id
            ,name=> $clone0->{name}
        );
    }
    Ravada::Request->remove_domain(
        uid => user_admin->id
        ,name=> $domain->{name}
    )
    if $remove_base;

    wait_request();
}

sub _create_2_clones_same_port($vm, $node, $base, $ip_local, $ip_remote) {
    my $clone_local = $base->clone(name => new_domain_name, user => user_admin);
    #TODO: add a flag in start to force node to start in
    $clone_local->{_migrated} = 1;
    my $clone_remote= $base->clone(name => new_domain_name, user => user_admin);
    $clone_remote->migrate($node);

    $clone_local->start(user => user_admin, remote_ip => $ip_local);
    $clone_remote->start(user => user_admin, remote_ip => $ip_remote);

    my ($port_less, $port_more) = ( 0,0 );

    for (1 .. 100 ) {
        my ($port_local) = $clone_local->display(user_admin) =~ m{://.*:(\d+)};
        my ($port_remote) = $clone_remote->display(user_admin) =~ m{://.*:(\d+)};

        return($clone_local, $clone_remote) if $port_local == $port_remote
        || ( $port_less && $port_more && $clone_local->is_local && !$clone_remote->is_local);

        diag("Trying to create 2 clones same port $_ [ port_local=$port_local , port_remote=$port_remote ] ");

        my $clone3 = $base->clone(name => new_domain_name, user => user_admin);
        if ($port_local < $port_remote) {
            $clone3->migrate($vm) if $clone3->_vm->id != $vm->id;
            $clone_local = $clone3;
            $clone_local->start(user => user_admin, remote_ip => $ip_local);
            $port_less++;
        } else {
            $clone3->migrate($node) if $clone3->_vm->id != $node->id;
            $clone_remote = $clone3;
            $clone_remote->start(user => user_admin, remote_ip => $ip_remote);
            $port_more++;
        }
    }
}

sub _start_clone_in_node($vm, $node, $base) {
    my $found_clone;
    for my $try ( 1 .. 20 ) {
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        _remove_tmp($clone1,$vm);
        ok(scalar($base->list_vms) >1) or confess Dumper([map { $_->name } $base->list_vms]);
        eval { $clone1->start(user_admin) };
        is($@,'') or die "Error $@ starting ".$clone1->name;
        $found_clone = $clone1;
        last if $clone1->_vm->id == $node->id;
        ok(scalar($base->list_vms) >1) or confess Dumper([map { $_->name } $base->list_vms]);
    }
    return $found_clone;
}

sub test_removed_local_swap($vm, $node) {
    diag("Testing removed local swap in ".$vm->type);
    my $base = create_domain($vm);
    $base->add_volume(size => 128*1024 , type => 'tmp');
    $base->add_volume(size => 128*1024 , type => 'swap');
    $base->add_volume(size => 128*1024 , type => 'data');
    $base->prepare_base(user_admin);
    $base->set_base_vm(node => $node, user => user_admin);
    ok(scalar($base->list_vms) >1) or die Dumper([map { $_->name } $base->list_vms]);

    my $found_clone = _start_clone_in_node($vm, $node, $base);

    is($found_clone->_vm->id, $node->id) or exit;
    for my $clone_data ($base->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }
    wait_request();
    $base->remove(user_admin);
}

sub test_removed_remote_swap($vm, $node) {
    diag("Testing removed remote swap in ".$vm->type);
    my $base = create_domain($vm);
    $base->add_volume(size => 128*1024 , type => 'tmp');
    $base->add_volume(size => 128*1024 , type => 'swap');
    $base->add_volume(size => 128*1024 , type => 'data');
    $base->prepare_base(user_admin);
    $base->set_base_vm(node => $node, user => user_admin);

    my $found_clone;
    for my $try ( 1 .. 20 ) {
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        $clone1->migrate($node);
        _remove_tmp($clone1,$node);
        $clone1->start(user_admin);
        $found_clone = $clone1;
        last if $clone1->_vm->id == $node->id;
    }
    is($found_clone->_vm->id,$node->id);
    $found_clone->info(user_admin);
    my $node_ip = $node->ip;
    my $clone_v = Ravada::Front::Domain->open($found_clone->id);
    like($clone_v->display(user_admin), qr($node_ip));
    for my $clone_data ($base->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }
    for my $req ( $base->list_requests ) {
        $req->stop;
    }
    $base->remove(user_admin);
}

sub test_removed_base_file($vm, $node) {
    diag("Testing removed base in ".$vm->type);
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(node => $node, user => user_admin);
    is($base->base_in_vm($node->id),1);

    for my $file ( $base->list_files_base ) {
        $node->remove_file($file);
    }

    my $found_req;
    my $found_clone;
    for my $try ( 1 .. 20 ) {
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        $clone1->start(user_admin);
        $found_clone = $clone1;
        my @req = $base->list_requests();
        next if !scalar @req;
        for my $req (@req) {
            if($req->command eq 'set_base_vm') {
                $found_req = $req;
                last;
            }
        }
        last if $found_req;
    }
    ok($found_req,"Expecting request to set base vm");
    wait_request();
    is($base->base_in_vm($node->id),1);
    is(scalar($base->list_vms),2) or exit;
    my $node2 = Ravada::VM->open($node->id);
    is($node2->enabled,1);
    for my $clone_data ($base->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }
    for my $req ( $base->list_requests ) {
        $req->stop;
    }
    $base->remove(user_admin);
}

sub _remove_base_files($base, $node) {
    for my $file ( $base->list_files_base ) {
        $node->remove_file($file);
    }
    $node->refresh_storage_pools();
}

sub _remove_tmp($domain, $vm = $domain->_vm) {
    my ($found_swap, $found_tmp);
    for my $vol ( $domain->list_volumes ) {
        if ( $vol =~ /TMP/ ) {
            $vm->remove_file($vol);
            $found_tmp= 1;
        }
        if ( $vol =~ /SWAP/ ) {
            $vm->remove_file($vol);
            $found_swap = 1;
        }
    }
    die "Error: no swap found in ".$domain->name if !$found_swap;
    die "Error: no tmp found in ".$domain->name if !$found_tmp;
    $vm->refresh_storage_pools();

}

sub test_removed_base_file_and_swap_remote($vm, $node) {
    diag("Testing removed remote base and swap in ".$vm->type);
    my $base = create_domain($vm);
    $base->add_volume(size => 128*1024 , type => 'tmp');
    $base->add_volume(size => 128*1024 , type => 'swap');
    $base->add_volume(size => 128*1024 , type => 'data');
    $base->prepare_base(user_admin);
    $base->set_base_vm(node => $node, user => user_admin);

    my $found_req;
    my $found_clone;
    for my $try ( 1 .. 20 ) {
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        $clone1->migrate($node);
        _remove_tmp($clone1,$node);
        _remove_base_files($base,$node);
        $clone1->start(user_admin);
        $found_clone = $clone1;
        my @req = $base->list_requests();
        last if !$base->base_in_vm($node->id);
        last if $base->list_requests();
    }
    ok(grep { $_->command eq 'set_base_vm' } $base->list_requests)
        or die $vm->type." ".Dumper([$base->list_requests]);
    is(scalar($base->list_vms),1) or exit;
    wait_request(debug => 0);
    is($base->base_in_vm($node->id),1);
    my $node2 = Ravada::VM->open($node->id);
    is($node2->enabled,1);
    for my $clone_data ($base->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }
    for my $req ( $base->list_requests ) {
        $req->stop;
    }
    $base->remove(user_admin);
}

sub test_set_vm_fail($vm, $node) {
    return if $vm->type ne 'KVM';
    diag("Test set vm fail");
    my $base = create_domain($vm);
    $base->volatile_clones(1);
    my $pool2 = create_storage_pool($vm);
    $vm->default_storage_pool_name($pool2);
    $base->add_volume( size => 11000 );
    $base->prepare_base(user_admin);

    $base->_set_base_vm_db($node->id, 1);

    my $req = Ravada::Request->set_base_vm(
        id_domain => $base->id
        , id_vm => $node->id
        , value => 1
        , uid => user_admin->id
    );
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    like($req->error, qr/storage pool/i);

    is($base->base_in_vm($node->id),0) or exit;
    $req = Ravada::Request->clone(
        id_domain => $base->id
        ,number => 3
        ,uid => user_admin->id
    );
    rvd_back->_process_all_requests_dont_fork();
    rvd_back->_process_all_requests_dont_fork();
    is($req->status, 'done');
    is($req->error,'');

    ok(scalar($base->clones));

    _remove_domain($base);
    my $pool = $vm->vm->get_storage_pool_by_name($pool2);
    eval {
        $pool->destroy();
        $pool->undefine();
    };
    warn $@ if$@ && $@ !~ /libvirt error code: 49,/;

    $vm->default_storage_pool_name('default');
}

sub test_set_vm($vm, $node) {
    my $base = create_domain($vm);
    my $info = $base->info(user_admin);
    is($info->{bases}->{$vm->id},0);

    my $req = Ravada::Request->set_base_vm(
        id_domain => $base->id
        , id_vm => $node->id
        , value => 1
        , uid => user_admin->id
    );
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    like($req->error, qr{^($|rsync done)});

    is($base->_vm->id, $vm->id);

    my $base2 = Ravada::Domain->open($base->id);
    is($base2->_vm->id, $vm->id);

    $info = $base2->info(user_admin);
    is($info->{bases}->{$vm->id},1,Dumper($info->{bases})) or exit;
    is($info->{bases}->{$node->id},1,$node->id." "
        .Dumper($info->{bases})) or exit;

    is($base->list_instances,2) or exit;

    my $base_f = Ravada::Front::Domain->open($base->id);
    $info = $base_f->info(user_admin);
    is($info->{bases}->{$vm->id},1) or exit;
    is($info->{bases}->{$node->id},1) or exit;

    is($base_f->list_instances,2) or exit;

    test_bind_ip($node, $base,'1.2.3.4',1);
    test_bind_ip($node, $base,'1.2.3.4');
    test_bind_ip($node, $base);
    $base->remove(user_admin);
    is(scalar($base->list_instances),undef);
}

sub test_bind_ip($node, $base, $remote_ip=undef, $config=undef) {
    if ($config) {
        rvd_back->display_ip("127.0.0.1");
    }
    my @clone;
    my $clone_2;
    my @remote_ip;
    @remote_ip = ( remote_ip => $remote_ip ) if $remote_ip;
    for (1 .. 20) {
        my $clone= $base->clone( user => user_admin, name => new_domain_name);
        if ($clone->type eq 'KVM') {
            $clone->_set_spice_ip(undef,'2.3.4.5');
            my $cloneb = Ravada::Domain->open($clone->id);
        }
        my $req = Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $clone->id
            ,@remote_ip
        );
        wait_request();
        like($req->error, qr{^($|rsync done)});
        my $clone_v = Ravada::Domain->open($clone->id);
        if ($clone_v->is_local) {
            if (!$config) {
                my $vm_ip = $clone_v->_vm->ip;
                like($clone_v->display(user_admin),qr($vm_ip)) or confess $clone_v->name;
            } else {
                like($clone_v->display(user_admin),qr(127.0.0.1)) or die $clone_v->name;
            }
        } else {
            my $node_ip = $node->ip;
            like($clone_v->display(user_admin), qr($node_ip));
        }
        is($req->status,'done');
        like($req->error, qr{^($|rsync done)});
        push @clone,($clone);
        $clone_2 = Ravada::Domain->open($clone->id);
        last if $clone_2->_vm->id == $node->id;
    }
    my $node_ip = $node->ip;
    is($clone_2->_vm->id, $node->id) or exit;
    like($clone_2->display(user_admin),qr($node_ip)) or exit;
    for (@clone) {
        $_->remove(user_admin);
    }
    rvd_back->display_ip("") if $config;
}

sub test_volatile($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);
    $base->volatile_clones(1);

    my @clones;
    for ( 1 .. 10 ) {
        my $clone = $base->clone(user => user_admin, name => new_domain_name);
        is($clone->_vm->is_active,1);
        is($clone->is_active(),1,"Expecting clone ".$clone->name." active on ".$clone->_vm->name);
        push @clones,($clone);
        last if $clone->_vm->id == $node->id;
    }
    is($clones[-1]->_vm->id, $node->id);

    is($clones[-1]->list_instances,1,Dumper([$clones[-1]->list_instances])) or exit;

    for (@clones) {
        $_->remove(user_admin);
    }
    $base->remove(user_admin);
    is(scalar($base->list_instances),undef,Dumper([$base->list_instances])) or exit;
}

sub test_volatile_req($vm, $node) {
    my $base = create_domain($vm);
    $base->volatile_clones(1);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);
    ok($base->base_in_vm($node->id));
    my @clones;
    my $clone;
    for ( 1 .. 20 ) {
        my $clone_name = new_domain_name;
        my $req = Ravada::Request->create_domain(
           id_base => $base->id
             ,name => $clone_name
            ,id_owner => user_admin->id
        );
        rvd_back->_process_all_requests_dont_fork();
        is($req->status, 'done');
        is($req->error,'');

        $clone = rvd_back->search_domain($clone_name);
        is($clone->is_active(),1,"[".$vm->type."] expecting clone ".$clone->name
            ." active on node ".$clone->_vm->name);
        push @clones,($clone);
        last if $clone->_vm->id == $node->id;
    }
    is($clone->_vm->id, $node->id) or exit;

    shutdown_domain_internal($clone);
    rvd_back->_cmd_refresh_vms();
    for my $vol ( $clone->list_volumes ) {
        ok(!$vm->file_exists($vol),$vol) or exit;
        ok(!$node->file_exists($vol),$vol) or exit;
    }
    _remove_domain($base);
}

sub test_volatile_req_clone($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);
    $base->volatile_clones(1);
    ok($base->base_in_vm($node->id));

    my $clone;
    for ( 1 .. 20 ) {
        my $req = Ravada::Request->clone(
           id_domain => $base->id
            ,number => 3
            ,uid => user_admin->id
        );
        rvd_back->_process_all_requests_dont_fork();
        rvd_back->_process_all_requests_dont_fork();
        is($req->status, 'done');
        is($req->error,'');

        is(scalar($base->clones),3) or exit;
        ($clone) = grep { $_->{id_vm} == $node->id } $base->clones;
        last if $clone;
    }
    is($clone->{id_vm}, $node->id) or exit;

    my @vols;
    my @clones;
    for my $clone_data ($base->clones) {
        my $clone2 = Ravada::Domain->open($clone_data->{id});
        push @clones,($clone2);
        push @vols,($clone2->list_volumes);
        shutdown_domain_internal($clone2);
    }
    rvd_back->_cmd_refresh_vms();
    for my $vol ( @vols ) {
        ok(!$vm->file_exists($vol),$vol) or exit;
        ok(!$node->file_exists($vol),$vol) or exit;
    }
    my @req;
    for my $clone2 (@clones) {
        my $req = Ravada::Request->remove_domain(
            name => $clone2->name
            ,uid => user_admin->id
        );
        push @req,($req);
    }
    wait_request();
    for my $req (@req) {
        is($req->status,'done');
        like($req->error,qr/(^$|Unknown)/);
    }
    $base->remove(user_admin);
}


sub test_volatile_tmp_owner($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);
    $base->set_base_vm(user => user_admin, node => $node);

    my $user = Ravada::Auth::SQL::add_user(name => 'mcnulty', is_temporary => 1);
    my $owner = Ravada::Auth::SQL->search_by_id($user->id);
    ok($owner) or exit;

    my @clones;
    for ( 1 .. 10 ) {
        my $clone_name = new_domain_name;
        my $req = Ravada::Request->create_domain(
           id_base => $base->id
             ,name => $clone_name
            ,id_owner => $user->id
        );
        rvd_back->_process_all_requests_dont_fork();
        is($req->status, 'done');
        is($req->error,'');

        my $clone = rvd_back->search_domain($clone_name);
        is($clone->is_active,1,"[".$node->type."] expecting ".$clone->name." active "
                                    ." in ".$clone->_vm->name) or exit;
        push @clones,($clone);
        last if $clone->_vm->id == $node->id;
    }
    is($clones[-1]->_vm->id, $node->id) or exit;

    for (@clones) {
        $_->shutdown_now(user_admin);
        $_->remove(user_admin);
    }
    $base->remove(user_admin);
    $user->remove();
}

sub test_clone_remote($vm, $node) {
    my $base = create_domain($vm);
    is($base->list_instances,1);
    $base->prepare_base(user_admin);

    my $bases_vm = $base->_bases_vm();
    is($bases_vm->{$vm->id},1) or exit;
    $base->set_base_vm(user => user_admin, node => $node);
    is($base->list_instances,2);

    $bases_vm = $base->_bases_vm();
    is($bases_vm->{$node->id},1) or exit;

    $base->migrate($node);

    my $clone = $base->clone(
        name => new_domain_name
        ,user => user_admin
    );
    ok($clone->_vm->name, $node->name);

    is($clone->list_instances,1);

    _test_old_base($base, $vm);
    _test_clones($base, $vm);
    $clone->remove(user_admin);
    is($clone->list_instances,undef);
    $base->remove(user_admin);
    is($base->list_instances,undef);
}

sub _test_old_base($base, $vm) {
    my $sth = connector->dbh->prepare(
        "DELETE FROM bases_vm "
        ." WHERE id_domain=? AND id_vm=?"
    );
    $sth->execute($base->id, $vm->id);

    my $base_f = Ravada::Front::Domain->open($base->id);

    my $info = $base_f->info(user_admin);
    is($info->{bases}->{$vm->id},1) ;

    is(scalar keys %{$info->{bases}}, 2);
}

sub _test_clones($base, $vm) {
    my $info = $base->info(user_admin);
    ok($info->{clones}) or return;
    ok($info->{clones}->{$vm->id}) or confess;
    is(scalar @{$info->{clones}->{$vm->id}},1 );
}

sub test_remove_base($vm, $node, $volatile) {
    my $base = create_domain($vm);
    $base->volatile_clones($volatile);
    my @volumes0 = $base->list_volumes( device => 'disk');
    ok(!grep(/iso$/,@volumes0),"Expecting no iso files on device list ".Dumper(\@volumes0))
        or exit;
    $base->prepare_base(user_admin);

    my @volumes = $base->list_files_base();
    $base->set_base_vm(node => $node, user => user_admin);
    for my $file ( @volumes ) {
        my ($out, $err) = $node->run_command("ls $file");
        ok($out, "Expecting file '$file' in ".$node->name) or exit;
    }

    $base->remove_base_vm(node => $node, user => user_admin);
    for my $file ( @volumes , @volumes0 ) {
        ok(!$node->file_exists($file));
        ok(-e $file, "Expecting file '$file' in local") or exit;
    }
    isnt($base->_data('id_vm'), $node->id);

    $base->set_base_vm(node => $node, user => user_admin);
    is(scalar($base->list_vms), 2) or exit;
    $base->remove_base(user_admin);

    my @req = $base->list_requests();
    is(scalar @req,2);
    ok(grep {$_->command eq 'remove_base_vm' } @req) or die Dumper(\@req);
    wait_request( debug => 0 );

    for my $file ( @volumes ) {
        ok(!-e $file, "Expecting no file '$file' in local") or exit;
        my ($out, $err) = $node->run_command("ls $file");
        ok(!$out, "Expecting no file '$file' in ".$node->name) or exit;
    }

    $base->remove(user_admin);
}

sub _check_internal_autostart($domain, $expected) {
    if ($domain->type eq 'KVM') {
        ok($domain->domain->get_autostart)  if $expected;
        ok(!$domain->domain->get_autostart) if !$expected;
    } elsif ($domain->type eq 'Void') {
        ok($domain->_value('autostart'))    if $expected;
        ok(!$domain->_value('autostart'),$domain->name) or exit   if !$expected;
    } else {
        diag("WARNING: I don't know how to check ".$domain->type." internal autostart");
    }
}

# check autostart is managed by Ravada when nodes
sub test_autostart($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    my $domain = $base->clone(name => new_domain_name , user => user_admin);
    $domain->autostart(1,user_admin);
    is($domain->autostart,1);
    _check_internal_autostart($domain,1);

    $base->set_base_vm(node => $node, user => user_admin);
    is($domain->autostart,1) or exit;
    _check_internal_autostart($domain,0);

    $domain->remove(user_admin);
    $base->remove(user_admin);
}

sub test_duplicated_set_base_vm($vm, $node) {
    diag("Test duplicated set base vm");
    my $domain = create_domain($vm);
    my $req = Ravada::Request->set_base_vm(id_vm => $node->id
        , uid => 1
        , id_domain => $domain->id
        , at => time + 3
    );
    my $req2 = Ravada::Request->set_base_vm(id_vm => $node->id
        , uid => 2
        , id_domain => $domain->id
        , at => time + 4
    );
    ok($req2) or exit;
    is($req2->id, $req->id) or exit;
    my $req3 = Ravada::Request->remove_base_vm(id_vm => $node->id
        , uid => 1
        , id_domain => $domain->id
        , at => time + 3
    );
    my $req4 = Ravada::Request->remove_base_vm(id_vm => $node->id
        , uid => 2
        , id_domain => $domain->id
        , at => time + 4
    );
    ok($req4) or exit;
    is($req4->id, $req3->id) or exit;
    my $req5 = Ravada::Request->set_base_vm(id_vm => 999
        , uid => 2
        , id_domain => $domain->id
        , at => time + 4
    );
    ok($req5) or exit;

    is($node->is_locked,1);
    my $sth = connector->dbh->prepare("DELETE FROM requests");
    $sth->execute;
    $domain->remove(user_admin);
}

sub test_create_active($vm, $node) {
    diag("Test create active machine");
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(vm => $node, user => user_admin);
    my $remote_ip = $node->ip or confess "No node ip";

    my $clone;
    for ( 1 .. 20 ) {
        my $name = new_domain_name();
        my $req = Ravada::Request->create_domain(
            id_base => $base->id
            ,name => $name
            ,start => 1
            ,remote_ip => '1.2.3.4'
            ,id_owner => user_admin->id
        );
        wait_request(debug => 0);
        $clone = rvd_front->search_domain($name);
        ok($vm->search_domain($name),"Expecting clone $name in master node") or exit;
        last if $clone->display(user_admin) =~ /$remote_ip/;
    }
    like($clone->display(user_admin), qr($remote_ip));

    my $clone2 = rvd_front->search_domain($clone->name);
    my $info = $clone2->info(user_admin);
    is($info->{display}->{ip}, $remote_ip) or die Dumper($info->{display});

    test_keep_node($node, $clone);

    _remove_domain($base);
}

sub test_keep_node($node, $clone) {
    # check clone is always started in the same node
    my $node_ip = $node->ip;
    for ( 1 .. 3 ) {
        Ravada::Request->shutdown_domain(id_domain => $clone->id, uid => user_admin->id
            , timeout => 1);
        wait_request();

        {
            my $clone2 = Ravada::Domain->open($clone->id);
            is($clone2->is_active,0);
            is($clone2->_vm->id, $node->id);
            is($clone2->_data('id_vm'), $node->id);
        }

        Ravada::Request->start_domain(id_domain => $clone->id, uid => user_admin->id
            ,remote_ip => '1.2.3.4'
        );
        wait_request();
        {
            my $clone3 = Ravada::Domain->open($clone->id);
            is($clone3->is_active,1);
            is($clone3->_vm->id, $node->id, $clone3->name) or exit;
            like($clone3->display(user_admin),qr($node_ip));
            $clone3->shutdown_now(user_admin);
            $clone3->migrate($node);
        }
    }
}

sub test_base_unset($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(vm => $node, user => user_admin);

    my $clone = $base->clone(name => new_domain_name, user => user_admin);
    $clone->migrate($node);
    $base->set_base_vm(id_vm => $node->id,value => 0, user => user_admin);
    is($base->base_in_vm($node->id),0) or exit;
    is(Ravada::Domain::base_in_vm($base->id,$node->id),0) or exit;
    my $clone2 = Ravada::Domain->open($clone->id);
    $clone2->start(user_admin);

    is($clone2->_vm->name, $vm->name) or exit;

    _remove_domain($base);
}

sub test_change_base($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(vm => $node, user => user_admin);
    my @volumes = ($base->list_files_base(), $base->list_volumes);
    my $req = Ravada::Request->change_hardware(
        uid => 1
        ,id_domain => $base->id
        ,hardware => 'memory'
        ,data => { memory => 100 }

    );
    wait_request();
    is($req->status,'done');
    is($req->error,'');
    for my $vol (@volumes) {
        ok(-e $vol,$vol);
        ok($node->file_exists($vol), $vol)  if $vol !~ /iso$/;
    }
    $base->remove(user_admin);
}

sub test_change_clone($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(vm => $node, user => user_admin);
    my @volumes_base = ($base->list_files_base() ,$base->list_volumes);

    my $clone = $base->clone( user => user_admin,name => new_domain_name());
    my @volumes_clone = ($clone->list_files_base(), $clone->list_volumes);

    my @args = (
        uid => 1
        ,hardware => 'memory'
        ,data => { memory => 100 }
    );

    my $reqb = Ravada::Request->change_hardware(@args ,id_domain => $base->id);
    my $reqc = Ravada::Request->change_hardware(@args ,id_domain => $clone->id);
    wait_request();
    is($reqb->status,'done');
    is($reqb->error,'');
    is($reqc->status,'done');
    is($reqc->error,'');
    for my $vol (@volumes_base) {
        ok(-e $vol);
        ok($node->file_exists($vol), $vol)  if $vol !~ /iso$/;
    }
    for my $vol (@volumes_clone) {
        ok(-e $vol, $vol);
        ok(!$node->file_exists($vol), $vol) if $vol !~ /iso$/;
    }
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_fill_memory($vm, $node, $migrate) {
    #TODO: Void VMs
    return if $vm->type eq 'Void';
    diag("Testing fill memory ".$vm->type.", migrate=$migrate");

    my $base = rvd_back->search_domain($BASE_NAME);
    $base = import_domain('KVM', $BASE_NAME, 1) if !$base;
    if (!$base) {
        diag("SKIPPING: base $BASE_NAME must be installed to test");
        return;
    }
    $base->prepare_base(user_admin) if !$base->is_base;
    Ravada::Request->set_base_vm(id_vm => $node->id
        ,uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request();

    my $master_free_memory = $vm->free_memory;
    my $node_free_memory = $node->free_memory;

    my $memory = $master_free_memory/3;
    if ( $node_free_memory < $master_free_memory ) {
        $memory = $node_free_memory/3;
    }

    my $error;
    my %nodes;
    my @clones;
    for ( 1 .. 100  ) {
        my $clone_name = new_domain_name();
        my $req = Ravada::Request->create_domain(
            name => $clone_name
            ,id_owner => user_admin->id
            ,id_base => $base->id
            ,memory => int($memory)
        );
        wait_request(debug => 0);
        is($req->error, '');
        is($req->status,'done');
        push @clones,($clone_name);
        my $clone = rvd_back->search_domain($clone_name) or last;
        ok($clone,"Expecting clone $clone_name") or exit;
        $clone->migrate($node) if $migrate;
        wait_request(debug => 0);
        eval { $clone->start(user_admin) };
        $error = $@;
        like($error, qr/(^$|No free memory)/);
        exit if $error && $error !~ /No free memory/;
        last if $error;

        my $clone_2 = Ravada::Domain->open($clone->id);
        $nodes{$clone_2->_vm->name}++;

        last if $migrate && exists $nodes{$vm->name} && $nodes{$vm->name} > 2;
        if (scalar keys(%nodes) > 0) {
            $memory = int($memory*1.5);
        }
    }
    ok(exists $nodes{$vm->name},"Expecting some clones to node ".$vm->name." ".$vm->id);
    ok(exists $nodes{$node->name},"Expecting some clones to node ".$node->name." ".$node->id) or exit;
    _remove_clones($base);
}

sub test_migrate($vm, $node) {
    diag("Test migrate");
    my $domain = create_domain($vm);

    $domain->migrate($node);

    is($domain->_data('id_vm'), $node->id);
    is($domain->_vm->id, $node->id);

    $domain->start(user_admin);
    is($domain->_data('id_vm'), $node->id);
    is($domain->_vm->id, $node->id);

    is($domain->is_active,1);

    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->is_active,1);
    is($domain2->_data('id_vm'), $node->id);
    is($domain2->_vm->id, $node->id);

    $domain->shutdown_now(user_admin);
    start_domain_internal($domain);

    my $domain3 = Ravada::Domain->open($domain->id);
    $domain3->start(user_admin);
    is($domain3->is_active,1);
    is($domain3->_data('id_vm'), $node->id);
    is($domain3->_vm->id, $node->id);

    is($domain3->has_non_shared_storage($vm),1) or exit;

    $domain->remove(user_admin);
}

sub test_check_instances($vm, $node) {
    my $domain = create_domain($vm);

    $domain->migrate($node);
    start_domain_internal($domain);
    is($domain->_data('id_vm'), $node->id );
    is($domain->_vm->id, $node->id);

    my @instances = $domain->list_instances();
    is(scalar(@instances),2);

    my $sth = connector->dbh->prepare("DELETE FROM domain_instances WHERE id_domain=?");
    $sth->execute($domain->id);

    my @instances2 = $domain->list_instances();
    is(scalar(@instances2),0);

    $domain->_data( id_vm => $vm->id );
    $domain->_vm($vm);
    $domain->start(user_admin);

    is($domain->_data('id_vm'), $node->id );
    is($domain->_vm->id, $node->id);

    my @instances3 = $domain->list_instances();
    is(scalar(@instances3),2, "Expecting 2 instances of ".$domain->name);

    $domain->remove(user_admin);
}

sub test_migrate_req($vm, $node) {
    my $domain = create_domain($vm);
    $domain->start(user_admin);
    my $req = Ravada::Request->migrate(
        id_domain => $domain->id
        , id_node => $node->id
        , uid => user_admin->id
        , start => 1
        , shutdown => 1
        , shutdown_timeout => 10
        , remote_ip => '1.2.2.34'
        , retry => 10
    );
    for ( 1 .. 30 ) {
        wait_request( debug => 0, check_error => 0);
        is($req->status,'done');
        last if !$req->error || $req->error =~ /rsync done/;
        sleep 1;
    }
    like($req->error,qr{^($|rsync done)}) or exit;

    my $domain3 = Ravada::Domain->open($domain->id);
    is($domain3->is_active,1);
    is($domain3->_data('id_vm'), $node->id);
    is($domain3->_vm->id, $node->id);

    test_change_hardware($vm, $node, $domain);

    $domain->remove(user_admin);
}

sub _migrate($domain, $node,$active) {
    return if $domain->_data('id_vm') == $node->id
    && $domain->is_active() == $active;

    my $req = Ravada::Request->migrate(
        id_domain => $domain->id
        , id_node => $node->id
        , uid => user_admin->id
        , start => $active
        , shutdown => 1
        , shutdown_timeout => 10
        , remote_ip => '1.2.2.34'
        , retry => 10
    );
    for ( 1 .. 30 ) {
        wait_request( debug => 0, check_error => 0);
        last if $req->status eq 'done';
        sleep 1;
    }

    my $domain2 = Ravada::Domain->open($domain->id);
    die "Error: domain ".$domain2->name." should be in node ".$node->name
    .". It is in ".$domain2->_vm->name
    if $node->id != $domain2->_vm->id;

    die "Error: domain ".$domain2->name." should be active=$active, got ".$domain2->is_active
    if $domain2->is_active != $active;
}

sub test_change_hardware($vm, $node, $domain, $active = 0) {
    _migrate($domain, $node, $active);

    my $mem = $domain->info(user_admin)->{memory};

    my $new_mem = int($mem*0.9)-1;

    my $req1 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => { memory => $new_mem }
    );

    wait_request(debug => 0);
    is($req1->status, 'done');
    is($req1->error, '');

    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->_data('id_vm'), $domain->_data('id_vm')) or exit;

}

sub _get_backing_files($volume0) {
    my @bf;
    my $volume = $volume0;
    for (;;) {
        my @cmd = ("qemu-img","info",$volume);
        my ($in, $out, $err);
        run3(\@cmd, \$in, \$out, \$err);
        my ($bf) = $out =~ m{backing file: (.*)}m;
        return @bf if !$bf;
        push @bf,($bf);
        $volume = $bf;
    }
}

sub test_volumes_levels($domain, $level) {

    for my $vol ($domain->list_volumes_info) {
        next if !$vol->file;
        my @backings = _get_backing_files($vol->file);
        for my $file (@backings) {
            like($file ,qr{-vd[a-z][\.-]},$domain->name) or exit;
            unlike($file,qr{--+},$domain->name) or exit;
        }
        is(scalar(@backings), $level, "Expecting ".$domain->name
            ." : ".$vol->file." level $level\n".Dumper(\@backings)) or exit;
    }
}

sub _get_backing_xml($disk) {
    my ($source) = $disk->findnodes("source");
    return if !$source;

    my @bf = ($source->getAttribute('file'));

    my ($backingstore2) = $disk->findnodes("backingStore");
    push @bf,(_get_backing_xml($backingstore2)) if $backingstore2;

    return @bf;
}

sub test_domain_volumes_levels($domain, $level) {
    my $doc =XML::LibXML->load_xml(string => $domain->xml_description());

    my $found = 0;
    for my $disk ($doc->findnodes("/domain/devices/disk")) {

        my ($source) = $disk->findnodes("source")
        or next;

        my $file = $source->getAttribute('file');
        my @backings = _get_backing_xml($disk);
        is(scalar(@backings), $level, "Expecting ".$domain->name
            ." : ".$file." level $level\n".Dumper(\@backings)) or confess;
        $found++;
    }
    confess "Error: no disk devices found" if !$found;
}

sub test_nested_base($vm, $node, $levels=1) {

    my $base0 = create_domain($vm);
    $base0->add_volume(swap => 1, size => 10 * 1024);
    $base0->add_volume(type => 'tmp', size => 10 * 1024);
    $base0->add_volume(type => 'data', size => 10 * 1024);

    my $base1 = $base0;
    my $clone;
    my @bases = ( );
    for my $n ( 1 .. $levels ) {
        diag("Cloning from ".$base1->name." level $n / $levels");
        $base1->prepare_base(user_admin) if !$base1->is_base;
        $clone = $base1->clone(
            name => new_domain_name
            ,user => user_admin
        );
        is($clone->id_base,$base1->id);
        push @bases,($base1);
        wait_request();
        test_volumes_levels($clone, $n);
        test_domain_volumes_levels($clone, $n+1);
        $base1 = $clone;
    }

    _test_migrate_nested($vm, $node, \@bases, $clone, $levels);
    $base0->remove_base_vm(vm => $node, user => user_admin);
    _test_migrate_nested($vm, $node, \@bases, $clone, $levels);
    my ($file) = $base0->list_files_base;
    $node->remove_file($file);

    for my $domain ($clone, reverse @bases ) {
        $domain->remove(user_admin);
    }
}

sub _test_migrate_nested($vm, $node, $bases, $clone, $levels) {
    my $req = Ravada::Request->migrate(
        id_node => $node->id
        ,id_domain => $clone->id
        ,uid => user_admin->id
        ,shutdown => 1
    );
    for ( 1 .. $levels+3 ) {
        last if $req->status eq 'done';
        wait_request(debug => 0, check_error => 0);
    }
    is($req->error,'');
    is($req->status,'done');
    for my $base ( @$bases ) {
        is($base->is_base,1,"Expecting ".$base->name." is base") or exit;
        is($base->base_in_vm($node->id),1);
    }
    my $clone2 = Ravada::Domain->open($clone->id);
    is($clone2->_vm->id,$node->id) or exit;
    eval { $clone2->start(user_admin) };
    is(''.$@, '', $clone2->name) or exit;
}

sub test_display_ip($vm, $node, $set_localhost_dp=0) {
    my $vm_ip = $vm->ip;
    if ($set_localhost_dp == 1) {
        $vm_ip = "192.168.122.1";
        rvd_back->display_ip($vm_ip);
    } elsif ($set_localhost_dp == 2) {
        $vm_ip = "192.168.130.1";
        $vm->display_ip($vm_ip);
    }

    eval {
        $node->display_ip("1.2.3.4");
    };
    like($@,qr(is not in any interface in node)i);

    my $display_ip_1 = "127.0.0.1";
    $node->display_ip($display_ip_1);
    is($node->display_ip,$display_ip_1);

    my $domain = create_domain($vm);
    $domain->add_volume(size => 10*1024 , type => 'tmp');
    $domain->add_volume(size => 10*1024 , type => 'swap');

    my $req = Ravada::Request->start_domain(
        remote_ip => '3.4.5.7'
        ,id_domain => $domain->id
        ,uid => user_admin->id
    );
    wait_request();
    is($domain->display_info(user_admin)->{ip}, $vm_ip);

    $domain->shutdown_now(user_admin);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(node => $node, user => user_admin);

    my $domain2 = _start_clone_in_node($vm, $node, $domain);

    is($domain2->_vm->id,$node->id) or exit;
    is($domain2->display_info(user_admin)->{ip},$display_ip_1) or exit;

    _remove_domain($domain);

    $node->_data(display_ip => '');
    rvd_back->display_ip('') if $set_localhost_dp;
    $vm->display_ip('')      if $set_localhost_dp;
}

sub test_nat($vm, $node, $set_localhost_natip=0) {
    my $nat_ip_1 = "5.6.7.8";
    $node->nat_ip($nat_ip_1);

    my $vm_ip = $vm->ip;
    if ($set_localhost_natip == 1) {
        $vm_ip = "22.22.22.22";
        rvd_back->nat_ip($vm_ip);
    } elsif ($set_localhost_natip == 2) {
        $vm_ip = "33.33.33.33";
        $vm->nat_ip($vm_ip);
    }

    $node->nat_ip($nat_ip_1);
    is($node->nat_ip,$nat_ip_1);

    my $domain = create_domain($vm);
    $domain->add_volume(size => 10*1024 , type => 'tmp');
    $domain->add_volume(size => 10*1024 , type => 'swap');

    my $req = Ravada::Request->start_domain(
        remote_ip => '3.4.5.7'
        ,id_domain => $domain->id
        ,uid => user_admin->id
    );
    wait_request();
    is($domain->display_info(user_admin)->{ip}, $vm_ip) or confess;

    $domain->shutdown_now(user_admin);
    $domain->prepare_base(user_admin);

    $domain->set_base_vm(node => $node, user => user_admin);

    my $domain2 = _start_clone_in_node($vm, $node, $domain);

    is($domain2->_vm->id,$node->id) or exit;
    is($domain2->display_info(user_admin)->{ip},$nat_ip_1);

    _remove_domain($domain);

    $node->_data(nat_ip => '');
    rvd_back->nat_ip('')    if $set_localhost_natip;
    $vm->nat_ip('')         if $set_localhost_natip;

    $node->_data(nat_ip => '');
}

sub _download_alpine64 {
    my $id_iso = search_id_iso('Alpine%64');

    my $req = Ravada::Request->download(
             id_iso => $id_iso
    );
    wait_request();
    is($req->error, '');
    is($req->status,'done') or exit;
}

sub test_displays($vm, $node, $no_builtin=0) {
    my $base;
    if ( $vm->type eq 'KVM') {
        $base = rvd_back->search_domain($BASE_NAME);
        $base = import_domain('KVM', $BASE_NAME, 1) if !$base;
    } else {
        return;
        #        $base = create_domain($vm);
    }
    _download_alpine64();

    my $domain = $base->clone(name => new_domain_name, user => user_admin);
    my $n_displays = 1;
    $n_displays++ if $vm->tls_ca();
    if ($no_builtin) {
        my $req_addh = Ravada::Request->add_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,name => 'display'
            ,data => { driver => 'x2go' }
        );
        wait_request(debug => 0);
        is($req_addh->status,'done');
        is($req_addh->error,'');
        $n_displays++;
    }
    $domain->start( user => user_admin
        ,remote_ip => '1.1.1.1'
        ,id_vm => $vm->id
    );
    wait_request(debug => 0);
    my $domain_f0 = Ravada::Front::Domain->open($domain->id);
    my @displays_f0 = $domain_f0->display_info(user_admin);
    is(scalar(@displays_f0),$n_displays) or die Dumper($domain->name,\@displays_f0);

    my @displays0 = $domain->display_info(user_admin);
    is(scalar(@displays0),2) or die Dumper(\@displays0);

    $domain->shutdown_now(user_admin);
    my $req = Ravada::Request->migrate(
        id_domain => $domain->id
        , id_node => $node->id
        , uid => user_admin->id
        , start => 1
        , shutdown => 1
        , shutdown_timeout => 10
        , remote_ip => '1.2.2.34'
        , retry => 10
    );
    for ( 1 .. 30 ) {
        wait_request( debug => 0, check_error => 0);
        is($req->status,'done');
        last if !$req->error || $req->error =~ /rsync done/;
        sleep 1;
    }
    like($req->error,qr{^($|rsync done)}) or exit;

    $domain = Ravada::Domain->open($domain->id);
    my @displays1 = grep {!$_->{is_secondary} } $domain->display_info(user_admin);
    is(scalar(@displays1),1,Dumper(\@displays1));

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my @displays_f = grep {!$_->{is_secondary} } $domain_f->display_info(user_admin);
    is(scalar(@displays_f),$n_displays-1,Dumper(\@displays_f));

    $domain->remove(user_admin);
}

##################################################################################

if ($>)  {
    diag("SKIPPED: Test must run as root");
    done_testing();
    exit;
}

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;
my $tls;

for my $vm_name (vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        my $REMOTE_CONFIG = remote_config($vm_name);
        if (!keys %$REMOTE_CONFIG) {
            my $msg = "skipped, missing the remote configuration for $vm_name in the file "
                .$Test::Ravada::FILE_CONFIG_REMOTE;
            diag($msg);
            skip($msg,10);
        }

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        $tls = 1 if check_libvirt_tls() && $vm_name eq 'KVM';
        my $node = remote_node($vm_name)  or next;
        clean_remote_node($node);

        ok($node->vm,"[$vm_name] expecting a VM inside the node") or do {
            remove_node($node);
            next;
        };
        is($node->is_local,0,"Expecting ".$node->name." ".$node->ip." is remote" ) or BAIL_OUT();

        start_node($node);

        # test displays with no builtin added
        test_displays($vm, $node,1) if $tls;
        # test displays with only builtin
        test_displays($vm, $node) if $tls;

        test_iptables_close($vm, $node);

        test_nat($vm, $node, 1); # also set deprecated localhost ip

        test_duplicated_set_base_vm($vm, $node);
        if ($vm_name eq 'KVM') {
            test_nested_base($vm, $node, 3);
            test_nested_base($vm, $node);
        }

        test_removed_base_file($vm, $node);

        test_check_instances($vm, $node);
        test_migrate($vm, $node);
        test_migrate_req($vm, $node);

        test_nat($vm, $node);
        test_nat($vm, $node, 1); # also set deprecated localhost ip
        test_nat($vm, $node, 2); # also set localhost ip
        test_display_ip($vm, $node);
        test_display_ip($vm, $node, 1); # also set deprecated localhost ip
        test_display_ip($vm, $node, 2); # also set localhost ip

        test_set_vm_fail($vm, $node);
        test_volatile_req_clone($vm, $node);

        test_change_base($vm, $node);
        test_change_clone($vm, $node);

        test_fill_memory($vm, $node, 0); # balance
        test_fill_memory($vm, $node, 1); # migrate
        test_create_active($vm, $node);
        test_base_unset($vm,$node);

        test_removed_base_file_and_swap_remote($vm, $node);
        test_removed_remote_swap($vm, $node);
        test_removed_local_swap($vm, $node);
        test_duplicated_set_base_vm($vm, $node);

        test_set_vm($vm, $node);

        test_autostart($vm, $node);
        test_volatile($vm, $node);

        test_remove_req($vm, $node);

        for my $volatile (1,0) {
        test_remove_base($vm, $node, $volatile);
        }

        test_clone_remote($vm, $node);
        test_volatile_req($vm, $node);
        test_volatile_tmp_owner($vm, $node);

        test_reuse_vm($node);
        test_iptables($vm, $node);
        test_iptables($node, $vm);

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    end();
    done_testing();
}
