#!/usr/bin/perl
# test volatile anonymous domains kiosk mode

use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();
#############################################################################

sub test_frontend {
    my $vm = shift;
    my $swap = ( shift or 0);
    my $domain = create_domain($vm);

    my @volumes = $domain->list_volumes();
    is(scalar@volumes,2);

    $domain->info(user_admin);
    my $domain_f = rvd_front->search_domain($domain->name);
    my @volumes_f = $domain_f->list_volumes();

    is(scalar @volumes_f, scalar @volumes);

    my $info = $domain_f->info(user_admin);
    isa_ok($info->{hardware}->{disk}->[0],'HASH') or die Dumper($domain->name,$info->{hardware});
    isa_ok($info->{hardware}->{disk}->[0]->{info},'HASH') or die Dumper($domain->name,$info->{hardware});

    $domain->remove(user_admin);
}

sub test_frontend_refresh {
    my $vm = shift;
    my $domain = create_domain($vm);

    my $sth = connector->dbh->prepare("UPDATE domains SET info=? WHERE id=?");
    $sth->execute('',$domain->id);

    $sth = connector->dbh->prepare("DELETE FROM volumes WHERE id_domain=?");
    $sth->execute($domain->id);

    my $req = Ravada::Request->refresh_machine(id_domain => $domain->id, uid => user_admin->id);
    rvd_back->_process_requests_dont_fork();
    is($req->status, 'done');
    is($req->error, '');

    my $domain_f = rvd_front->search_domain($domain->name);
    my $info = $domain_f->info(user_admin);
    ok($info) or return;
    my $disk = $info->{hardware}->{disk};
    isa_ok($disk,'ARRAY') or return;
    isa_ok($disk->[0],'HASH', Dumper($disk));

    $domain->remove(user_admin);
}

sub test_add_disk {
    my $vm = shift;
    my $swap = ( shift or 0);
    my $domain = create_domain($vm);

    my @volumes = $domain->list_volumes();

    my $req = Ravada::Request->add_hardware(
        id_domain => $domain->id
        ,name => 'disk'
        ,uid => user_admin->id
        ,data => {
            size => 512 * 1024
            ,swap => $swap
        }
    );
    ok($req);
    rvd_back->_process_requests_dont_fork();

    is($req->status,'done');
    is($req->error,'');

    my @volumes2 = $domain->list_volumes();

    is(scalar @volumes2, scalar(@volumes)+1);

    my $domain_f = rvd_front->search_domain($domain->name);
    my @volumes_f = $domain_f->list_volumes();

    is(scalar @volumes_f, scalar @volumes2, $domain->name." [".$vm->type."]") or exit;
    $domain->info(user_admin);
    my $info = $domain_f->info(user_admin);
    is(scalar(@{$info->{hardware}->{disk}}),scalar(@volumes2),Dumper($info->{hardware}->{disk},$domain->name)) or exit;
    isa_ok($info->{hardware}->{disk}->[1]->{info},'HASH') or exit;
    $domain->remove(user_admin);
}

sub test_add_disk_boot_order {
    my $vm = shift;
    return if $vm->type ne 'KVM';
    my $domain = create_domain($vm);
    $domain->add_volume( boot => 1 , name => 'troy' );
    my @volumes = $domain->list_volumes_info();
    my ($troy) = grep { $_->{name} =~ m/^troy/ } @volumes;
    is($troy->{boot}, 1);

    $domain->add_volume( boot => 1 , name => 'abed');
    @volumes = $domain->list_volumes_info();
    my ($abed) = grep { $_->{name} =~ /^abed/ } @volumes;
    is($abed->{boot}, 1);
    ($troy) = grep { $_->{name} =~ m/^troy/ } @volumes;
    is($troy->{boot}, 2);


    $domain->add_volume( boot => 2 , name => 'jeff');
    @volumes = $domain->list_volumes_info();
    my ($jeff) = grep { $_->{name} =~ /^jeff/ } @volumes;

    ($abed) = grep { $_->{name} =~ m/^abed/ } @volumes;
    is($abed->{boot}, 1);

    ($troy) = grep { $_->{name} =~ m/^troy/ } @volumes;
    is($troy->{boot}, 3);

    $domain->change_hardware('disk',0,{ boot => 1 });
    @volumes = $domain->list_volumes_info();
    is($volumes[0]->{boot}, 1 );
}

#############################################################################

clean();


for my $vm_name ('Void', 'KVM') {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";

        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing volatile for $vm_name");

        test_add_disk_boot_order($vm);

        test_frontend($vm);
        test_frontend_refresh($vm);

        test_add_disk($vm);
        test_add_disk($vm , 1); # swap file

	}
}

clean();
done_testing();
