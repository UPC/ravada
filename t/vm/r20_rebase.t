use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3 qw(run3);
use POSIX qw(WNOHANG);
use Test::More;
use YAML qw(Load LoadFile DumpFile Dump);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my $MOD_NBD= 0;
my $DEV_NBD = "/dev/nbd10";
my $MNT_RVD= "/mnt/test_rvd";
my $QEMU_NBD = `which qemu-nbd`;
chomp $QEMU_NBD;

ok($QEMU_NBD,"Expecting qemu-nbd command") or do {
    done_testing;
    exit;
};

init();

######################################################################
sub test_rebase_3times($vm, $swap, $data, $with_cd) {

    my $base1 = create_domain($vm);
    $base1->add_volume(type => 'swap', size => 1024*1024) if $swap;
    $base1->add_volume(type => 'data', size => 1024*1024) if $data;

    _mangle_vol2($vm, "base1",$base1->list_volumes);
    $base1->prepare_base(user => user_admin, with_cd => $with_cd);

    my $base2 = $base1->clone( name => new_domain_name, user => user_admin);
    _mangle_vol2($vm, "base2",$base2->list_volumes);

    my $clone = $base1->clone( name => new_domain_name, user => user_admin);
    for my $file ( $clone->list_volumes ) {
        test_volume_contents2($vm, $file,"base1");
    }
    $base2->prepare_base(user => user_admin, with_cd => $with_cd);

    $clone->rebase(user_admin, $base2);
    is($clone->id_base, $base2->id);
    for my $file ( $clone->list_volumes() ) {
        my ($type) =$file =~ /\.([A-Z]+)\./;
        if ($type && $type eq 'DATA') {
            test_volume_contents2($vm,$file,"base1");
            test_volume_contents2($vm,$file,"base2",0);
        } else {
            test_volume_contents2($vm,$file,"base1");
            test_volume_contents2($vm,$file,"base2");
        }
    }

    _mangle_vol2($vm, "clone", $clone->list_volumes);
    $clone->rebase(user_admin, $base1);
    is($clone->id_base, $base1->id);
    for my $file ( $clone->list_volumes() ) {
        my ($type) =$file =~ /\.([A-Z]+)\./;
        if ($type && $type eq 'DATA') {
            test_volume_contents2($vm,$file,"base1");
            test_volume_contents2($vm,$file,"base2",0);
            test_volume_contents2($vm,$file,"clone",1);
        } else {
            test_volume_contents2($vm,$file,"base1");
            test_volume_contents2($vm,$file,"base2",0);
            test_volume_contents2($vm,$file,"clone",0);
        }
    }

    my $base3 = $base2->clone(name => new_domain_name, user => user_admin);
    _mangle_vol2($vm, "clone", $base3->list_volumes);
    $base3->prepare_base(user => user_admin, with_cd => $with_cd);

    $clone->rebase(user_admin, $base3);
    is($clone->id_base, $base3->id);
    for my $file ( $clone->list_volumes() ) {
        my ($type) =$file =~ /\.([A-Z]+)\./;
        if ($type && $type eq 'DATA') {
            test_volume_contents2($vm,$file,"base1");
            test_volume_contents2($vm,$file,"base2",0);
            test_volume_contents2($vm,$file,"base3",0);
            test_volume_contents2($vm,$file,"clone",1);
        } else {
            test_volume_contents2($vm,$file,"base1");
            test_volume_contents2($vm,$file,"base2",0);
            test_volume_contents2($vm,$file,"base3",1);
            test_volume_contents2($vm,$file,"clone",0);
        }
    }

    $clone->remove(user_admin);
    $base1->remove(user_admin);
    $base2->remove(user_admin);
    $base3->remove(user_admin);
}

sub test_rebase_with_vols($vm, $swap0, $data0, $with_cd0, $swap1, $data1, $with_cd1) {
    #diag("\nsw da cd");
    #diag("$swap0, $data0, $with_cd0\n$swap1, $data1, $with_cd1");

    my $same_outline = 0;
    $same_outline = ( $swap0 == $swap1 ) && ($data0 == $data1) && ($with_cd0 == $with_cd1);

    my $base = create_domain($vm);
    $base->add_volume(type => 'swap', size => 1024*1024)    if $swap0;
    $base->add_volume(type => 'data', size => 1024*1024)    if $data0;
    $base->prepare_base(user => user_admin, with_cd => $with_cd0);

    my $clone1 = $base->clone( name => new_domain_name, user => user_admin);

    my @volumes_before = $clone1->list_volumes();
    _mangle_vol($vm,@volumes_before);

    my %backing_file = map { $_->file => $_->backing_file }
        grep { $_->file } $clone1->list_volumes_info;

    my $base2 = create_domain($vm);
    $base2->add_volume(type => 'swap', size => 1024*1024)    if $swap1;
    $base2->add_volume(type => 'data', size => 1024*1024)    if $data1;
    $base2->prepare_base(user => user_admin, with_cd => $with_cd1);

    my @reqs;
    eval { @reqs = $clone1->rebase(user_admin, $base2) };
    if (!$same_outline) {
        like($@,qr/outline different/i) or exit;
        _remove_domains($base, $base2);
        return;
    } else {
        is($@, '') or exit;
    }
    my @volumes_after = $clone1->list_volumes();
    ok(scalar @volumes_after >= scalar @volumes_before,Dumper(\@volumes_after,\@volumes_before))
        or exit;

    test_match_vols(\@volumes_before, \@volumes_after);

    for my $vol ($clone1->list_volumes_info) {
        my $file = $vol->file or next;
        test_volume_contents($vm,$file);

        my $bf2 = $base2->name;
        if ( $file !~ /\.iso$/ ) {
            like ($vol->backing_file, qr($bf2), $vol->file) or exit;
            isnt($vol->backing_file, $backing_file{$vol->file}) if $backing_file{$file};
        } else {
            is($vol->backing_file, $backing_file{$vol->file}) if $backing_file{$file};
        }
        # we may check inside eventually but it is costly
    }
    _remove_domains($base, $base2);
}

