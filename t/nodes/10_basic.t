use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);


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
    my $domain = create_domain($node->type);
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

    my $domain = create_domain($node->type);

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
        ,local_port => $local_port2
    );
    is(scalar @found,1,$vm->name." $remote_ip2:$local_port2".Dumper(\@found)) or exit;

    @found = search_iptable_remote(
       node => $node
        ,remote_ip => $remote_ip2
        ,local_port => $local_port2
    );
    is(scalar @found,1,$vm->name." $remote_ip2:$local_port2".Dumper(\@found)) or exit;

    $clone_local->shutdown_now(user_admin);

    @found = search_iptable_remote(
       node => $vm
        ,remote_ip => $remote_ip1
        ,local_port => $local_port1
    );
    is(scalar @found,0,$node->name." $remote_ip1:$local_port1".Dumper(\@found));

    @found = search_iptable_remote(
       node => $node
        ,remote_ip => $remote_ip2
        ,local_port => $local_port2
    );
    is(scalar @found,1,$vm->name." $remote_ip2:$local_port2".Dumper(\@found));

    _remove_domain($domain);
}

sub _remove_domain($domain) {
    for my $clone0 ( $domain->clones) {
        my $clone = Ravada::Domain->open($clone0->{id});
        $clone->remove(user_admin);
    }
    $domain->remove(user_admin);

}

