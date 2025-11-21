use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $DIR_TMP = "/var/tmp/$$";
mkdir $DIR_TMP if ! -e $DIR_TMP;

########################################################################

sub _create_storage_pool($vm, $dir=undef) {

    my $name;
    if (!defined $dir) {
        $name = new_pool_name();
        $dir = "$DIR_TMP/$name";
    } else {
        ($name) = $dir =~ m{.*/(.*)};
    }
    mkdir $dir if ! -e $dir;

    my ($old) = grep {$_ eq $name } $vm->list_storage_pools();

    if (!$old) {
        my $req = Ravada::Request->create_storage_pool(
            uid => user_admin->id
            ,id_vm => $vm->id
            ,name => $name
            ,directory => $dir
        );
        wait_request();
    }
    Ravada::Request->active_storage_pool(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => $name
        ,value => 1
    );
    wait_request();

    return ($name, $dir);
}

sub test_fail_nonvol($domain, $sp) {
    my $req = Ravada::Request->move_volume(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,volume => 'missing'
        ,storage => $sp
    );
    wait_request( check_error => 0);
    like($req->error, qr/Volume .*not found in/);
}

sub test_do_not_overwrite($vm) {
    my $domain = create_domain_v2(vm => $vm, data => 1, swap => 1 );
    my ($sp, $dir) = _create_storage_pool($vm);

    my ($vol) = ( $domain->list_volumes );

    my ($filename)= $vol =~ m{.*/(.*)};
    die "Unknown filename from volume $vol" if !$filename;

    open my $out,">","$dir/$filename" or die "$! $dir/$filename";
    print $out "\n";
    close $out;

    my $req = Ravada::Request->move_volume(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,volume => $vol
            ,storage => $sp
    );
    wait_request( debug => 0, check_error => 0);
    is($req->status,'done');
    like($req->error, qr/already exist/);

    unlink "$dir/$filename" or die "$! $dir/$filename";
    $vm->remove_storage_pool($sp);
    rmdir($dir) or die "$! $dir";
}

sub _search_free_space($dir) {
    diag($dir);
    open my $mounts,"<","/proc/mounts" or die $!;
    my $found;
    while (my $line = <$mounts>) {
        my ($type,$partition) = split /\s+/, $line;
        if ($partition eq $dir) {
            $found = $partition;
            last;
        }
    }
    close $mounts;
    if ( $found ) {
        my @cmd = ("stat","-f","-c",'%a',$found);
        my ($in, $out, $err);
        run3(\@cmd,\$in,\$out,\$err);
        die $err if $err;
        chomp $out;
        my $blocks = $out;
        @cmd=("stat","-f","-c",'%S',$found);
        run3(\@cmd,\$in,\$out,\$err);
        die $err if $err;
        chomp $out;
        my $size = $out;
        return $size * $blocks / (1024*1024*1024);

    }

    my ($dir2) = $dir =~ m{(/.*)/.*};
    return if !$dir2;

    return _find_mount($dir2);
}

sub test_fail($vm) {
    return if $< || $vm->type eq 'Void';

    my ($dir,$size, $dev) = create_ram_fs();

    $dir .= "/".new_pool_name();

    my ($sp) = _create_storage_pool($vm, $dir);

    my $domain = create_domain_v2(vm => $vm, data => 1, swap => 1 );

    my $vol = $domain->add_volume( name => new_domain_name()
        ,size => $size
        ,allocation => $size*1024
        ,format => 'raw'
    );

    my $req = Ravada::Request->move_volume(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,volume => $vol
            ,storage => $sp
    );

    wait_request( check_error => 0, debug => 0);
    like($req->error,qr/./,"Expecting $vol failed to copy to $sp")
    or exit;

    $domain->remove(user_admin);
    `umount $dir`;
    $vm->remove_storage_pool($sp);
    rmdir $dir  or die "$! $dir";
    unlink $dev or die "$! $dev";

}

sub test_queue_move($vm) {
    my $domain = create_domain_v2(vm => $vm, data => 1, swap => 1 );
    my $vol = $domain->add_volume( name => new_domain_name().".raw"
        ,type => "raw"
        ,capacity => 1024*10
    );
    my ($sp, $dir) = _create_storage_pool($vm);

    my @args = (
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => {
            max_mem => '1000'
        }
    );

    my $req1 = Ravada::Request->move_volume(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,volume => $vol
            ,storage => $sp
    );
    my $req2 = Ravada::Request->move_volume(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,volume => $vol
            ,storage => $sp
    );

    is($req2->after_request, $req1->id);

    remove_domain($domain);
    $vm->remove_storage_pool($sp);

}

sub test_queue_change_hw($vm) {
    my $domain = create_domain_v2(vm => $vm, data => 1, swap => 1 );
    my $vol = $domain->add_volume( name => new_domain_name().".raw"
        ,type => "raw"
        ,capacity => 1024*10
    );
    my ($sp, $dir) = _create_storage_pool($vm);

    my @args = (
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'memory'
        ,data => {
            max_mem => '1000'
        }
    );

    my $req0 = Ravada::Request->change_hardware(@args);
    my $req = Ravada::Request->move_volume(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,volume => $vol
            ,storage => $sp
    );
    is($req->after_request, $req0->id);

    my $req1 = Ravada::Request->change_hardware(@args);
    is($req1->after_request, $req->id);

    my $req2 = Ravada::Request->change_hardware(@args);
    is($req2->after_request,$req1->id);

    wait_request(debug => 0);

    $domain->remove(user_admin);

    $vm->remove_storage_pool($sp);
    rmdir($dir) or die "$! $dir";

}

sub test_move_volume($vm, $domain=undef) {
    $domain = create_domain_v2(vm => $vm, data => 1, swap => 1 )
    if !$domain;

    $domain->add_volume( name => new_domain_name().".raw"
        ,format => "raw"
        ,size => 1024*10
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
            diag("removing previously copied $dir/$filename");
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
    my $file_iso;
    for my $vol ($domain->list_volumes_info ) {

        is($vol->info->{storage_pool},$sp, $vol->file) or exit;
        like($vol->file, qr/^$dir/);
        my $file = $vol->file;
        my $md5sum = `md5sum $file`;
        $md5sum =~ s/(.*?) .*/$1/;
        my ($filename)= $file =~ m{.*/(.*)};
        is($md5sum,$md5{$filename}, $file) or exit;
        $file_iso = $file
        if $file =~ /\.iso$/ && -e $file;
    }
    my @volumes = $domain->list_volumes();
    $domain->remove(user_admin);
    unlink $file_iso if $file_iso;
    for my $vol (@volumes) {
        ok(!-e $vol);
    }

    $vm->remove_storage_pool($sp);
    rmdir($dir) or die "$! $dir";
}

sub test_move_volume_zztest($vm) {
    return if $vm->type ne 'KVM';
    my $base = import_domain($vm);
    my $clone = $base->clone(name => new_domain_name()
        ,user => user_admin
    );
    my $req = Ravada::Request->spinoff(
        uid => user_admin->id
        ,id_domain => $clone->id
    );
    wait_request();
    test_move_volume($vm, $clone);
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
        test_move_volume_zztest($vm);
        test_queue_move($vm);
        test_queue_change_hw($vm);
        test_fail($vm);
        test_move_volume($vm);
        test_do_not_overwrite($vm);
    }
}

end();

done_testing();