sub test_volume_contents($vm, $file) {
    if ($file =~ /\.iso$/) {
        my $file_type = `file $file`;
        chomp $file_type;
        if ($file_type =~ /ASCII/) {
            my $data = LoadFile($file);
            ok($data->{iso});
        } else {
            like($file_type , qr/DOS\/MBR/);
        }
    } elsif ($file =~ /\.void$/) {
        my $data = LoadFile($file);
        if ($file =~ /\.DATA\./) {
            like($data->{a},qr(b{20}), $file);
        } else {
            is($data->{a},undef);
        }
    } elsif ($file =~ /\.qcow2$/) {
        if ($file =~ /\.DATA\./) {
            test_file_exists($vm,$file);
        } else {
            test_file_not_exists($vm,$file)
        }
    }
}

sub test_volume_contents2($vm, $file, $name, $expected=1) {
    if ($file =~ /\.void$/) {
        my $data = LoadFile($file);
        if ($file =~ /\.DATA\./) {
            if ($expected) {
                ok(exists $data->{$name}, "Expecting $name in ".Dumper($file,$data)) or confess;
            } else {
                ok(!exists $data->{$name}, "Expecting no $name in ".Dumper($file,$data)) or confess;
            }
        }
    } elsif ($file =~ /\.qcow2$/) {
        if ($file =~ /\.DATA\./) {
            test_file_exists2($vm, $file, $name, $expected);
        }
    } elsif ($file =~ /\.iso$/) {
        my $file_type = `file $file`;
        chomp $file_type;
        if ($file_type =~ /ASCII/) {
            my $data = LoadFile($file);
            ok($data->{iso});
        } else {
            like($file_type , qr/DOS\/MBR/);
        }
    } else {
        confess "I don't know how to check vol contents of '$file'";
    }
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

sub _mangle_vol($vm,@vol) {
    for my $file (@vol) {
        if ($file =~ /\.void$/) {
            my $data = Load($vm->read_file($file));
            $data->{a} = "b" x 20;
            $vm->write_file($file, Dump($data));
        } elsif ($file =~ /\.qcow2$/) {
            _mount_qcow($vm, $file);
            open my $out,">","/mnt/test_rvd/".base_domain_name.".txt";
            print $out "hola\n";
            close $out;
            _umount_qcow();
        }
    }
}

sub _mangle_vol2($vm,$name,@vol) {
    for my $file (@vol) {

        if ($file =~ /\.void$/) {
            my $data = Load($vm->read_file($file));
            $data->{$name} = "c" x 20;
            $vm->write_file($file, Dump($data));

        } elsif ($file =~ /\.qcow2$/) {
            _mount_qcow($vm, $file);
            open my $out,">","/mnt/test_rvd/$name";
            print $out ("c" x 20)."\n";
            close $out;
            _umount_qcow();
        }
    }
}


sub _mount_qcow($vm, $vol) {
    my ($in,$out, $err);
    if (!$MOD_NBD++) {
        my @cmd =("/sbin/modprobe","nbd", "max_part=63");
        run3(\@cmd, \$in, \$out, \$err);
        die join(" ",@cmd)." : $? $err" if $?;
    }
    $vm->run_command($QEMU_NBD,"-d", $DEV_NBD);
    for ( 1 .. 10 ) {
        ($out, $err) = $vm->run_command($QEMU_NBD,"-c",$DEV_NBD, $vol);
        last if !$err || $err !~ /NBD socket/;
        sleep 1;
    }
    confess "qemu-nbd -c $DEV_NBD $vol\n?:$?\n$out\n$err" if $? || $err;
    _create_part($DEV_NBD);
    $vm->run_command("/sbin/mkfs.ext4","${DEV_NBD}p1");
    die "Error on mkfs" if $?;
    mkdir "$MNT_RVD" if ! -e $MNT_RVD;
    $vm->run_command("/bin/mount","${DEV_NBD}p1",$MNT_RVD);
    exit if $?;
}

sub _create_part($dev) {
    my @cmd = ("/sbin/fdisk","-l",$dev);
    my ($in,$out, $err);
    for my $retry ( 1 .. 10 ) {
        run3(\@cmd, \$in, \$out, \$err);
        last if !$err;
        warn $err if $err && $retry>2;
        sleep 1;
    }
    confess join(" ",@cmd)."\n$?\n$out\n$err\n" if $err || $?;

    return if $out =~ m{/dev/\w+\d+p\d+}mi;

    for (1 .. 10) {
        @cmd = ("/sbin/fdisk",$dev);
        $in = "n\np\n1\n\n\n\nw\np\n";

        run3(\@cmd, \$in, \$out, \$err);
        chomp $err;
        last if !$err || $err !~ /evice.*busy/;
        diag($err." retrying");
        sleep 1;
    }
    ok(!$err) or die join(" ",@cmd)."\n$?\nIN: $in\nOUT:\n$out\nERR:\n$err";
}
sub _umount_qcow() {
    my @cmd = ("umount",$MNT_RVD);
    my ($in, $out, $err);
    for ( ;; ) {
        run3(\@cmd, \$in, \$out, \$err);
        last if $err !~ /busy/i || $err =~ /not mounted/;
        sleep 1;
    }
    die $err if $err && $err !~ /busy/ && $err !~ /not mounted/;
    `qemu-nbd -d $DEV_NBD`;
}

sub test_file_exists($vm, $vol, $expected=1) {
    _mount_qcow($vm,$vol);
    my $ok = -e $MNT_RVD."/".base_domain_name.".txt";
    _umount_qcow();
    return 1 if $ok && $expected;
    return 1 if !$ok && !$expected;
    return 0;
}
sub test_file_exists2($vm, $vol,$name, $expected=1) {
    _mount_qcow($vm,$vol);
    my $ok = -e $MNT_RVD."/".base_domain_name.".txt";
    _umount_qcow();
    return 1 if $ok && $expected;
    return 1 if !$ok && !$expected;
    return 0;
}


sub test_file_not_exists($vm, $vol) {
    return test_file_exists($vm,$vol, 0);
}

sub _key_for($a) {
    my($key) = $a =~ /\.([A-Z]+)\.\w+$/;
    $key = 'SYS' if !defined $key;
    return $key;
}
sub test_match_vols($vols_before, $vols_after) {
    return if scalar(@$vols_before) != scalar (@$vols_after);
    my %vols_before = map { _key_for($_) => $_ } @$vols_before;
    my %vols_after  = map { _key_for($_) => $_ } @$vols_after;

    for my $key (keys %vols_before, keys %vols_after) {
        is($vols_before{$key}, $vols_after{$key}, $key) or die Dumper($vols_before, $vols_after);
    }
}

sub test_rebase($vm, $swap, $data, $with_cd) {
    #diag("sw: $swap , da: $data , cd: $with_cd");
    my $base = create_domain($vm);

    $base->add_volume(type => 'swap', size => 1024*1024)    if $swap;
    $base->add_volume(type => 'data', size => 1024*1024)    if $data;
    $base->prepare_base(user => user_admin, with_cd => $with_cd);

    my $clone1 = $base->clone( name => new_domain_name, user => user_admin);
    my $clone2 = $base->clone( name => new_domain_name, user => user_admin);

    wait_request();
    is(scalar($base->clones),2);

    $clone1->prepare_base(user => user_admin, with_cd => $with_cd) if $with_cd;

    my @reqs = $base->rebase(user_admin, $clone1);
    for my $req (@reqs) {
        rvd_back->_process_requests_dont_fork();
        is($req->status, 'done' ) or exit;
        is($req->error, '', $req->command." ".$clone2->name) or exit;
    }

    $clone1 = Ravada::Domain->open($clone1->id);
    is($clone1->id_base, undef ) or exit;
    is($clone1->is_base, 1);

    $clone2 = Ravada::Domain->open($clone2->id);
    is($clone2->id_base, $clone1->id );

    is(scalar($base->clones),0);
    is(scalar($clone1->clones),1);

    $clone2->remove(user_admin);
    $clone1->remove(user_admin);
    $base->remove(user_admin);
}

######################################################################


clean();
$ENV{LANG}='C';
_umount_qcow();

for my $vm_name (reverse vm_names() ) {
    ok($vm_name);
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing rebase for $vm_name");

        for my $swap0 ( 0 , 1 ) {
            for my $data0 ( 0 , 1 ) {
                for my $with_cd0 ( 0 , 1 ) {
                    test_rebase($vm, $swap0, $data0, $with_cd0);
                    test_rebase_3times($vm, $swap0, $data0, $with_cd0);
                    for my $swap1 ( 0 , 1 ) {
                        for my $with_cd1 ( 0 , 1 ) {
                            for my $data1 ( 0 , 1 ) {
                                test_rebase_with_vols($vm, $swap0, $data0, $with_cd0
                                    , $swap1, $data1, $with_cd1);

                            }
                        }
                    }
                }
            }
        }
    }
}

clean();

done_testing();
