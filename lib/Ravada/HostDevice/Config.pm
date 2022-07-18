package Ravada::HostDevice::Config;

use warnings;
use strict;

no warnings "experimental::signatures";
use feature qw(signatures);

use Carp qw(confess);
use Data::Dumper qw(Dumper);
use File::Copy qw(copy);
use IPC::Run3 qw(run3);
use File::Path qw(make_path);
use Text::Diff;

my $FILE_GRUB="/etc/default/grub";
my $FILE_BLACKLIST="/etc/modprobe.d/blacklist-gpu.conf";
my $FILE_VFIO = "/etc/modprobe.d/vfio.conf";
my $FILE_MODULES = "/etc/modules";
my $FILE_KVM ="/etc/modprobe.d/kvm.conf";
my $FILE_INITRAMFS = "/etc/initramfs-tools/modules";

sub configure_grub($devices, $file=$FILE_GRUB, $dst="/") {
    $file = $FILE_GRUB if !defined $file;

    my $file_out = _file_out($file);

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;

        if ($line =~ /^(GRUB_CMDLINE_LINUX_DEFAULT)="(.*)"/) {
            my $var = $1;
            my $grub_value = $2;

            my %fields = map { $_ => 1 } split /\s+/,$grub_value;

            _grub_blacklist(\%fields, $devices);
            _grub_iommu(\%fields, $devices);
            _grub_pci_stub(\%fields, $devices);

            my $grub_value_new =join(" ",sort keys %fields);

            print $out "$var=\"$grub_value_new\"\n";
        } else {
            print $out "$line\n";
        }
    }
    close $in;
    close $out;

    _update_file($file, $file_out, $dst);
}

sub configure_blacklist($devices,$file=$FILE_BLACKLIST) {
    my $file_out = _file_out($file);

    my %found;

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;
        my ($module) = $line =~ /\s*blacklist\s*(.*)/;
        my $configure = _is_module_configured($devices, $module);
        if (defined $configure) {
            $found{$module}++;
            if (!$configure) {
                next;
            }
        }
        print $out "$line\n";
    }

    for my $driver ( _drivers_blacklist($devices) ) {
        next if $found{$driver};
        print $out "blacklist $driver\n";
    }

    close $in;
    close $out;

    _update_file($file, $file_out);
}

sub configure_vfio($devices, $file=$FILE_VFIO) {
    my $file_out= _file_out($file);

    my %found;

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;
        my ($module) = $line =~ /\s*softdep\s*(.*?) pre: vfio-pci/;
        my $configure = _is_module_configured($devices, $module);
        if (defined $configure) {
            $found{$module}++;
            if (!$configure) {
                next;
            }
        }
        print $out "$line\n";
    }

    for my $driver ( _drivers_blacklist($devices) ) {
        next if $found{$driver};
        print $out "softdep $driver pre: vfio-pci\n";
    }

    close $in;
    close $out;

    _update_file($file, $file_out);

}

sub configure_vfio_ids($devices, $file=$FILE_VFIO) {
    my $file_out= _file_out($file);

    my $ids = join(",",_configure_ids($devices));

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";

    my $found=0;
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ /^\s*options vfio-pci ids=(.*?) (.*)/) {
            $found++;
            if ($ids ne $1) {
                print $out "options vfio-pci ids=$ids $2\n";
            } else {
                next;
            }
        }
        print $out "$line\n";
    }

    if (!$found) {
        print $out "options vfio-pci ids=$ids disable_vga=1\n";
    }

    close $in;
    close $out;

    _update_file($file, $file_out);

}


sub configure_modules($devices, $file=$FILE_MODULES) {
    my $ids = join(",",_configure_ids($devices));

    my $file_out= _file_out($file);

    my $found;

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ /^\s*vfio vfio_iommu_type1 vfio_pci ids=(.*)/) {
            $found = 1;
            if ($ids && $ids ne $1) {
                print $out "vfio vfio_iommu_type1 vfio_pci ids=$ids\n";
            }
        } else {
            print $out "$line\n";
        }
    }
    if (!$found && $ids) {
        print $out "vfio vfio_iommu_type1 vfio_pci ids=$ids\n";
    }

    close $out;
    close $in;

    _update_file($file, $file_out);

}

sub configure_msrs($devices,$file=$FILE_KVM) {
    my $ids = join(",",_configure_ids($devices));

    my $file_out= _file_out($file);

    my $found;

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ /^\s*options kvm /) {
            $found++;
            if ($ids) {
                next if $line =~ /ignore_msrs=1/;
                print $out  "options kvm ignore_msrs=1\n";
            } else {
                next if $line =~ /ignore_msrs=0/ || $line !~ /ignore_msrs/;
            }
            next;
        }
        print $out "$line\n";
    }
    if (!$found) {
        print $out  "options kvm ignore_msrs=1\n";
    }
    close $out;
    close $in;

    _update_file($file, $file_out);

}

sub configure_initramfs($devices,$file=$FILE_INITRAMFS) {
    my $ids = join(",",_configure_ids($devices));

    my $file_out= _file_out($file);

    my $found;

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ /^\s*vfio vfio_iommu_type1 vfio_virqfd.*ids=(.*)(\s|$)/) {
            $found++;
            if ($ids) {
                next if $ids eq $1;
                $found=0;
                next;
            } else {
            }
            next;
        }
        print $out "$line\n";
    }
    if (!$found) {
        print $out "vfio vfio_iommu_type1 vfio_virqfd vfio_pci"
        ." ids=$ids\n";
    }
    close $out;
    close $in;

    _update_file($file, $file_out);


}

sub _drivers_blacklist($devices) {
    my @drivers;
    for my $pci (keys %$devices) {
        next if !$devices->{$pci}->{configure};
        push @drivers,@{$devices->{$pci}->{driver}};
    }
    return @drivers;
}

