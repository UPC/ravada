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
    $domain->add_volume(name => 'vdb', swap => 1, size => 512 * 1024);
    $domain->prepare_base(user_admin);
    $domain->set_base_vm(vm => $node, user => user_admin);

    my $clone1 = $domain->clone(name => new_domain_name, user => user_admin);

    my $clone2 = $domain->clone(name => new_domain_name, user => user_admin);
    is($clone1->_vm, $clone2->_vm, $clone1->_vm->name);
    is($clone1->_vm->id, $clone2->_vm->id);

    $clone1->migrate($node);
    is($clone1->_data('id_vm'), $node->id);
    $clone2->migrate($node);
    is($clone2->_data('id_vm'), $node->id);

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

sub test_remove($clone, $node) {

    diag("Testing remove is_local = ".$clone->is_local);

    my @volumes = $clone->list_volumes();
    ok(scalar @volumes,"Expecting volumes in ".$clone->name);

    for my $file ( @volumes ) {
        ok( -e $file, "Expecting file '$file' in localhost");
        my ($out, $err) = $node->run_command("ls $file");
        ok($out, "Expecting file '$file' in ".$node->name) or exit;
    }

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

    for (1 .. 10 ) {
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
    die;
}

sub test_volatile($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);
    $base->volatile_clones(1);

    my @clones;
    for ( 1 .. 4 ) {
        my $clone = $base->clone(user => user_admin, name => new_domain_name);
        $clone->start(user_admin) if !$clone->is_active;
        push @clones,($clone);
        last if $clone->_vm->id == $node->id;
    }
    is($clones[-1]->_vm->id, $node->id);

    for (@clones) {
        $_->remove(user_admin);
    }
    $base->remove(user_admin);
}

sub test_volatile_req($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);
    $base->volatile_clones(1);
    ok($base->base_in_vm($node->id));

    my @clones;
    for ( 1 .. 4 ) {
        my $clone_name = new_domain_name;
        my $req = Ravada::Request->create_domain(
           id_base => $base->id
             ,name => $clone_name
            ,id_owner => user_admin->id
        );
        rvd_back->_process_all_requests_dont_fork();
        is($req->status, 'done');
        is($req->error,'');

        my $clone = rvd_back->search_domain($clone_name);
        $clone->start(user_admin) if !$clone->is_active;
        push @clones,($clone);
        last if $clone->_vm->id == $node->id;
    }
    is($clones[-1]->_vm->id, $node->id) or exit;

    for (@clones) {
        $_->remove(user_admin);
    }
    $base->remove(user_admin);
}

sub test_volatile_tmp_owner($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(user => user_admin, node => $node);

    my $user = Ravada::Auth::SQL::add_user(name => 'mcnulty', is_temporary => 1);

    my @clones;
    for ( 1 .. 4 ) {
        my $clone_name = new_domain_name;
        my $req = Ravada::Request->create_domain(
           id_base => $base->id
             ,name => $clone_name
            ,id_owner => user_admin->id
        );
        rvd_back->_process_all_requests_dont_fork();
        is($req->status, 'done');
        is($req->error,'');

        my $clone = rvd_back->search_domain($clone_name);
        $clone->start(user_admin) if !$clone->is_active;
        push @clones,($clone);
        last if $clone->_vm->id == $node->id;
    }
    is($clones[-1]->_vm->id, $node->id);

    for (@clones) {
        $_->shutdown_now(user_admin);
        $_->remove(user_admin);
    }
    $base->remove(user_admin);
    $user->remove();
}

sub test_clone_remote($vm, $node) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);

    my $bases_vm = $base->_bases_vm();
    is($bases_vm->{$vm->id},1) or exit;
    $base->set_base_vm(user => user_admin, node => $node);

    $bases_vm = $base->_bases_vm();
    is($bases_vm->{$node->id},1) or exit;

    $base->migrate($node);

    my $clone = $base->clone(
        name => new_domain_name
        ,user => user_admin
    );
    ok($clone->_vm->name, $node->name);

    _test_old_base($base, $vm);
    _test_clones($base, $vm);
    $clone->remove(user_admin);
    $base->remove(user_admin);
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
    ok($info->{clones}->{$vm->id}) or return;
    is(scalar @{$info->{clones}->{$vm->id}},1 );
}

sub test_remove_base($vm, $node) {
    my $base = create_domain($vm);
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
    for my $file ( @volumes ) {
        my ($out, $err) = $node->run_command("ls $file");
        ok(!$out, "Expecting no file '$file' in ".$node->name) or exit;
    }
    isnt($base->_data('id_vm'), $node->id);

    for my $file ( @volumes0 ) {
        my ($out, $err) = $node->run_command("ls $file");
        ok($out, "Expecting file '$file' in ".$node->name) or exit;
    }
    $base->set_base_vm(node => $node, user => user_admin);
    $base->remove_base(user_admin);

    for my $file ( @volumes ) {
        ok(!-e $file, "Expecting no file '$file' in local") or exit;
        my ($out, $err) = $node->run_command("ls $file");
        ok(!$out, "Expecting no file '$file' in ".$node->name) or exit;
    }

    $base->remove(user_admin);

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

        test_remove_base($vm, $node);
        test_clone_remote($vm, $node);
        test_volatile_req($vm, $node);
        test_volatile_tmp_owner($vm, $node);
        test_volatile($vm, $node);

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
