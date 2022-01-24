#!/usr/bin/perl
# test volatile anonymous domains kiosk mode

use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

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
    isa_ok($info->{hardware}->{disk}->[1],'HASH') or exit;
    $domain->remove(user_admin);
}

sub test_add_disk_boot_order($vm, $iso_name, $options=undef) {
    return if $vm->type ne 'KVM';

    my $domain = create_domain_v2(vm => $vm, iso_name => $iso_name
    , options => $options);
    $domain->add_volume( boot => 1 , name => $domain->name.'-troy' );
    my @volumes = $domain->list_volumes_info();
    my ($troy) = grep { $_->name =~ m/-troy\.\w+$/ } @volumes;
    ok($troy,"Expecting volume called -troy\$") or die Dumper(\@volumes);

    is($troy->info->{boot}, 1);

    $domain->add_volume( boot => 1 , name => $domain->name.'-abed');
    @volumes = $domain->list_volumes_info();
    my ($abed) = grep { $_->name =~ /-abed/ } @volumes;
    is($abed->info->{boot}, 1);
    ($troy) = grep { $_->name =~ m/-troy/ } @volumes;
    is($troy->info->{boot}, 2);


    $domain->add_volume( boot => 2 , name => $domain->name.'-jeff');
    @volumes = $domain->list_volumes_info();
    my ($jeff) = grep { $_->name =~ /-jeff/ } @volumes;

    ($abed) = grep { $_->name =~ m/-abed/ } @volumes;
    is($abed->info->{boot}, 1);

    ($troy) = grep { $_->name =~ m/-troy/ } @volumes;
    is($troy->info->{boot}, 3);

    $domain->change_hardware('disk',0,{ boot => 1 });
    @volumes = $domain->list_volumes_info();
    is($volumes[0]->info->{boot}, 1 );
}

sub combine_iso_options($vm, $iso_name) {

    return (undef) if $vm->type ne 'KVM';

    $Ravada::VM::KVM::VERIFY_ISO = 0;
    my $iso = $vm->_search_iso(search_id_iso($iso_name));
    my @options = (
        { machine => 'pc' }
        ,{ machine => search_latest_machine($vm, $iso->{arch},'pc-i440fx')}
    );
    my $machine = $iso->{options}->{machine};
    if ($machine) {
        my $found = 0;
        for my $option (@options) {
            $found++ if $option->{machine} eq $machine;
        }
        push @options,(
            {machine =>search_latest_machine($vm, $iso->{arch},$machine)})
        if !$found;
    }
    if ($iso->{options}->{bios} && $iso->{options}->{bios} eq 'UEFI') {
        my @options2;
        for my $option (@options) {
            my %option2 = %$option;
            $option2{uefi} = 1;
            push @options2, \%option2;
        }
        push @options,@options2;
    }
    return @options;
}

#############################################################################

clean();


for my $vm_name ( vm_names() ) {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";

        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing disk for $vm_name");

        for my $iso_name ('Alpine%64 bits', 'Alpine%32 bits') {
            for my $options ( combine_iso_options($vm, $iso_name)) {
                warn $iso_name.Dumper($options);
                test_add_disk_boot_order($vm, $iso_name, $options);
            }
        }

        test_frontend($vm);
        test_frontend_refresh($vm);

        test_add_disk($vm);
        test_add_disk($vm , 1); # swap file

	}
}

end();
done_testing();