sub _is_module_configured($devices, $module) {
    for my $pci (keys %$devices) {
        for my $driver (@{$devices->{$pci}->{driver}}) {
            return $devices->{$pci}->{configure}
            if $driver eq $module;
        }
    }
    return undef;
}

sub _update_file($file, $file_out, $dst='/') {
    my $diff = diff $file,$file_out;
    warn $diff;
    if (!$diff) {
        unlink $file_out;
        return;
    }else {
        $file = "$dst/$file" if $dst ne "/";
        my ($path) = $file =~ m{(.*)/};
        make_path($path) or die "$! $path"
        if ! -e $path;

        warn $file;

        copy($file_out, $file) or die "$file_out -> $file";
    }
}

sub _grub_blacklist($fields, $devices) {

    for my $entry (keys %$fields) {
        delete $fields->{$entry} if $entry =~ m{[a-z][a-z0-9]+\.blacklist=1$};
    }
    for my $pci ( keys %$devices ) {
        my $dev = $devices->{$pci};
        for my $driver ( @{$devices->{$pci}->{driver}} ) {
            my $blacklist = "$driver.blacklist=1";
            if ($dev->{configure} && !exists $fields->{$blacklist}) {
                $fields->{$blacklist}=1;
            }
        }
    }
}

sub _grub_iommu($fields, $devices) {

    my $configure = grep { $devices->{$_}->{configure} } keys %$devices;

    my @iommu_fields = _grub_iommu_by_cpu();

    for (@iommu_fields) {
        if ($configure) {
            $fields->{$_}++;
        } else {
            delete $fields->{$_};
        }
    }

}


sub _cpu_vendor() {
    my @cmd = ("lscpu");
    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    die $err if $err;
    my ($vendor) = $out =~ m{^Vendor ID:\s+(.*)}m;
    return 'intel' 	if $vendor =~ /intel$/i;
    return 'amd'	if $vendor =~ /amd$/i;
    die "Error: unknown cpu vendor $vendor\n$out";
}

sub _grub_iommu_by_cpu() {
    if (_cpu_vendor() eq 'intel') {
        return("intel_iommu=on");
    } elsif (_cpu_vendor() eq 'amd') {
        return qw(
        amd_iommu=on
        iommu=pt
        kvm_amd.npt=1
        kvm_amd.avic=1
        );
    } else {
        die "Error: I don't know cpu vendor ".cpu_vendor();
    }
}

sub _configure_ids($devices) {
    my @ids = ();
    for my $pci (sort keys %$devices){
        next if !$devices->{$pci}->{configure};
        push @ids,@{$devices->{$pci}->{id}};
    }
    return sort @ids;
}

sub _grub_pci_stub($fields, $devices) {
    my $found;
    for my $field (keys %$fields) {
        $found = $field if $field =~ m/^pci-stub.ids=/;
    }

    delete $fields->{$found} if $found;
    my @ids = _configure_ids($devices);

    return if !scalar(@ids);
    $fields->{"pci-stub.ids=".join(",",sort @ids)}=1;
}

sub now {
    my @now = localtime(time);
    $now[5]+=1900;
    $now[4]++;
    for (0..4) {
	$now[$_] = "0".$now[$_] if length($now[$_])<2;
    }
    return "$now[5]-$now[4]-$now[3].$now[2]:$now[1]:$now[0]";
}

sub _file_out($path) {
    confess "Undefinde path" if !defined $path;

    if (! -e $path ) {
        open my $out,">",$path or die "$! $path";
        close $out;
    }
    my ($name) = $path =~ m{.*/(.*)};
    $name = $path if !defined $name;

    return "/tmp/$name.".now();
}

sub _run_lspci() {
    my @cmd = ("lspci","-D","-knn");
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    return $out;
}

sub _clean_dupes($devices) {
    for my $pci (keys %$devices) {
        my %driver = map { $_ => 1 } @{$devices->{$pci}->{driver}};
        my %dev = map { $_ => 1 } @{$devices->{$pci}->{dev}};
        $devices->{$pci}->{driver} = [ keys %driver ];
        $devices->{$pci}->{dev} = [ keys %dev ];
    }
}

sub _load_devices ($vm,$file=undef) {
    my $lspci;
    if (!defined $file) {
        $lspci = _run_lspci();
    } else {
        open my $in,"<",$file or die "$! $file";
        $lspci = join"",<$in>;
        close $in;
    }
    my $found;
    my %devices;
    for my $line (split /\n/,$lspci) {
        my ($pci_data) = $line =~ m{^([0-9a-f]{4}.*?) };
        if (!$found || $pci_data ) {
            next if !$pci_data;
            for my $hd ( $vm->list_host_devices ) {
                my $filter = $hd->list_filter();
                next if !defined $filter;

                if ( $line =~ qr($filter)i ) {
                    $found = $pci_data;
                    warn "found $line\n";
                }
                last if $found;
            }
        }
        next if !$found;
        my ($dev) = $line =~ m{\[([0-9a-f]{4}\:[0-9a-f]{4})\]};
        push @{$devices{$found}->{dev}} , ($dev) if $dev;
        my ($driver) = $line =~ /\s+Kernel (?:driver|modules).*: ([a-zA-Z0-9_]+)/;

        my ($field, $value) = $line =~ /^\s+(.*?)\s*:\s*(.*)/;
        push @{$devices{$found}->{driver}},$driver if $driver && $driver !~ /vfio/i;
    }
    _clean_dupes(\%devices);

    return \%devices;
}

sub configure($vm, $file=undef, $dst='/') {
    my $devices = _load_devices($vm, $file);

    if (! -e $dst ) {
        make_path($dst);
    }
    configure_grub($devices, undef, $dst);
}

1;
