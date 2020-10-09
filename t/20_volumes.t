use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Copy;
use File::Path qw(make_path);
use IPC::Run3 qw(run3);
use Test::More;
use YAML qw(Dump Load);

use lib 't/lib';
use Test::Ravada;


no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada::Volume');

my %TEST_BASE = (
       iso => \&_test_base_iso
      ,img => \&_test_base_qcow2
      ,raw => \&_test_base_raw
     ,void => \&_test_base_void
    ,qcow2 => \&_test_base_qcow2
);
my %TEST_CLONE = (
       iso => \&_test_clone_iso
      ,img => \&_test_clone_qcow2
     ,void => \&_test_clone_void
    ,qcow2 => \&_test_clone_qcow2
);

#########################################################

sub _test_base_iso($volume, $base) {
    is($base, $volume->file );
}

sub _test_clone_iso($base, $clone) {
    is($base->file, $clone);
}

sub _test_base_void($volume, $base) {
    my $info = Load($volume->vm->read_file($base));
    is($info->{is_base},1);
}

sub _test_clone_void($vol_base, $clone) {
    my $info = Load($vol_base->vm->read_file($clone));
    is($info->{is_base},undef);
    is($info->{backing_file},$vol_base->file);
}

sub _test_identical($vm, $file, $base) {
    my ($size_f,$errf) = $vm->run_command("/usr/bin/test","-s",$file);
    is($errf,'');

    my ($size_b,$errb) = $vm->run_command("/usr/bin/test","-s",$base);
    is($errb,'');

    is($size_f, $size_b) or return;

    my ($sum_f,$err_fs) = $vm->run_command("/usr/bin/md5sum",$file);
    is($errf,'');
    $sum_f =~ s/\s+.*//;
    chomp $sum_f;

    my ($sum_b,$err_bs) = $vm->run_command("/usr/bin/md5sum",$base);
    is($errb,'');
    $sum_b =~ s/\s+.*//;
    chomp $sum_b;

    is($sum_f, $sum_b,Dumper([$file,$base])) or confess;

}

sub _test_base_qcow2($volume, $base) {

    my @cmd = ("/usr/bin/qemu-img","info",$base);
    my ($out, $err) = $volume->vm->run_command(@cmd);
    is($err,'');

    my ($ext) = $volume->file =~ m{.*(\.\w+)$};
    $ext = '.qcow2' if $ext =~ m{\.(img|raw)};
    my ($type) = $volume->file =~ m{(\.[A-Z]+)\.\w+$};
    $type = '' if !$type;

    $ext = "$type$ext";

    like($out,qr/^image:.*\.ro$ext$/m);

    @cmd = ("/usr/bin/qemu-img","info",$volume->file);
    ($out, $err) = $volume->vm->run_command(@cmd);
    is($err,'');
    like($out,qr/backing file:.*\.ro$ext$/m);
}

sub _test_base_raw($volume, $base) {

    my @cmd = ("/usr/bin/qemu-img","info",$base);
    my ($out, $err) = $volume->vm->run_command(@cmd);
    is($err,'');

    my ($ext) = $volume->file =~ m{.*\.(\w+)$};
    like($out,qr/^image:.*\.ro\.$ext$/m);

    @cmd = ("/usr/bin/qemu-img","info",$volume->file);
    ($out, $err) = $volume->vm->run_command(@cmd);
    is($err,'');
    like($out,qr/file format: raw$/m);
}


sub _test_clone_qcow2($vol_base, $clone) {
    my ($ext) = $vol_base->file =~ m{.*(\.\w+)$};
    my ($type) = $vol_base->file =~ m{(\.[A-Z]+)\.\w+$};
    $type = '' if !$type;
    $ext = "$type$ext";

    my @cmd = ("/usr/bin/qemu-img","info",$clone);
    my ($out, $err) = $vol_base->vm->run_command(@cmd);
    is($err,'');
    like($out,qr/backing file:.*\.ro$ext$/m) or exit;
}


sub test_base($volume) {
    my ($ext) = $volume->file =~ m{.*\.(.*)};
    $ext = 'qcow2' if $ext =~ m{^(img|raw)};

    my $test = $TEST_BASE{$ext} or confess "Error: no test for $ext";

    my $base = $volume->prepare_base();

    if ($ext ne 'iso') {
        if ( $volume->file =~ /\.SWAP\./) {
            like($base,qr{(vd.|\d)\.ro\.SWAP\.$ext$}, $volume->file) or exit
        } elsif ( $volume->file =~ /\.DATA\./) {
            like($base,qr{(vd.|\d)\.ro\.DATA\.$ext$}, $volume->file) or exit
        } else {
            like($base,qr{(vd.|\d+)\.ro\.$ext$}, $volume->file) or exit;
        }
    }
    $test->($volume, $base);

    return $base;
}

