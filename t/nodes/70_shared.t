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

my $SHARED_SP = "pool_shared";
my $DIR_SHARED = "/home2/pool_shared";

init();

my $BASE_NAME = "zz-test-base-alpine";
my $BASE;

#################################################################################

sub test_shared($vm, $node) {
    my $domain = create_domain($vm);

    my $storage_path = $vm->_storage_path($SHARED_SP);
    for my $vol ($domain->list_disks) {
        like($vol,qr(^$storage_path), $vol);
    }

    my $req = Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node->id
    );
    rvd_back->_process_requests_dont_fork(1);

    ok($req->status, 'done');
    is($req->error, '') or exit;
    is($domain->base_in_vm($node->id),1);
    is($domain->base_in_vm($vm->id),1);

    my @files_base = $domain->list_files_base();
    for my $vol (@files_base) {
        my $ok;
        for ( 1 .. 5 ) {
            $ok = -e $vol;
            last if $ok;
            sleep 1;
        }
        ok($ok,"Volume $vol should exist") or exit;
        ok($node->file_exists($vol), "Volume $vol should exist in ".$node->name);
    }


    $req = Ravada::Request->set_base_vm(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,id_vm => $node->id
        ,value => 0
    );
    rvd_back->_process_requests_dont_fork(1);

    ok($req->status, 'done');
    is($req->error, '') or exit;

    is($domain->base_in_vm($node->id),0);
    is($domain->base_in_vm($vm->id),1);

    for my $vol (@files_base) {
        my $ok;
        for ( 1 .. 5 ) {
            $ok = -e $vol;
            last if $ok;
            sleep 1;
        }
        ok($ok,"Volume $vol should exist") or exit;
        ok($node->file_exists($vol), "Volume $vol should exist in ".$node->name);
    }
    $domain->remove(user_admin);

}

sub test_is_shared($vm, $node) {
    is($vm->shared_storage($node,$DIR_SHARED),1) or exit;
    is($node->shared_storage($vm,$DIR_SHARED),1) or exit;
    my $sth = connector->dbh->prepare("SELECT * FROM storage_nodes "
        ." WHERE dir=?"
    );
    my $dir_shared = $DIR_SHARED;
    $dir_shared.="/" unless $dir_shared =~ m{/$};
    $sth->execute($dir_shared);
    my $row = $sth->fetchrow_hashref;
    is($row->{is_shared},1) or die Dumper($row);
}

sub _add_disk($domain) {
    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name=> 'disk'
        ,data => { size => 512 * 1024 }
    );
    wait_request(debug => 0);
    is($req->error,'');
    is($req->status, 'done');
}

sub _change_ram($domain) {

    my $mem = $domain->info(user_admin)->{memory};
    my $new_mem = int($mem * 0.8 ) - 1;

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => {memory => $new_mem }
    );
    wait_request(debug => 0);
    is($req->error,'');
    return $new_mem;
}

sub test_change_ram($vm, $node, $start=0, $prepare_base=0, $migrate=0) {
    diag("start=$start , prepare_base=$prepare_base , migrate=$migrate");
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->spinoff();

    my $domain = $base;
    if ($prepare_base) {
        $base->prepare_base(user_admin);
        $base->set_base_vm(vm => $node, user => user_admin);
        $domain = $base->clone(name => new_domain_name, user => user_admin);
    }
    req_migrate($node, $domain, $start) if $migrate;

    my $new_mem = _change_ram($domain);
    if ( $migrate ) {
        my $domain2 = Ravada::Domain->open($domain->id);
        is($domain2->_vm->id, $node->id);
    }
    _test_volumes_exist($domain);

    my $domain_local = $vm->search_domain($domain->name);
    is($domain_local->_vm->id,$vm->id);
    my $mem2 = $domain_local->info(user_admin)->{memory};
    is($mem2, $new_mem);

    req_start($domain);
    req_migrate($node, $domain, 1);
    $domain = Ravada::Domain->open($domain->id);
    $mem2 = $domain->info(user_admin)->{memory};
    is($mem2, $new_mem);
    _test_volumes_exist($domain);

    $domain->remove(user_admin);
    $base->remove(user_admin) if $base->id != $domain->id;
}

sub _test_volumes_exist($domain) {
    my $domain_local = Ravada::Domain->open($domain->id);
    for my $disk ( $domain_local->list_volumes ) {
        ok(-e $disk,"Expecting ".$domain_local->name." $disk exist in "
            .$domain_local->_vm->name) or confess;
    }
    if ($domain->id_base) {
        my $base = Ravada::Domain->open($domain->id_base);
        for my $disk ($base->list_files_base) {
            ok(-e $disk,"Expecting $disk exist");
        }
    }
}

