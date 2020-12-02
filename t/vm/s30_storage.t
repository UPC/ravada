use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Copy;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;


###########################################################

sub test_storage_pools($vm) {
    my $req = Ravada::Request->check_storage(
        uid => user_admin->id
    );
    my $req_cleanup = Ravada::Request->cleanup(
        after_request_ok => $req->id
    );
    wait_request( debug => 1);
    is($req->status,'done');
    is($req->error, '');

    is($req_cleanup->status,'done');
    is($req_cleanup->error, '');
}

sub _add_fstab($vm) {
    my $dir = "/mnt/".base_domain_name();
    if (!-e $dir) {
        mkdir $dir;
    }
    my %fstab = Ravada::_list_mnt($vm,"s");
    return $dir if $fstab{$dir};

    copy("/etc/fstab","/etc/fstab.tst_rvd_backup") or die $!;

    open my $fstab,">>","/etc/fstab" or die $!;
    print $fstab "bogus.ravada:$dir $dir nfs rw,_netdev 0 0\n";
    close $fstab;

    return $dir;
}

sub remove_fstab($vm, $dir) {
    my $file = "$dir/check_storage";# or die "$!";
    unlink $file or die "$! $file" if -e $file;
    copy("/etc/fstab.tst_rvd_backup","/etc/fstab")
}

sub test_storage_pools_fail($vm) {
    return if $vm->type ne 'KVM';
    my $dir = _add_fstab($vm);

    create_storage_pool($vm, $dir);

    my $req = Ravada::Request->check_storage(
        uid => user_admin->id
        ,retry => 2
    );
    my $req_cleanup = Ravada::Request->cleanup(
        after_request_ok => $req->id
    );
    is($req_cleanup->after_request_ok,$req->id);
    wait_request( debug => 1, check_error => 0);
    is($req->status,'done');
    like($req->error, qr/not mounted/);

    is($req_cleanup->status,'done');
    like($req_cleanup->error, qr/not mounted/);

    remove_fstab($vm, $dir);
    $vm->refresh_storage_pools();
}

sub _clean_local {
    my $dir = "/mnt/".base_domain_name();
    my $file = "$dir/check_storage";# or die "$!";
    unlink $file or die "$! $file" if -e $file;
}
###########################################################

_clean_local();
clean();

for my $vm_name (vm_names() ) {
    ok($vm_name);
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        test_storage_pools($vm);
        test_storage_pools_fail($vm);
    }
}

end();
done_testing();
