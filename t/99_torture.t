use warnings;
use strict;

use Data::Dumper;
use Test::More;

use Cwd;
use IPC::Run3 qw(run3);

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada') or BAIL_OUT;

my $RVD_BACK;

#####################################################################3

sub install_debian {
    my $vm_name = shift;

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $name = new_domain_name();

    my $id_iso = search_id_iso('debian%64');
    ok($id_iso) or BAIL_OUT;

    my $internal_domain;
    eval { $internal_domain = $vm->vm->get_domain_by_name($name) };

    my $old_domain = $vm->search_domain($name);
    return $name if $old_domain && $internal_domain;

    if ($internal_domain) {
        rvd_back->import_domain(
            vm => $vm_name
            ,name => $name
            ,user => user_admin->name
        );
        return $name;
    }
    my $domain = $vm->search_domain($name,1);
    $domain->remove(user_admin) if $domain;

    $domain = $vm->create_domain(
        name => $name
        ,id_iso => $id_iso
        ,id_owner => user_admin->id
    );
    my $iso = $vm->_search_iso($id_iso);
    my @volumes = $domain->list_volumes();

    $domain->domain->undefine();

    my @cmd = qw(virt-install
        --noautoconsole
        --ram 1024
        --vcpus 1
        --os-type linux
        --os-variant debian9
        --graphics spice
        --video qxl --channel spicevmc
    );
    my $preseed = getcwd."/t/preseed.cfg";
    ok(-e $preseed,"ERROR: Missing $preseed") or BAIL_OUT;

    push @cmd,('--extra-args', "'console=ttyS0,115200n8 serial'");
    push @cmd,('--initrd-inject',$preseed);
    push @cmd,('--name' => $name );
    push @cmd,('--disk' => $volumes[0]
                            .",bus=virtio"
                            .",cache=unsafe");# only for this test
    push @cmd,('--network' => 'bridge=virbr0,model=virtio');
    push @cmd,('--location' => $iso->{device});

    my ($in, $out, $err);
    warn Dumper(\@cmd);
    run3(\@cmd,\$in, \$out, \$err);
    diag($out);
    diag($err)  if $err;

    $domain = $vm->search_domain($name);
    diag("Waiting for shutdown from agent");
    for (;;) {
        last if !$domain->is_active;
        eval { 
            $domain->domain->shutdown(Sys::Virt::Domain::SHUTDOWN_GUEST_AGENT);
        };
        warn $@ if $@ && $@ !~ /^libvirt error code: 74,/;
        sleep 1;
    }
    return $name;
}

sub test_create_clones {
    my ($vm_name, $domain_name) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);

    $domain->prepare_base(user_admin)   if !$domain->is_base;
    $domain->is_public(1);

    for my $clone_data ( $domain->clones ) {
        my $clone = Ravada::Domain->open($clone_data->{id});
        $clone->remove(user_admin);
    }

    my $n_users = int($vm->free_memory / 1024 /1024) ;
    diag("creating $n_users");

    _wait_requests($domain->list_requests);

    my @reqs;
    for my $n ( 1 .. $n_users ) {
        my $user = Ravada::Auth::SQL->new(name => "user_$n");
        $user = create_user("user_$n",$n)   if !$user || !$user->id;

        my $clone_name = $domain->name."-user-$n";
        my $clone = $vm->search_domain($clone_name);
        push @reqs,(Ravada::Request->remove_domain(
                        uid => user_admin->id
                 ,name => $clone_name
                )
        );
        my $req = Ravada::Request->clone(
            name => $clone_name
            ,uid => $user->id
            ,id_domain => $domain->id
        );
        push @reqs,($req);
    }
    _wait_requests(\@reqs);
}