sub test_add_disk($vm, $node, $start=0, $prepare_base=0, $migrate=0) {
    my $base = $BASE->clone(name => new_domain_name, user => user_admin);
    $base->spinoff();

    my $domain = $base;
    if ($prepare_base) {
        $base->prepare_base(user_admin);
        $base->set_base_vm(vm => $node, user => user_admin);
        $domain = $base->clone(name => new_domain_name, user => user_admin);
    }
    my $n = scalar($domain->list_volumes);
    my @volumes0 = map { $_->{file} } $domain->list_volumes_info;
    req_migrate($node, $domain, $start) if $migrate;

    _add_disk($domain);
    if ( $migrate ) {
        my $domain2 = Ravada::Domain->open($domain->id);
        is($domain2->_vm->id, $node->id);
    }
    _test_volumes_exist($domain);

    my $domain_local = $vm->search_domain($domain->name);
    is($domain_local->_vm->id,$vm->id);
    my @volumes1 = map { $_->{file} } $domain->list_volumes_info;
    is(scalar($domain_local->list_volumes),$n+1,Dumper(\@volumes0,\@volumes1)) or exit;

    req_start($domain);
    req_migrate($node, $domain, 1);
    $domain = Ravada::Domain->open($domain->id);
    is(scalar($domain->list_volumes),$n+1);
    _test_volumes_exist($domain);

    $domain->remove(user_admin);
    #    $base->remove(user_admin) if $base->id != $domain->id;
}

sub req_start($domain) {
    my $req = Ravada::Request->start_domain(
        id_domain => $domain->id
        ,uid => user_admin->id
    );
    wait_request();
    is($req->status,'done');
    is($req->error,'');
}

sub req_migrate($node, $domain, $start=0) {
    my $req = Ravada::Request->migrate(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,shutdown => 1
        ,shutdown_timeout => 30
        ,start => 1
        ,id_node => $node->id
    );
    wait_request();
    is($req->status,'done');
    is($req->error,'');

    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->_vm->id,$node->id);
}

sub import_base($vm) {
    if ($vm->type eq 'KVM') {
        $BASE = import_domain($vm->type, $BASE_NAME, 1);
        confess "Error: domain $BASE_NAME is not base" unless $BASE->is_base;
    } else {
        $BASE = create_domain($vm);
    }
}

#################################################################################
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP:{
        skip($msg,10);
    }
    done_testing();
    exit;
}

clean();

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

for my $vm_name ( vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        my $REMOTE_CONFIG = remote_config($vm_name);
        if (!keys %$REMOTE_CONFIG) {
            my $msg = "skipped, missing the remote configuration for $vm_name in 
the file "
                .$Test::Ravada::FILE_CONFIG_REMOTE;
            diag($msg);
            skip($msg,10);
        }

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        if ($vm && !grep /^$SHARED_SP$/,$vm->list_storage_pools) {
            $msg = "SKIPPED: Missing storage pool '$SHARED_SP' in node ".$vm->name;
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        my $node = remote_node_shared($vm_name)  or next;
        clean_remote_node($node);

        ok($node->vm,"[$vm_name] expecting a VM inside the node") or do {
            remove_node($node);
            next;
        };
        is($node->is_local,0,"Expecting ".$node->name." ".$node->ip." is remote") or BAIL_OUT();

        if (!grep /^$SHARED_SP$/,$node->list_storage_pools) {
            $msg = "SKIPPED: Missing storage pool '$SHARED_SP' in node ".$node->name;
            diag($msg);
            skip($msg,10);
        }

        # set storage in shared dir
        $vm->default_storage_pool_name($SHARED_SP);
        my $storage_path = $vm->_storage_path($SHARED_SP);
        is($vm->shared_storage($node, $storage_path),1,"Expecting $SHARED_SP shared") or exit;

        import_base($vm);

        test_is_shared($vm, $node);
        test_shared($vm, $node);

        for my $default_sp ( 0,1 ) {
            $node->default_storage_pool_name('default')     if !$default_sp;
            $node->default_storage_pool_name($SHARED_SP)    if $default_sp;
            for my $start ( 0,1 ) {
                for my $prepare_base ( 0,1 ) {
                    for my $migrate( 1, 0 ) {
                        test_change_ram($vm,$node, $start, $prepare_base, $migrate);
                        test_add_disk($vm,$node, $start, $prepare_base, $migrate);
                    }
                }
            }
        }

        NEXT:
        clean_remote_node($node);
        remove_node($node);
    }

}

END: {
    end();
    done_testing();
}

