package Ravada::HostDevice::Config;

use warnings;
use strict;

use Carp qw(confess croak);
use Data::Dumper qw(Dumper);
use File::Copy qw(copy);
use IPC::Run3 qw(run3);
use File::Path qw(make_path);
use Moose;
use Text::Diff;

no warnings "experimental::signatures";
use feature qw(signatures);

my $FILE_GRUB="/etc/default/grub";
my $FILE_BLACKLIST="/etc/modprobe.d/blacklist-rvd.conf";
my $FILE_VFIO = "/etc/modprobe.d/vfio.conf";
my $FILE_MODULES = "/etc/modules";
my $FILE_KVM ="/etc/modprobe.d/kvm.conf";
my $FILE_INITRAMFS = "/etc/initramfs-tools/modules";

has 'dst' => (
    is => 'ro'
    ,isa => 'Str'
    ,required => 0
    ,default => sub { return '/' }
);

has 'vm' => (
    is => 'ro'
    ,does => 'Ravada::VM'
    ,required => 1
);

sub configure_grub($self, $devices, $file=$FILE_GRUB) {

    my $file_out = _file_out($file);

    open my $in,"<",$file       or die "$! $file";
    open my $out,">",$file_out  or die "$! $file_out";
    while (my $line = <$in>) {
        chomp $line;

        if ($line =~ /^(GRUB_CMDLINE_LINUX_DEFAULT)="(.*)"/) {
            my $var = $1;
            my $grub_value = $2;

            my %fields = map { $_ => 1 } split /\s+/,$grub_value;

            $self->_grub_blacklist(\%fields, $devices);
            $self->_grub_iommu(\%fields, $devices);
            $self->_grub_pci_stub(\%fields, $devices);

            my $grub_value_new =join(" ",sort keys %fields);

            print $out "$var=\"$grub_value_new\"\n";
        } else {
            print $out "$line\n";
        }
    }
    close $in;
    close $out;

    $self->_update_file($file, $file_out);
}

sub configure_blacklist($self, $devices,$file, $dst="/") {

    my $file_out = _file_out($file);

    my %found;

    my $fh = open my $in,"<",$file;
    open my $out,">",$file_out  or die "$! $file_out";

    if ($fh) {
        while (my $line = <$in>) {
            chomp $line;
            my ($module) = $line =~ /\s*blacklist\s*(.*)/;
            if ($module ) {
                my $configure = _is_module_configured($devices, $module);
                if (defined $configure) {
                    $found{$module}++;
                    if (!$configure) {
                        next;
                    }
                }
            }
            print $out "$line\n";
        }
    }

    for my $driver ( _drivers_blacklist($devices) ) {
        next if $found{$driver};
        print $out "blacklist $driver\n";
    }

    close $in if $in;
    close $out;

    $self->_update_file($file, $file_out);
}

sub configure_vfio($self,$devices, $file) {

    my $file_out= _file_out($file);

    my $ids = join(",",_configure_ids($devices));

    my %found;
    my $found_options;

    my $fh = open my $in,"<",$file;
    open my $out,">",$file_out  or die "$! $file_out";

    if ($fh ) {
        while (my $line = <$in>) {
            chomp $line;
            my ($module) = $line =~ /\s*softdep\s*(.*?) pre: vfio-pci/;
            my $configure;

            $configure = _is_module_configured($devices, $module)
            if defined $module;

            if (defined $configure && $module) {
                $found{$module}++;
                if (!$configure) {
                    next;
                }
            }
            if ($line =~ /^\s*options vfio-pci ids=(.*?) (.*)/) {
                $found_options++;
                if ($ids ne $1) {
                    print $out "options vfio-pci ids=$ids $2\n";
                } else {
                    next;
                }
            }

            print $out "$line\n";
        }
    }

    for my $driver ( _drivers_blacklist($devices) ) {
        next if $found{$driver};
        print $out "softdep $driver pre: vfio-pci\n";
    }
    if (!$found_options) {
        print $out "options vfio-pci ids=$ids disable_vga=1\n";
    }

    close $in;
    close $out;

    $self->_update_file($file, $file_out);

}

sub _configure_vfio_ids($self, $devices, $file=$FILE_VFIO) {
    $file = $FILE_VFIO if !defined $file;
    my $file_out= _file_out($file);

    my $ids = join(",",_configure_ids($devices));

    my $fh = open my $in,"<",$file;
    open my $out,">",$file_out  or die "$! $file_out";

    my $found=0;
    if ($fh) {
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
    }


    close $in;
    close $out;

    $self->_update_file($file, $file_out);

}


sub configure_modules($self, $devices, $file) {
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

    $self->_update_file($file, $file_out);

}