sub test_clone($vm, $base) {
    my ($ext) = $base =~ m{.*\.(.*)};
    my $test = $TEST_CLONE{$ext} or confess "Error: no test for $ext";

    my $vol_base = Ravada::Volume->new(
        file => $base
        ,vm => $vm
        ,is_base => 1
    );
    is($vol_base->is_base, 1);

    my $clone0 = $vol_base->clone();
    my ($base_name) = $base =~ m{.*/(.*?)\..*};

    like($clone0->file,qr(^.*/$base_name)) or exit;

    my $name = new_domain_name();
    my $clone = $vol_base->clone(name => $name);
    like(ref($clone),qr/^Ravada::Vol/, $vm->type) or exit;

    unlike($clone->file,qr(\.ro\.\w+$)) or exit;
    like($clone->file,qr($ext$));
    like($clone->file,qr(\.SWAP\.$ext$)) if $base =~ /\.SWAP\./;

    #ISOs should be identical and we test no more
    if ($ext eq 'iso') {
        is($clone->file, $base);
        is($clone->name, $vol_base->name);
        return;
    }

    like($clone->file,qr(^.*/$name));
    isnt($clone->name, $vol_base->name);

    $test->($vol_base, $clone->file);

    copy($clone->file,$clone->file.".tmp");

    my $size = -s $clone->file;

    for ('a' .. 'z') {
        open my $out,">>",$clone->file or die $!;
        print $out "$_: ".("a"x 1024)."\n";
        close $out;
        my $size_change = -s $clone->file;
        last if int($size_change/1024) > int($size/1024);
    }

    my $size_change = -s $clone->file;
    isnt($size_change,$size);
    $clone->restore();

    _test_identical($clone->vm, $clone->file, $clone->file.".tmp");
    unlink($clone->file.".tmp");

    return $clone
}

sub _do_test_file($type, $vm, $file) {
    my $volume = Ravada::Volume->new(file => $file, vm => $vm, info => {name => $file});

    is(ref $volume,"Ravada::Volume::$type");
    is(ref $volume->info,'HASH') or exit;

    is($volume->info->{name}, $file);

    my $base_file = test_base($volume);
    test_clone($vm, $base_file);

    unlink $file if $type ne 'ISO';

    if ($type eq 'ISO') {
        is($base_file, $volume->file);
        ok(-e $file, "ISO file $file shouldn't be removed") or exit;
        ok(-e $base_file, "ISO file $file shouldn't be removed") or exit;
    } else {
        isnt($base_file, $volume->file);
        ok(! -e $file);
        unlink $base_file or die "$! $base_file";
    }
}

sub test_qcow2($vm, $swap = 0) {
    use_ok('Ravada::Volume::QCOW2') or return;

    my $file = $vm->dir_img."/".new_domain_name();
    $file .= ".SWAP" if $swap;
    $file .= ".qcow2";

    my @cmd = ("qemu-img","create","-f","qcow2",$file,"1M");
    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    is($err,'') or return;

    _do_test_file("QCOW2", $vm, $file);
    $vm->remove_file($file);
}

sub test_raw($vm, $swap = 0) {
    use_ok('Ravada::Volume::RAW') or return;

    my $file = $vm->dir_img."/".new_domain_name();
    $file .= ".SWAP" if $swap;
    $file .= ".raw";

    make_path($vm->dir_img) if ! -e $vm->dir_img;
    my @cmd = ("qemu-img","create","-f","raw",$file,"1M");
    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    is($err,'') or return;

    _do_test_file("RAW", $vm, $file);
    $vm->remove_file($file);
}


sub test_iso($vm) {
    use_ok('Ravada::Volume::ISO') or return;

    my $iso = $vm->dir_img."/".new_domain_name().".iso";
    open my $out,">",$iso;
    close $out;

    _do_test_file("ISO", $vm, $iso);
}

sub test_void($vm, $swap=0) {
    use_ok('Ravada::Volume::Void') or return;

    my $file = $vm->dir_img."/".new_domain_name();
    $file .= ".SWAP" if $swap;
    $file .= ".void";
    my $data = {
        capacity => 1024
        ,type => 'file'
    };
    $vm->write_file($file, Dump($data));
    _do_test_file("Void", $vm, $file);

    $vm->remove_file($file);
}

sub test_void_swap($vm) {
    test_void($vm,1);
}

