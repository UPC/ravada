use warnings;
use strict;

use Carp qw(confess croak);
use Data::Dumper;
use File::Copy qw(copy);
use Hash::Util qw(lock_hash);
use IPC::Run3;
use Mojo::JSON qw(decode_json);
use Ravada::HostDevice::Config;
use Ravada::HostDevice::Templates;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);
my $DEFAULT_GRUB = "/etc/default/grub";

my @FILES;

sub _create_grub_file() {
    my $grub_file = "/var/tmp/grub_default";
    open my $in,"<",$DEFAULT_GRUB or die "$! $DEFAULT_GRUB";
    open my $out,">",$grub_file or die "$! $grub_file";
    while (my $line = <$in>) {
        if ($line =~ /^GRUB_CMDLINE_LINUX_DEFAULT/) {
            print $out "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"\n";
        } else {
            print $out $line;
        }
    }
    close $in;
    close $out;

    push @FILES,($grub_file);

    return $grub_file;
}

sub _pci_data() {
    my %data = (
        '0000:00:1c.0' => {
            'driver' => [
                'pcieport'
            ],
            'id' => [
                '8086:a33c'
            ]
            ,configure => 0
        },
        '0000:03:00.0' => {
            'driver' => ['tg3']
            ,id => ['14e4:165a']
        },
        '0000:01:00.0' => {
            'driver' => [
                'radeon'
            ],
            'id' => [
                '1002:95c5',
                '1787:2252'
            ]
            ,configure => 1
        },
    );
    lock_hash(%data);
    return \%data;
}

sub _check_variable($file, %var) {
    open my $in,"<",$file or die "$! $file";
    my %found;
    while (my $line = <$in>) {
        chomp $line;
        my ($name, $value)= $line =~ /\s*(.*?)\s*=\s*(.*)/;
        next if !defined $name;
        if (exists $var{$name}) {
            if ($found{$name}) {
                ok(0,"Variable $name duplicated in $file");
            } else {
                is($value,$var{$name},"$name=$var{$name} in $file") or croak;
                $found{$name}++;
            }
        }
    }
}

sub _check_line($file, %var) {
    ok(-e $file,"Expecting file '$file'") or croak;
    open my $in,"<",$file or die "$! $file";
    my %found;
    while (my $line = <$in>) {
        chomp $line;

        $line =~ s/^\s*(.*?)\s*$/$1/;

        if (exists $var{$line}) {
            $found{$line}++;
        }
    }
    close $in;

    for my $name( keys %var ) {
        $found{$name}=0 if !$found{$name};

        is($found{$name},$var{$name},"Line '$name' in $file") or croak;
    }
}

sub _check_line_begins_with($file, %var) {
    open my $in,"<",$file or die "$! $file";
    my %found;
    while (my $line = <$in>) {
        chomp $line;

        for my $name (keys %var) {
            $found{$name}++ if $line =~ m/^$name/;
        }
    }
    close $in;

    for my $name( keys %var ) {
        $found{$name}=0 if !$found{$name};

        is($found{$name},$var{$name},"Line '$name' in $file");
    }
}


sub _set_pci_data($data, $driver, $value=1) {
    my $found;
    for my $pci (keys %$data) {
        for my $curr_driver (@{$data->{$pci}->{driver}}) {
            $found = $pci if $curr_driver eq $driver;
        }
    }
    die "Error: driver '$driver' not found in ".Dumper($data)
    if !$found;

    $data->{$found}->{configure} = $value;
}

sub test_grub($config) {
    my $file=_create_grub_file();

    _check_variable($file
        ,'GRUB_CMDLINE_LINUX_DEFAULT','"quiet splash"');

    my $data = _pci_data();
    $config->configure_grub($data, $file);

    _check_variable($file
        ,'GRUB_CMDLINE_LINUX_DEFAULT',
        '"intel_iommu=on pci-stub.ids=1002:95c5,1787:2252 quiet radeon.blacklist=1 splash"'
    );

    _set_pci_data($data,'radeon',0);
    _set_pci_data($data,'tg3',1);

    $config->configure_grub($data, $file);
    _check_variable($file
        ,'GRUB_CMDLINE_LINUX_DEFAULT',
        '"intel_iommu=on pci-stub.ids=14e4:165a quiet splash tg3.blacklist=1"'
    );

    # All to 0

    for my $pci (keys %$data) {
        $data->{$pci}->{configure} = 0;
    }

    $config->configure_grub($data, $file);

    _check_variable($file
        ,'GRUB_CMDLINE_LINUX_DEFAULT',
        '"quiet splash"'
    );

}