sub _create_2_clones_same_port($vm, $node, $base, $ip_local, $ip_remote) {
    my $clone_local = $base->clone(name => new_domain_name, user => user_admin);
    #TODO: add a flag in start to force node to start in
    $clone_local->{_migrated} = 1;
    my $clone_remote= $base->clone(name => new_domain_name, user => user_admin);
    $clone_remote->migrate($node);

    $clone_local->start(user => user_admin, remote_ip => $ip_local);
    $clone_remote->start(user => user_admin, remote_ip => $ip_remote);

    for (1 .. 100 ) {
        my ($port_local) = $clone_local->display(user_admin) =~ m{://.*:(\d+)};
        my ($port_remote) = $clone_remote->display(user_admin) =~ m{://.*:(\d+)};

        return($clone_local, $clone_remote) if $port_local == $port_remote;

        my $clone3 = $base->clone(name => new_domain_name, user => user_admin);
        if ($port_local < $port_remote) {
            $clone3->migrate($vm) if $clone3->_vm->id != $vm->id;
            $clone_local = $clone3;
            $clone_local->start(user => user_admin, remote_ip => $ip_local);
        } else {
            $clone3->migrate($node) if $clone3->_vm->id != $node->id;
            $clone_remote = $clone3;
            $clone_remote->start(user => user_admin, remote_ip => $ip_remote);
        }
    }
}

sub test_removed_local_swap($vm, $node) {
    diag("Testing removed local swap in ".$vm->type);
    my $base = create_domain($vm);
    $base->add_volume(size => 128*1024 , type => 'tmp');
    $base->add_volume(size => 128*1024 , type => 'swap');
    $base->add_volume(size => 128*1024 , type => 'data');
    $base->prepare_base(user_admin);
    $base->set_base_vm(node => $node, user => user_admin);

    my $found_clone;
    for my $try ( 1 .. 20 ) {
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        _remove_tmp($clone1,$vm);
        $clone1->start(user_admin);
        $found_clone = $clone1;
        last if $clone1->_vm->id == $node->id;
    }
    is($found_clone->_vm->id, $node->id);
    for my $clone_data ($base->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }
    for my $req ( $base->list_requests ) {
        $req->stop;
    }
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
        diag("try $try");
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        $clone1->migrate($node);
        _remove_tmp($clone1,$node);
        $clone1->start(user_admin);
        $found_clone = $clone1;
        last if $base->list_requests;
    }
    ok(grep { $_->command eq 'set_base_vm' } $base->list_requests );
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

    for my $file ( $base->list_files_base ) {
        $node->remove_file($file);
    }

    my $found_req;
    my $found_clone;
    for my $try ( 1 .. 20 ) {
        diag("try $try");
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
    is($base->base_in_vm($node->id),0);
    is(scalar($base->list_vms),1) or exit;
    my $node2 = Ravada::VM->open($node->id);
    is($node2->is_enabled,1);
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
    diag("Testing removed remote base in ".$vm->type);
    my $base = create_domain($vm);
    $base->add_volume(size => 128*1024 , type => 'tmp');
    $base->add_volume(size => 128*1024 , type => 'swap');
    $base->add_volume(size => 128*1024 , type => 'data');
    $base->prepare_base(user_admin);
    $base->set_base_vm(node => $node, user => user_admin);

    my $found_req;
    my $found_clone;
    for my $try ( 1 .. 20 ) {
        diag("try $try");
        my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
        $clone1->migrate($node);
        _remove_tmp($clone1,$node);
        _remove_base_files($base,$node);
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
    is($base->base_in_vm($node->id),0);
    is(scalar($base->list_vms),1) or exit;
    my $node2 = Ravada::VM->open($node->id);
    is($node2->is_enabled,1);
    for my $clone_data ($base->clones) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }
    for my $req ( $base->list_requests ) {
        $req->stop;
    }
    $base->remove(user_admin);
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
    is($req->error, '');

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
        is($req->error, '');
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
        is($req->error, '');
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
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);
    $base->volatile_clones(1);
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

    for (@clones) {
        $_->remove(user_admin);
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
        my ($out, $err) = $node->run_command("ls $file");
        ok(!$out, "Expecting no file '$file' in ".$node->name) or exit;
        ok(-e $file, "Expecting file '$file' in local") or exit;
    }
    isnt($base->_data('id_vm'), $node->id);

    $base->set_base_vm(node => $node, user => user_admin);
    is(scalar($base->list_vms), 2) or exit;
    $base->remove_base(user_admin);

    my @req = $base->list_requests();
    is(scalar @req,2);
    ok(grep {$_->command eq 'remove_base_vm' } @req) or die Dumper(\@req);
    wait_request( debug => 1 );

    for my $file ( @volumes ) {
        ok(!-e $file, "Expecting no file '$file' in local") or exit;
        my ($out, $err) = $node->run_command("ls $file");
        ok(!$out, "Expecting no file '$file' in ".$node->name) or exit;
    }

    $base->remove(user_admin);

}

sub test_duplicated_set_base_vm($vm, $node) {
    my $req = Ravada::Request->set_base_vm(id_vm => $node->id
        , uid => 1
        , id_domain => 1
        , at => time + 3
    );
    my $req2 = Ravada::Request->set_base_vm(id_vm => $node->id
        , uid => 2
        , id_domain => 1
        , at => time + 4
    );
    ok(!$req2) or exit;
    my $req3 = Ravada::Request->remove_base_vm(id_vm => $node->id
        , uid => 1
        , id_domain => 1
        , at => time + 3
    );
    my $req4 = Ravada::Request->remove_base_vm(id_vm => $node->id
        , uid => 2
        , id_domain => 1
        , at => time + 4
    );
    ok(!$req4);
    my $req5 = Ravada::Request->set_base_vm(id_vm => 999
        , uid => 2
        , id_domain => 1
        , at => time + 4
    );
    ok($req5) or exit;

    is($node->is_locked,1);
    my $sth = connector->dbh->prepare("DELETE FROM requests");
    $sth->execute;
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
        wait_request(debug => 1);
        $clone = rvd_front->search_domain($name);
        ok($vm->search_domain($name),"Expecting clone $name in master node") or exit;
        last if $clone->display(user_admin) =~ /$remote_ip/;
    }
    like($clone->display(user_admin), qr($remote_ip));

    my $clone2 = rvd_front->search_domain($clone->name);
    my $info = $clone2->info(user_admin);
    like($info->{display}->{display}, qr($remote_ip)) or die Dumper($info->{display});

    _remove_domain($base);
}

##################################################################################
clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name ( 'Void', 'KVM') {
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
        my $node = remote_node($vm_name)  or next;
        clean_remote_node($node);

        ok($node->vm,"[$vm_name] expecting a VM inside the node") or do {
            remove_node($node);
            next;
        };
        is($node->is_local,0,"Expecting ".$node->name." ".$node->ip." is remote" ) or BAIL_OUT();

        test_create_active($vm, $node);

        test_removed_base_file_and_swap_remote($vm, $node);
        test_removed_remote_swap($vm, $node);
        test_removed_local_swap($vm, $node);
        test_duplicated_set_base_vm($vm, $node);
        test_removed_base_file($vm, $node);

        test_set_vm($vm, $node);

        test_volatile($vm, $node);

        test_remove_req($vm, $node);

        for my $volatile (1,0) {
        test_remove_base($vm, $node, $volatile);
        }

        test_clone_remote($vm, $node);
        test_volatile_req($vm, $node);
        test_volatile_tmp_owner($vm, $node);

        test_iptables_close($vm, $node);

        test_reuse_vm($node);
        test_iptables($vm, $node);
        test_iptables($node, $vm);

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    clean();
    done_testing();
}