sub test_qcow2_swap($vm) {
    test_qcow2($vm,1);
}

sub test_raw_swap($vm) {
    test_raw($vm,1);
}

sub test_rebase($volume) {
    my $file_base;
    eval { $file_base = test_base($volume) };
    is($@,'');
    return $file_base;
}

sub test_defaults($vm, $volume_type=undef) {
    diag("Testing defaults for ".$vm->name);
    my $domain = create_domain($vm);
    my @format;
    @format = ( format => $volume_type ) if $vm->type eq 'void' && $volume_type;
    $domain->add_volume( type => 'swap', size => 1024*1024, @format );
    $domain->add_volume( type => 'data', size => 1024*1024, @format);
    for my $volume ( $domain->list_volumes_info ) {
        ok(-e $volume->file,$volume->file) or exit;
        my $file_base = test_base($volume);
        delete $volume->{_qemu_info};
        my $file_rebase = test_rebase($volume);
        next if !$file_rebase;
        isnt($file_base, $file_rebase) if $file_base !~ /iso$/;
        unlink $file_base or die "$! $file_base" if $file_base !~ /iso$/;
    }
    my $info = $domain->info(user_admin);
    my $disk = $info->{hardware}->{disk};

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $info_f = $domain_f->info(user_admin);
    my $disk_f = $info_f->{hardware}->{disk};

    is(scalar(@$disk), scalar(@$disk_f));
    for my $field ( qw(name driver capacity device type target)) {
        for my $n ( 0 .. @$disk ) {
            my $dev = $disk->[0];
            my $dev_f = $disk_f->[0];
            ok(exists $dev->{$field}, "Expecting field $field") or die Dumper($dev);
            ok(exists $dev_f->{$field}, "Expecting field $field") or die Dumper($dev_f);
            if ($field eq 'capacity') {
                like($dev_f->{$field},qr(^\d+[A-Z]$));
                next;
            }
            is($dev->{$field}, $dev_f->{$field}) or die Dumper($dev, $dev_f);
        }
    }

    $domain->remove(user_admin);
}

sub test_qcow_format($vm) {
    return if $vm->type ne 'KVM';
    my $base = create_domain($vm);
    $base->add_volume(type => 'swap', size => 1024*1024);
    $base->add_volume(type => 'data', size => 1024*1024);

    my $clone = $base->clone(
         name => new_domain_name
        ,user => user_admin
    );
    my $QEMU_IMG = `which qemu-img`;
    chomp $QEMU_IMG;
    for my $vol ( $clone->list_volumes_info ) {
        next if $vol->file && $vol->file =~ /iso$/;
        my @cmd = ($QEMU_IMG,'create'
            ,'-f','qcow2'
            ,"-b", $vol->backing_file
            ,$vol->file
        );
        $clone->_vm->run_command(@cmd);
        my @cmd_info = ($QEMU_IMG , 'info', $vol->file);
        my ($out, $err) = $clone->_vm->run_command(@cmd_info);
        my ($bff) = $out =~ /^backing file format: (.*)/m;
        is($bff, undef);
    }
    eval { $clone->start(user_admin) };
    is(''.$@,'');
    $clone->shutdown_now(user_admin);

    for my $vol ( $clone->list_volumes_info ) {
        next if !$vol->file || $vol->file =~ /iso$/;

        my @cmd_info = ($QEMU_IMG , 'info', $vol->file);
        my ($out, $err) = $clone->_vm->run_command(@cmd_info);
        my ($bff) = $out =~ /^backing file format: (.*)/m;
        is($bff, 'qcow2');
    }

    eval { $clone->start(user_admin) };
    is(''.$@,'');

    _remove_domains($base);
}

sub _remove_domains(@bases) {
    for my $base (@bases) {
        for my $clone ($base->clones) {
            my $d_clone = Ravada::Domain->open($clone->{id});
            $d_clone->remove(user_admin);
        }
        $base->remove(user_admin);
    }
}

#########################################################

init();
clean();
for my $vm_name (reverse vm_names() ) {
    my $vm;
    eval {
        $vm = rvd_back->search_vm($vm_name);
    };
    SKIP: {
        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        if (0 && $vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing volumes in $vm_name");
        init_vm($vm);

        test_qcow_format($vm);

        test_raw($vm);
        test_raw_swap($vm);

        test_void($vm);
        test_qcow2($vm);
        test_iso($vm);

        test_void_swap($vm);
        test_qcow2_swap($vm);

        test_defaults($vm,'qcow2');
        test_defaults($vm);
    }
}

end();
done_testing();