sub _create_file($name) {
    my $file = "/var/tmp/$name";
    open my $out,">",$file or die "$! $file";
    close $out;

    push @FILES,($file);
    return $file;
}

sub _create_blacklist_file() {
    my $file = "/var/tmp/blacklist-gpu.conf";
    open my $out,">",$file or die "$! $file";
    print $out "blacklist foo\n";
    close $out;

    push @FILES,($file);

    return $file;
}

sub test_blacklist($config) {
    my $file=_create_blacklist_file();

    my $data = _pci_data();

    _check_line($file
        ,'blacklist foo',1
        ,'blacklist radeon',0);
    for ( 1 .. 2 ) {
        $config->configure_blacklist($data,$file);

        _check_line($file
            ,'blacklist foo',1
            ,'blacklist tg3',0
            ,'blacklist radeon',1);

    }

    _set_pci_data($data,'radeon',0);
    _set_pci_data($data,'tg3',1);
    $config->configure_blacklist($data,$file);

    _check_line($file
            ,'blacklist foo',1
            ,'blacklist tg3',1
            ,'blacklist radeon',0);

    # All to 0

    for my $pci (keys %$data) {
        $data->{$pci}->{configure} = 0;
    }

    $config->configure_blacklist($data,$file);

    _check_line($file
            ,'blacklist foo',1
            ,'blacklist tg3',0
            ,'blacklist radeon',0);

}

sub test_vfio($config) {
    my $file=_create_file(new_domain_name().'vfio.conf');

    my $data = _pci_data();
    my $ids = '1002:95c5,1787:2252';

    $config->configure_vfio($data,$file);
    _check_line($file,"softdep radeon pre: vfio-pci",1);

    _check_line($file,"options vfio-pci ids=$ids disable_vga=1",1);

    _set_pci_data($data,'radeon',0);
    _set_pci_data($data,'tg3',1);

    $ids = '14e4:165a';

    $config->configure_vfio($data,$file);
    _check_line($file,"softdep radeon pre: vfio-pci",0);
    _check_line($file,"softdep tg3 pre: vfio-pci", 1);
    _check_line($file,"options vfio-pci ids=$ids disable_vga=1",1);

    _set_pci_data($data,'tg3',0);
    $config->configure_vfio($data,$file);
    _check_line($file,"softdep tg3 pre: vfio-pci", 0);
}

sub _copy_file($file) {
    my $new = $file;
    $new =~ s{^/}{};
    $new =~ s{/}{_}g;

    $new = "/var/tmp/$new";

    copy($file, $new);

    push @FILES,($new);
    return $new;
}

sub test_modules($config) {
    my $file = _copy_file("/etc/modules");
    my $data = _pci_data();

    my $ids = '1002:95c5,1787:2252';

    $config->configure_modules($data,$file);
    _check_line($file,"vfio vfio_iommu_type1 vfio_pci ids=$ids",1);

    _set_pci_data($data,'radeon',0);
    _set_pci_data($data,'tg3',1);

    $ids = '14e4:165a';

    $config->configure_modules($data,$file);
    _check_line($file,"vfio vfio_iommu_type1 vfio_pci ids=$ids",1);
    _check_line_begins_with($file,"vfio vfio_iommu_type1 vfio_pci",1);

    _set_pci_data($data,'tg3',0);

    $config->configure_modules($data,$file);
    _check_line($file,"vfio vfio_iommu_type1 vfio_pci ids=$ids",0);
    _check_line_begins_with($file,"vfio vfio_iommu_type1 vfio_pci",0);

}

sub test_msrs($config) {

    my $file = _create_file('kvm.conf');

    my $data = _pci_data();

    $config->configure_msrs($data, $file);
    _check_line($file,"options kvm ignore_msrs=1",1);

    $data = {};

    $config->configure_msrs($data, $file);
    _check_line($file,"options kvm ignore_msrs=1",0);

}

sub test_initramfs($config) {

    my $file = _copy_file('/etc/initramfs-tools/modules');

    my $data = _pci_data();

    my $ids = '1002:95c5,1787:2252';

    $config->configure_initramfs($data, $file);
    _check_line($file,"vfio vfio_iommu_type1 vfio_virqfd vfio_pci ids=$ids",1);
}