sub test_restart {
    my ($vm_name) = @_;

    my $vm = rvd_back->search_vm($vm_name);

    for my $count ( 1 .. 5 ) {
        my @reqs;
        diag("COUNT $count");

        my $t0 = time;
        my @domains;
        for my $domain ( $vm->list_domains ) {
            next if $domain->is_base;
            next if $domain->name !~ /^99/;

            push @reqs,( Ravada::Request->start_domain(
                        remote_ip => '127.0.0.1'
                        ,id_domain => $domain->id
                        ,uid => user_admin->id
                        )
            );
            push @domains,($domain);
        }
        _wait_requests(\@reqs);
        sleep 30 - ( time - $t0 );
        for my $domain (@domains) {
            push @reqs,( Ravada::Request->shutdown_domain(
                        id_domain => $domain->id
                        ,uid => user_admin->id
                        )
            );
        }
        _wait_requests(\@reqs);

        for ( ;; ) {
            my $alive = 0;
            for my $domain ( @domains ) {
                if ( $domain->is_active() ) {
                    $alive++;
                    Ravada::Request->shutdown_domain(
                        id_domain => $domain->id
                            ,uid => user_admin->id
                    ) if !$domain->list_requests;
                }
            }
            last if !$alive;
            diag("$alive domains alive");
            _process_requests();
        }
    }
}

sub test_hibernate {
    my ($vm_name, $n) = @_;

    my $vm = rvd_back->search_vm($vm_name);

    my @reqs;
    for ( 1 ..  10 ) {
        my @domains;
        for my $domain ( $vm->list_domains ) {
            next if $domain->is_base;
            next if $domain->name !~ /^99/;

            push @reqs,( Ravada::Request->start_domain(
                        remote_ip => '127.0.0.1'
                        ,id_domain => $domain->id
                        ,uid => user_admin->id
                        )
            );
            push @domains,($domain);
        }
        _wait_requests(\@reqs);

        for my $domain ( @domains ) {
            push @reqs,( Ravada::Request->hibernate_domain(
                        id_domain => $domain->id
                        ,uid => user_admin->id
                        )
            );
        }
        _wait_requests(\@reqs);

    }

}

sub test_make_clones_base {
    my ($vm_name, $domain_name) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);

    my @reqs;
    for my $clone ($domain->clones) {
        push @reqs,(Ravada::Request->prepare_base(
                    uid => user_admin->id
                    ,id_domain => $clone->{id}
                )
        );
    }
    _wait_requests(\@reqs);
}

sub _wait_requests {
    my $reqs = shift;
    for ( ;; ) {
        _process_requests();
        last if _all_reqs_done($reqs);
        sleep 1;
    }
}

sub _process_requests {
    #rvd_back->_process_all_requests_dont_fork(1);
#    rvd_back->process_requests(1);
#    rvd_back->process_long_requests(1);
#    rvd_back->enforce_limits();
}

sub _all_reqs_done {
    my $reqs = shift;
    for my $r (@$reqs) {
        diag($r->id." ".$r->command." ".$r->status." "
            .($r->error or '' ));
        return 0 if $r->status ne 'done';
    }
    return 1;
}

sub _ping_backend {
    my $req = Ravada::Request->ping_backend();
    for ( 1 .. 60 ) {
        if ($req->status ne 'done' ) {
            sleep 1;
            next;
        }
        return 1 if $req->error eq '';

        diag($req->error);
    }
    return 0;
}

#####################################################################3

for my $vm_name ( 'KVM' ) {
    SKIP: {
        eval {
            $RVD_BACK= Ravada->new();
            init($RVD_BACK->connector,"/etc/ravada.conf");
        };
        diag($@)    if $@;
        skip($@,10) if $@ || !$RVD_BACK;
    
        my $virt_install = `which virt-install`;
        chomp $virt_install;
        ok($virt_install,"Checking virt-install");
        skip("Missing virt-install",10) if ! -e $virt_install;

        skip("ERROR: backend stopped")  if !_ping_backend();
        
        my $domain_name = install_debian($vm_name);
        test_create_clones($vm_name, $domain_name);

        test_restart($vm_name);
        test_make_clones_base($vm_name, $domain_name);
    }
}
   
done_testing();