sub configure_msrs($self, $devices,$file) {
    my $ids = join(",",_configure_ids($devices));

    my $file_out= _file_out($file);

    my $found;

    my $fh = open my $in,"<",$file;
    open my $out,">",$file_out  or die "$! $file_out";
    if ($fh) {
        while (my $line = <$in>) {
            chomp $line;
            if ($line =~ /^\s*options kvm /) {
                $found++;
                if ($ids) {
                    next if $line =~ /ignore_msrs=1/;
                    print $out  "options kvm ignore_msrs=1\n";
                } else {
                    next if $line =~ /ignore_msrs=0/
                    || $line !~ /ignore_msrs/;
                }
                next;
            }
            print $out "$line\n";
        }
    }
    if (!$found) {
        print $out  "options kvm ignore_msrs=1\n";
    }
    close $out;
    close $in;

    $self->_update_file($file, $file_out);

}

sub configure_initramfs($self, $devices,$file) {
    my $ids = join(",",_configure_ids($devices));

    my $file_out= _file_out($file);

    my $found;

    my $fh = open my $in,"<",$file;
    open my $out,">",$file_out  or die "$! $file_out";
    if ($fh ) {
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
    }
    if (!$found) {
        print $out "vfio vfio_iommu_type1 vfio_virqfd vfio_pci"
        ." ids=$ids\n";
    }
    close $out;
    close $in;

    $self->_update_file($file, $file_out);

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
    confess if !defined $module;
    for my $pci (keys %$devices) {
        for my $driver (@{$devices->{$pci}->{driver}}) {
            return $devices->{$pci}->{configure}
            if $driver eq $module;
        }
    }
    return;
}

sub _file_contents($file) {
    open my $in,"<",$file or die $!;
    return join("",<$in>);
}

sub _update_file($self, $file, $file_out) {
    my $diff;
    if (-e $file) {
        $diff = diff($file,$file_out, {STYLE => 'Unified'});
    }
    $self->{log}->{$file} = ($diff or _file_contents($file_out));
    if (defined $diff && !$diff) {
        unlink $file_out;
        return;
    }else {
        my $dst = $self->dst;
        $file = "$dst$file" if defined $dst && $dst ne "/";
        my ($path) = $file =~ m{(.*)/};
        make_path($path) or die "$! $path"
        if ! -e $path;

        copy($file_out, $file) or die "$file_out -> $file";
    }
}

sub _grub_blacklist($self,$fields, $devices) {

    confess if !ref($devices);

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

sub _grub_iommu($self, $fields, $devices) {

    my $configure = grep { $devices->{$_}->{configure} } keys %$devices;

    my @iommu_fields = $self->_grub_iommu_by_cpu();

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

sub _grub_iommu_by_cpu($self) {
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
        next if !$devices->{$pci}->{configure}
            || !exists $devices->{$pci}->{id};
        push @ids,@{$devices->{$pci}->{id}};
    }
    my @ids2 = sort @ids;
    return @ids2;
}

sub _grub_pci_stub($self, $fields, $devices) {
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
    confess "Undefined path" if !defined $path;

    my ($name) = $path =~ m{.*/(.*)};
    $name = $path if !defined $name;

    my $file = "/tmp/$name.".now();
    my $n=2;
    while ( -e $file ) {
        $file = "/tmp/$name.$n.".now();
        $n++;
    }
    return $file;
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
        my %id = map { $_ => 1 } @{$devices->{$pci}->{id}};
        $devices->{$pci}->{driver} = [ keys %driver ];
        $devices->{$pci}->{id} = [ keys %id];
    }
}

sub _load_devices ($self, $file=undef) {
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
            $found = $pci_data;
            $devices{$found}->{configure}=0;
            for my $hd ( $self->vm->list_host_devices ) {
                my $filter = $hd->list_filter();
                next if !defined $filter;

                if ( $line =~ qr($filter)i ) {
                    $devices{$found}->{configure}=1;
                }

                last if $found;
            }
        }
        next if !$found;
        my ($id) = $line =~ m{\[([0-9a-f]{4}\:[0-9a-f]{4})\]};
        push @{$devices{$found}->{id}} , ($id) if $id;
        my ($driver) = $line =~ /\s+Kernel (?:driver|modules).*: ([a-zA-Z0-9_]+)/;

        my ($field, $value) = $line =~ /^\s+(.*?)\s*:\s*(.*)/;
        push @{$devices{$found}->{driver}},$driver if $driver && $driver !~ /vfio/i;
    }
    _clean_dupes(\%devices);

    return \%devices;
}

sub configure($self, $file=undef) {
    my $devices = $self->_load_devices($file);

    if (! -e $self->dst ) {
        make_path($self->dst);
    }
    $self->configure_grub($devices, $FILE_GRUB);
    $self->configure_blacklist($devices, $FILE_BLACKLIST);

    $self->configure_vfio($devices, $FILE_VFIO);
    $self->configure_modules($devices, $FILE_MODULES);

    $self->configure_msrs($devices, $FILE_KVM);
    $self->configure_initramfs($devices, $FILE_INITRAMFS);
}

1;
