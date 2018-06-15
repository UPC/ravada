use warnings;
use strict;

use Data::Dumper;
use Test::More;

use Carp qw(confess);
use Cwd;
use IPC::Run3 qw(run3);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada') or BAIL_OUT;

my $RVD_BACK;

my %DOMAIN_INSTALLING;

our %CHECKED;
our %CLONE_N;
#####################################################################3

sub install_base {
    my $vm_name = shift;

    my $name = Test::Ravada::base_domain_name."_$vm_name";

    $DOMAIN_INSTALLING{$vm_name} = $name;

    my $vm = rvd_back->search_vm($vm_name);

    my $id_iso = search_id_iso('debian%64');
    ok($id_iso) or BAIL_OUT;

    my $old_domain = $vm->search_domain($name);

    if ( $old_domain ) {
        return $name if $vm->type eq 'Void';
    }

    my $internal_domain;
    eval { $internal_domain = $vm->vm->get_domain_by_name($name) };
    return $name if $old_domain && $internal_domain;

    if ($internal_domain) {
        rvd_back->import_domain(
            vm => $vm->type
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

    return $name if $vm_name eq 'Void';

    my $iso = $vm->_search_iso($id_iso);
    my @volumes = $domain->list_volumes();

    $domain->domain->undefine();

    my @cmd = qw(virt-install
        --noautoconsole
        --ram 256
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

    return $name;
}

sub _wait_base_installed($vm_name) {
    my $name = $DOMAIN_INSTALLING{$vm_name} or die "No $vm_name domain installing";

    diag("[$vm_name] waiting for $name");
    my $vm = rvd_back->search_vm($vm_name);
    return $name if $vm_name eq 'Void';

    my $domain = $vm->search_domain($name);
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

sub test_create_clones($vm_name, $domain_name, $n_clones=undef) {

    diag("[$vm_name] create clones from $domain_name");
    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);

    $domain->prepare_base(user_admin)   if !$domain->is_base;
    $domain->is_public(1);

    my $n_users = int($vm->free_memory / 1024 /1024) ;
    $n_users = 3 if $n_users<3;
    $n_users = $n_clones if defined $n_clones;
    diag("creating $n_users");

    my @domain_reqs = $domain->list_requests;
    _wait_requests([@domain_reqs], $vm) if scalar @domain_reqs;

    my @reqs;
    for my $n ( 1 .. $n_users ) {
        my $user_name = "user-".$domain->id."-".$n;
        my $user = Ravada::Auth::SQL->new(name => $user_name);
        $user = create_user($user_name,$n)   if !$user || !$user->id;

        my $clone_name = new_clone_name($domain_name);
        my $clone = $vm->search_domain($clone_name);
        push @reqs,(Ravada::Request->remove_domain(
                        uid => user_admin->id
                 ,name => $clone_name
                )
        )   if $clone;

        my $mem = 1024 * 128 if $n_users < 3 && $vm_name eq 'Void';
        my $req = Ravada::Request->clone(
            name => $clone_name
            ,uid => $user->id
            ,id_domain => $domain->id
            , memory => 1024 * 256
        );
        diag("create $clone_name");
        push @reqs,($req);
        push @reqs,(random_request($vm))  if rand(10)<2;
    }
    _wait_requests(\@reqs, $vm);
}

sub random_request($vm) {
    my @domains = $vm->list_domains();

    my $domain = $domains[rand($#domains)];
    return if $domain->name =~ /[a-z]$/i;

    return if $domain->is_base;

    return Ravada::Request->remove_domain(
        uid => user_admin->id
        ,name => $domain->name
    )   if rand(10)<2;

    my $ip = '192.168.1.'.int(rand(254)+1);
    if (!$domain->is_active) {
        return Ravada::Request->start_domain(
            remote_ip => $ip
            ,uid => user_admin->id
            ,id_domain => $domain->id
        );
    } elsif(rand(30)<10) {
        return Ravada::Request->hybernate(
            uid => user_admin->id
            ,id_domain => $domain->id
        )
    } elsif(rand(30)<10) {
        return Ravada::Request->shutdown_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
    } else {
        return Ravada::Request->open_iptables(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,remote_ip => $ip
        );

    }
}

sub new_clone_name {
    my $base_name = shift;

    my $clone_name;
    my $n = $CLONE_N{$base_name}++;
    for ( ;; ) {
        $n++;
        $n = "0$n" while length($n)<3;
        $clone_name = "$base_name-$n";

        return $clone_name if !rvd_front->domain_exists($clone_name);
    }
}

sub test_restart($vm_name) {

    my $vm = rvd_back->search_vm($vm_name);

    for my $count ( 1 .. 2 ) {
        my @reqs;
        diag("COUNT $count");

        my $t0 = time;
        my @domains;
        for my $domain ( $vm->list_domains ) {
            my $min_memory = ($vm->min_free_memory or $domain->get_info->{memory}*2);
            next if $domain->is_base;
            next if $domain->name !~ /^99/;
            next if $domain->list_requests;

            diag("request start domain ".$domain->name);
            push @reqs,( Ravada::Request->start_domain(
                        remote_ip => '127.0.0.1'
                        ,id_domain => $domain->id
                        ,uid => user_admin->id
                        )
            );
            push @domains,($domain);
            if ( $vm->free_memory <= $min_memory ) {
                _shutdown_random_domain($vm);
            }
        }
        _wait_requests(\@reqs, $vm);

        my $seconds = 60 - ( time - $t0 );
        $seconds = 1 if $seconds <=0 || $vm_name eq 'Void';
        diag("sleeping $seconds");
        sleep($seconds);

        for my $domain (@domains) {
            diag("request shutdown domain ".$domain->name);
            push @reqs,( Ravada::Request->shutdown_domain(
                        id_domain => $domain->id
                        ,uid => user_admin->id
                        )
            );
        }
        _wait_requests(\@reqs, $vm);

        for ( 1 .. 60 ) {
            my $alive = 0;
            my @reqs;
            for my $domain ( @domains ) {
                if ( $domain->is_active() && ! $domain->list_requests ) {
                    $alive++;
                    diag("request shutdown domain ".$domain->name);
                    push @reqs,(Ravada::Request->shutdown_domain(
                        id_domain => $domain->id
                            ,uid => user_admin->id
                        )
                    )if !$domain->list_requests;
                }
            }
            _wait_requests(\@reqs, $vm);
            last if !$alive;
            diag("$alive domains alive");
            sleep 1;
        }
    }
}

sub test_hibernate {
    my ($vm_name, $n) = @_;

    my $vm = rvd_back->search_vm($vm_name);

    my @reqs;
    my @domains;
    for my $domain ( $vm->list_domains ) {
        next if $domain->is_base;
        next if $domain->name !~ /^99/;
        next if $domain->list_requests();

        push @reqs,( Ravada::Request->start_domain(
                    remote_ip => '127.0.0.1'
                    ,id_domain => $domain->id
                    ,uid => user_admin->id
                    )
        );
        push @domains,($domain);
    }
    _wait_requests(\@reqs, $vm);

    for my $domain ( @domains ) {
        next if $domain->is_base || !$domain->is_active;
        diag("request hibernate ".$domain->name);
        push @reqs,( Ravada::Request->hybernate(
                    id_domain => $domain->id
                    ,uid => user_admin->id
                    )
        );
    }
    _wait_requests(\@reqs, $vm);
}

sub test_make_clones_base {
    my ($vm_name, $domain_name) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    ok($domain,"[$vm_name] Expecting to find domain $domain_name") or confess;

    diag("Making base to clones from ".$domain_name);
    for my $clone ($domain->clones) {
        diag("Prepare base to $clone->{name}");
        my @reqs;
        push @reqs,(Ravada::Request->prepare_base(
                    uid => user_admin->id
                    ,id_domain => $clone->{id}
                )
        );
        test_restart($vm_name);
        test_hibernate($vm_name);
        _wait_requests(\@reqs, $vm);
        test_create_clones($vm_name, $clone->{name});
    }
}

sub _wait_requests($reqs, $vm) {
    return if !$reqs || !scalar @$reqs;
    diag("Waiting for ".scalar(@$reqs)." requests");
    for ( ;; ) {
        last if _all_reqs_done($reqs, $vm);
        sleep 1;
    }
}

sub _all_reqs_done($reqs, $vm) {
    for my $r (@$reqs) {
        return 0 if $r->status ne 'done';
        next if $CHECKED{$r->id}++;
        next if !defined $r->error;
        ok(1) and next
            if ( $r->command eq 'remove' && $r->error =~ /already removed/)
            || ( $r->command eq 'start' && $r->error =~ /already running/)
            || ( $r->command eq 'hibernate' && $r->error =~ /not running/)
            || ( $r->command eq 'hybernate' && $r->error =~ /not running/)
            || ( $r->command eq 'clone' && $r->error =~ /already exists/)
            || ( $r->command eq 'prepare_base'
                    && $r->error =~ /already a base/);
        if ($r->error =~ /free memory/i) {
            _shutdown_random_domain($vm);
             next;
        }
        is($r->error,'',$r->id." ".$r->command." ".Dumper($r->args)) or exit;
    }
    return 1;
}

sub _shutdown_random_domain($vm) {
    my @domains = $vm->list_domains(active => 1);
    my $active = $domains[rand($#domains)];
    return if !$active;
    diag("request shutdown random domain ".$active->name);
    Ravada::Request->shutdown_domain(
                id_domain => $active->id
                ,uid => user_admin->id
    );

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

sub clean_clones($domain_name, $vm_name) {

    my $domain = rvd_back->search_domain($domain_name) or return;

    my $vm = rvd_back->search_vm($vm_name);

    my @reqs;
    for my $clone ($domain->clones) {
        clean_clones($clone->{name}, $vm_name);
        push @reqs,(Ravada::Request->remove_domain(
                name => $clone->{name}
                ,uid => user_admin->id
        ));
    }
    _wait_requests(\@reqs, $vm);
}

sub test_remove_base($domain_name, $vm_name) {

    my $domain = rvd_back->search_domain($domain_name) or return;
    my $vm = rvd_back->search_vm($vm_name);

    for my $clone ($domain->clones) {
        clean_clones($clone->{name}, $vm_name);
        my @reqs;
        diag("request remove base $clone->{name}");
        push @reqs,(Ravada::Request->remove_base(
                name => $clone->{name}
                ,uid => user_admin->id
        ));
        test_restart($vm_name);
        test_hibernate($vm_name);
        _wait_requests(\@reqs, $vm);
    }
}

sub clean_clone_requests {
    my $sth = rvd_back->connector->dbh->prepare(
        "DELETE FROM requests WHERE command='clone' "
        ." AND status='requested'"
    );
    $sth->execute();
    $sth->finish;
}

sub clean_leftovers($vm_name) {

    clean_clone_requests();

    my $vm = rvd_back->search_vm($vm_name);
    my @reqs;
    DOMAIN:
    for my $domain ( @{rvd_front->list_domains} ) {
        next if $domain->{name} !~ /^99_.*\d$/;

        for my $vm_installing (keys %DOMAIN_INSTALLING) {
            next DOMAIN if $DOMAIN_INSTALLING{$vm_installing} eq $domain->{name};
        }
        clean_clones($domain->{name}, $vm);
        diag("[$vm_name] cleaning leftover $domain->{name}");
        push @reqs, (
            Ravada::Request->remove_domain(
                name => $domain->{name}
                ,uid => user_admin->id
           )
       );
    }
}

#####################################################################3


my @vm_names;
for my $vm_name ( 'KVM' ) {

    SKIP: {
        if (!$ENV{TEST_STRESS} && !$ENV{"TEST_STRESS_$vm_name"}) {
            diag("Skipped $vm_name stress test. Set environment variable TEST_STRESS or"
                        ." TEST_STRESS_$vm_name to run");
            skip("Skipping stress $vm_name");
        }
        eval {
            $RVD_BACK= Ravada->new();
            init($RVD_BACK->connector,"/etc/ravada.conf");
            clean_clone_requests();
        };
        diag($@)    if $@;
        skip($@,10) if $@ || !$RVD_BACK;

        if ($vm_name eq 'KVM') {
            my $virt_install = `which virt-install`;
            chomp $virt_install;
            ok($virt_install,"Checking virt-install");
            skip("Missing virt-install",10) if ! -e $virt_install;
        }
        ok(_ping_backend(),"ERROR: backend stopped") or next;

        my $vm = $RVD_BACK->search_vm($vm_name);
        ok($vm, "Expecting VM $vm_name not found")  or next;

        clean_leftovers($vm_name);
        ok(install_base($vm_name),"[$vm_name] Expecting domain installing") or next;
        push @vm_names, ( $vm_name );
    }
}

for my $vm_name (reverse sort @vm_names) {
        diag("Testing $vm_name");
        my $domain_name = _wait_base_installed($vm_name);
        clean_clones($domain_name, $vm_name);
        test_create_clones($vm_name, $domain_name,20);
        test_restart($vm_name);

        my $vm = rvd_back->search_vm($vm_name);
        test_make_clones_base($vm_name, $domain_name);
        test_remove_base($vm_name, $domain_name);

        test_create_clones($vm_name, $domain_name, 20);
        test_restart($vm_name);
        test_hibernate($vm_name);
        clean_leftovers($vm_name);
}

done_testing();
