use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);


########################################################################

sub _create_storage_pool($vm) {
    my $name = new_domain_name();
    my $dir = "/var/tmp/$name";
    mkdir $dir if ! -e $dir;

    my ($old) = grep {$_ eq $name } $vm->list_storage_pools();
    return($name, $dir) if $old;

    my $req = Ravada::Request->create_storage_pool(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => $name
        ,directory => $dir
    );
    wait_request();

    return ($name, $dir);
}

sub test_fail_nonvol($domain, $sp) {
    my $req = Ravada::Request->move_volume(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,volume => 'missing'
        ,storage => 'poolwrong'
    );
    wait_request( check_error => 0);
    like($req->error, qr/Volume .*not found in/);
}

sub test_move_volume($vm) {
    my $domain = create_domain_v2(vm => $vm, data => 1, swap => 1 );
    $domain->add_volume( name => new_domain_name().".raw"
        ,type => "raw"
    );
    my ($sp, $dir) = _create_storage_pool($vm);

    test_fail_nonvol($domain, $sp);

    my %done;
    my %md5;
    for my $vol ( $domain->list_volumes ) {
        my $md5sum = `md5sum $vol`;
        $md5sum =~ s/(.*?) .*/$1/;
        my ($filename)= $vol =~ m{.*/(.*)};

        if ( -e "$dir/$filename" ) {
            unlink("$dir/$filename") or die "$! $dir/$filename";
            $vm->refresh_storage();
        }

        $md5{$filename} = $md5sum;
        my $req = Ravada::Request->move_volume(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,volume => $vol
            ,storage => $sp
        );
        ok(!$done{$req->id}++);
        wait_request( debug => 0);
        is($req->status,'done');
        is($req->error, '');
        if ($vol =~ /iso$/) {
            ok( -e $vol) or die "Expecting $vol not removed";
        } else {
            ok(! -e $vol) or die "Expecting $vol removed";
        }
        ok(-e "$dir/$filename", "Expecting $dir/$filename") or exit;
    }
    for my $vol ($domain->list_volumes_info ) {
        is($vol->info->{storage_pool},$sp, $vol->file) or exit;
        like($vol->file, qr/^$dir/);
        my $file = $vol->file;
        my $md5sum = `md5sum $file`;
        $md5sum =~ s/(.*?) .*/$1/;
        my ($filename)= $file =~ m{.*/(.*)};
        is($md5sum,$md5{$filename}, $file) or exit;
        unlink $file or die "$! $file"
        if $file =~ /\.iso$/ && -e $file;
    }
    $domain->remove(user_admin);

    rmdir($dir) or die "$! $dir";
}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name eq 'KVM' && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("test $vm_name");
        test_move_volume($vm);
    }
}

end();

done_testing();