sub test_configs($vm) {

    my $config = Ravada::HostDevice::Config->new(vm => $vm);

    test_grub($config);
    test_blacklist($config);
    test_vfio($config);

    test_modules($config);

    test_msrs($config);

    test_initramfs($config);
}

sub _current_default_grub {
    my $quiet = '';
    my $splash = '';
    open my $in,"<","/etc/default/grub" or die $!;
    while (my $line = <$in>) {
        if ($line =~ /^GRUB_CMDLINE_LINUX_DEFAULT/) {
            my ($quiet) = $line =~ /(quiet)/;
            my ($splash) = $line =~ /(splash)/;
            $quiet = " $quiet" if $quiet;
            $splash = " $splash" if $splash;
            return (($quiet or ''), ($splash or ''));
        }
    }
    return ('','');
}

sub test_example_ati_tg3($vm) {

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($pci) = grep { $_->{name} eq 'PCI' } @$templates;
    ok($pci,"Expecting PCI template in ".$vm->name) or return;

    my $id = $vm->add_host_device(template => $pci->{name});

    my @list_hostdev = $vm->list_host_devices();
    my ($hd) = $list_hostdev[-1];
    $hd->_data( 'list_filter' => '(Broad|VGA.*Radeon)');

    my $dst = "/var/tmp/".new_domain_name();

    my $config = Ravada::HostDevice::Config->new( vm => $vm
        , dst => $dst
    );
    ok($config);

    $config->configure('t/etc/lspci_ati_tg3.txt');
    my $file = "$dst/etc/default/grub";
    ok( -e $file)  or die "Missing $file";
    my $ids = "1002:95c5,14e4:165a,1787:2252";
    my ($quiet, $splash) = _current_default_grub();
    _check_variable($file
        ,'GRUB_CMDLINE_LINUX_DEFAULT',
        '"intel_iommu=on pci-stub.ids='.$ids."$quiet radeon.blacklist=1$splash tg3.blacklist=1\""
    );

    _check_line("$dst/etc/modprobe.d/blacklist-rvd.conf"
            ,'blacklist tg3',1
            ,'blacklist radeon',1);

    _check_line("$dst/etc/modprobe.d/vfio.conf","softdep radeon pre: vfio-pci",1);
    _check_line("$dst/etc/modprobe.d/vfio.conf","softdep tg3 pre: vfio-pci", 1);

    _check_line("$dst/etc/modprobe.d/vfio.conf","options vfio-pci ids=$ids disable_vga=1",1);

    _check_line("$dst/etc/modules","vfio vfio_iommu_type1 vfio_pci ids=$ids",1);

    _check_line("$dst/etc/modprobe.d/kvm.conf",'options kvm ignore_msrs=1',1);

    _check_line("$dst/etc/initramfs-tools/modules","vfio vfio_iommu_type1 vfio_virqfd vfio_pci ids=$ids",1);

    $hd->remove();

}

sub test_request_empty($vm) {
    my $req = Ravada::Request->configure_boot_hostdevices(
        id_vm => $vm->id
        ,uid => user_admin->id
    );
    wait_request();
    ok($req->status, '');
    my $out;
    eval { $out = decode_json($req->output) };
    is($@,'');

    for my $file (keys %$out) {
        is($out->{$file},'');
    }
}

sub test_request($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($pci) = grep { $_->{name} eq 'PCI' } @$templates;
    ok($pci,"Expecting PCI template in ".$vm->name) or return;

    my $id = $vm->add_host_device(template => $pci->{name});

    my @list_hostdev = $vm->list_host_devices();
    my ($hd) = $list_hostdev[-1];
    $hd->_data( 'list_filter' => '(Broad|VGA.*Radeon)');

    my $req = Ravada::Request->configure_boot_hostdevices(
        id_vm => $vm->id
        ,uid => user_admin->id
        ,test => 1
        ,file => 't/etc/lspci_ati_tg3.txt'
    );

    wait_request();
    ok($req->status, '');
    my $out;
    eval { $out = decode_json($req->output) };
    is($@,'');

    for my $file (keys %$out) {
        like($out->{$file},qr'.');
    }
}


sub _clean_files() {
    for my $file (@FILES) {
        unlink $file or die "$! $file"
        if -e $file;
    }
}

########################################################################


init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_example_ati_tg3($vm);
        test_configs($vm);
        test_request_empty($vm);
        test_request($vm);
    }
}

_clean_files();

end();

done_testing();
