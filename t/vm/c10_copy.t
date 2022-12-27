use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(DumpFile);

use lib 't/lib';
use Test::Ravada;

init();

use_ok('Ravada');

##########################################################################3

sub add_volumes {
    my ($base, $volumes) = @_;
    $base->add_volume_swap(name => $base->name."-vol_swap", size => 512 * 1024);
    for my $n ( 1 .. $volumes ) {
        $base->add_volume(name => $base->name."-vol_$n", size => 512 * 1024);
    }
}

sub test_copy_clone {
    my $vm_name = shift;
    my $volumes = shift;

    my $base = create_domain($vm_name);

    add_volumes($base, $volumes)  if $volumes;

    my $name_clone = new_domain_name();

    my $clone = $base->clone(
        name => $name_clone
        ,user => user_admin
    );

    is($clone->is_base,0,$clone->name." is base");
    for my $vol ( $clone->list_volumes_info ) {
        next if $vol->info->{device} ne 'disk';
        confess Dumper($vol) if !$vol->file;

        open my $out ,'>>', $vol->file;
        print $out,"data : hola\n" ;
        close $out;
    }

    my $name_copy = new_domain_name();
    my $copy = $clone->clone(
        name => $name_copy
        ,user => user_admin
    );
    is($clone->is_base,0);
    is($copy->is_base,0);

    is($copy->id_base, $base->id);

    is(scalar($copy->list_volumes),scalar($clone->list_volumes));

    my @copy_volumes = $copy->list_volumes_info( device => 'disk');
    my %copy_volumes = map { $_->info->{target} => $_->file } @copy_volumes;
    my @clone_volumes = $clone->list_volumes_info( device => 'disk');
    my %clone_volumes = map { $_->info->{target} => $_->file } @clone_volumes;

    for my $target ( keys %copy_volumes ) {
        isnt($copy_volumes{$target}, $clone_volumes{$target}, Dumper(\@copy_volumes,\@clone_volumes)) or exit;
        my @stat_copy = stat($copy_volumes{$target});
        my @stat_clone = stat($clone_volumes{$target});
        is($stat_copy[7],$stat_clone[7],"[$vm_name] size different "
                ."\n$copy_volumes{$target} ".($stat_copy[7])
                ."\n$clone_volumes{$target} ".($stat_clone[7])
        ) or exit;

    }
    $clone->remove(user_admin);
    $copy->remove(user_admin);
    $base->remove(user_admin);
}

sub test_copy_request {
    my $vm_name = shift;

    my $base = create_domain($vm_name);
    my $memory = $base->get_info->{memory};

    my $name_clone = new_domain_name();
    my $mem_clone = int($memory * 1.5);

    my $clone = $base->clone(
        name => $name_clone
       ,user => user_admin
       ,memory => $mem_clone
    );

    is($clone->get_info->{memory}, $mem_clone,"[$vm_name] memory");

    my $name_copy = new_domain_name();
    my $mem_copy = ($mem_clone * 1.5);
    my $req;

    my $clone_mem = int ( $memory * 1.5);
    eval { $req = Ravada::Request->clone(
            id_domain => $clone->id
              ,memory => $mem_copy
               , name => $name_copy
                , uid => user_admin->id
        );
    };
    is($@,'') or return;
    is($req->status(),'requested');
    rvd_back->_process_all_requests_dont_fork();

    is($req->status(),'done');
    is($req->error,'');

    my $copy = rvd_back->search_domain($name_copy);
    ok($copy,"[$vm_name] Expecting domain $name_copy");
    is($copy->get_info->{memory}, $mem_copy);

    my $clone2 = rvd_back->search_domain($name_clone);
    is($clone2->is_base,0);

    is($clone2->get_info->{memory}, $mem_clone);

    isnt($clone2->get_info->{memory}, $base->get_info->{memory});
    isnt($clone2->get_info->{memory}, $copy->get_info->{memory});
}

sub test_copy_change_ram {
    my $vm_name = shift;

    my $base = create_domain($vm_name);

    my $name_clone = new_domain_name();

    my $clone = $base->clone(
        name => $name_clone
       ,user => user_admin
    );
    my $clone_mem = $clone->get_info->{memory};

    my $name_copy = new_domain_name();
    my $copy = $clone->clone(
        name => $name_copy
        ,memory => int($clone_mem * 1.5)
        ,user => user_admin
    );
    is($clone->is_base,0);
    is($copy->is_base,0);

    is ($copy->get_info->{memory},int($clone_mem * 1.5),"[$vm_name] Expecting memory");
    $clone->remove(user_admin);
    $copy->remove(user_admin);
    $base->remove(user_admin);
}

sub test_copy_req_nonbase {
    my $vm_name = shift;
    my $domain = create_domain($vm_name);

    my $name_copy = new_domain_name();

    my $req;
    eval { $req = Ravada::Request->clone(
            id_domain => $domain->id
               , name => $name_copy
                , uid => user_admin->id
        );
    };
    is($@,'') or return;
    is($req->status(),'requested');
    rvd_back->_process_all_requests_dont_fork();
    is($req->status(),'done');
    is($req->error,'');

    my $copy = rvd_back->search_domain($name_copy);
    ok($copy,"[$vm_name] Expecting domain $name_copy");

    $domain->_refresh_db();
    is($domain->is_base,1);

    my $id_copy = $copy->id;
    $copy->remove(user_admin);
    my $sth = connector->dbh->prepare("SELECT count(*) FROM volumes WHERE id_domain=?");
    $sth->execute($id_copy);
    my ($found) = $sth->fetchrow;
    is($found, 0, "Expected no volumes for domain $id_copy");

    $domain->remove(user_admin);

}

sub test_copy_req_many {
    my $vm_name = shift;
    my $domain = create_domain($vm_name);

    my $name_copy = new_domain_name();

    my $number = 3;
    my $req;
    eval { $req = Ravada::Request->clone(
            id_domain => $domain->id
              ,number => $number
                , uid => user_admin->id
        );
    };
    is($@,'') or return;
    is($req->status(),'requested');
    wait_request(check_error => 1);
    is($req->status(),'done');
    is($req->error,'');

    $domain->_refresh_db();
    is($domain->is_base,1);

    my @clones = $domain->clones();
    is(scalar @clones, $number);

    for (@clones) {
        my $clone = Ravada::Domain->open($_->{id} );
        $clone->remove(user_admin);
    }
    $domain->remove(user_admin);

}


##########################################################################3


for my $vm_name ( vm_names() ) {
    diag($vm_name);
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        init( { vm => [$vm_name] });

        test_copy_req_many($vm_name);

        test_copy_clone($vm_name);
        test_copy_clone($vm_name,1);
        test_copy_clone($vm_name,2);
        test_copy_clone($vm_name,10);

        test_copy_request($vm_name);

        test_copy_change_ram($vm_name);

        test_copy_req_nonbase($vm_name);
        clean();
    }

}

end();
done_testing();
