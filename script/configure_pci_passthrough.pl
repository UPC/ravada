#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Getopt::Long;
use File::Copy qw(copy);
use File::Path qw(make_path);
use IPC::Run3 qw(run3);

no warnings "experimental::signatures";
use feature qw(signatures);

my $TEST = $<;

GetOptions( test => \$TEST ) or die $!;

my $DEFAULT_GRUB = "/etc/default/grub";

my $FILE_BLACKLIST = "/etc/modprobe.d/rvd-blacklist.conf";
my $FILE_SOFTDEP = "/etc/modprobe.d/rvd-softdep.conf";
my $FILE_VFIO = "/etc/modprobe.d/rvd-vfio.conf";
my $FILE_KVM = "/etc/modprobe.d/rvd-kvm.conf";
my $FILE_INITRAMFS = "/etc/initramfs-tools/modules";

sub search_devices($re) {

    my @cmd = ("lspci","-D","-knn");
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);

    my $found;
    my @devices;
    my @pci;
    my %drivers;
    for my $line (split /\n/,$out) {
	$found = 0 if $line =~ m{^[0-9a-f]};
	next if !$found && $line !~ qr($re);
	my ($pci_data) = $line =~ m{^([0-9a-f]{4}.*?) };
	push @pci,($pci_data) if $pci_data;
	my ($device) = $line =~ m{\[([0-9a-f]{4}\:[0-9a-f]{4})\]};
	push @devices,($device) if $device;
	my ($driver) = $line =~ /\s+Kernel (?:driver|modules).*: ([a-zA-Z0-9_]+)/;
	$drivers{$driver}++ if $driver;
	$found=1;
    }
    return(\@pci,\@devices,[keys %drivers]);
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

sub filename_backup($file) {
    my $file_backup = "";
    $file_backup = "/tmp" if $TEST;
    $file_backup = "$file_backup$file.".now();

    return _create($file_backup);
}

sub filename_new($file) {
    my $file_new= "";
    $file_new= "/tmp" if $TEST;
    $file_new = "$file_new$file.new";

    return _create($file_new);

}

sub _create($file) {
    my ($path) = $file =~ m{(.*)/};
    make_path($path) if !-e $path;
    return $file;
}

sub cpu_vendor() {
    my @cmd = ("lscpu");
    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    die $err if $err;
    my ($vendor) = $out =~ m{^Vendor ID:\s+(.*)}m;
    return 'intel' 	if $vendor =~ /intel$/i;
    return 'amd'	if $vendor =~ /amd$/i;
    die "Error: unknown cpu vendor $vendor\n$out";
}

sub _add_cpu_iommu_grub($entries) {
    if (cpu_vendor() eq 'intel') {
	$entries->{"intel_iommu=on"}++;
    } elsif (cpu_vendor() eq 'amd') {
	$entries->{"amd_iommu=on"}++;
	$entries->{"iommu=pt"}++;
	$entries->{"kvm_amd.npt=1"}++;
	$entries->{"kvm_amd.avic=1"}++;
    } else {
	die "Error: I don't know cpu vendor ".cpu_vendor();
    }
}

sub _equal($hash1, $hash2) {
    return 0 if scalar(keys %$hash1) != scalar(keys %$hash2);

    my $keys1 = join(" ",sort keys %$hash1);
    my $keys2 = join(" ",sort keys %$hash2);

    return $keys1 eq $keys2;
}

sub _blacklist_grub($current, $drivers) {
    my %entries = map { $_ => 1 } split /\s+/, $current;
    my %entries2 = %entries;
    for my $driver(@$drivers) {
	$entries2{"$driver.blacklist=1"}++;
    }
    _add_cpu_iommu_grub(\%entries2);
    return $current if _equal(\%entries, \%entries2);
    return join(" ",sort keys %entries2);
}

sub _pci_stub($current, $devices) {
    my %entries = map { $_ => 1 } split /\s+/, $current;
    my %entries2 = %entries;

    my %devices2 = map { $_ => 1} @$devices;

    my $pci_stub;
    for my $key (keys %entries2) {
	if ($key =~ /^pci-stub.ids=(.*)/) {
	    my $ids = $1;
	    for my $id (split/,/,$ids) {
		$devices2{$id}++;
	    }
	}
    }
    $entries2{"pci-stub.ids=".join(",",sort keys %devices2)}++;;
    return $current if _equal(\%entries, \%entries2);
    return join(" ",sort keys %entries2);

}

sub configure_grub($drivers, $devices) {
    my $default_grub_backup = filename_backup($DEFAULT_GRUB);;
    open my $in,"<",$DEFAULT_GRUB or die "$! $DEFAULT_GRUB";
    open my $backup,">",$default_grub_backup or die "$! $default_grub_backup";
    open my $new,">",filename_new($DEFAULT_GRUB) or die "$!";

    my $changed = 0;
    while (my $line = <$in>) {
	chomp $line;
	print $backup "$line\n";
	if ($line =~ /^(GRUB_CMDLINE_LINUX_DEFAULT)="(.*)"/) {
	    my $var = $1;
	    my $grub_value = $2;
	    my $grub_value_orig = $grub_value;
	    $grub_value = _blacklist_grub($grub_value, $drivers);
	    $grub_value = _pci_stub($grub_value, $devices);
	    print $new "$var=\"$grub_value\"\n";
	    $changed++ if $grub_value_orig ne $grub_value;
	} else {
	    print $new "$line\n";
	}
    }
    close $in;
    close $backup or die $!;
    close $new;

    if (!$changed) {
	print "Nothing changed to $DEFAULT_GRUB\n";
	unlink $default_grub_backup or die "$! $default_grub_backup";
	unlink filename_new($DEFAULT_GRUB);
    } else {
	copy(filename_new($DEFAULT_GRUB), $DEFAULT_GRUB) if !$<;
	print $DEFAULT_GRUB." changed.\n";
    }
    return $changed;
}

sub backup_file($file) {
    my $file_backup = filename_backup($file);
    copy($file, $file_backup) or die "$! $file -> $file_backup\n";
    return $file_backup;
}

sub blacklist_modules($drivers) {
    my %drivers= map { $_ => 1 } @$drivers;
    my %drivers_old;
    my $in;
    open $in,"<",$FILE_BLACKLIST and do {
	while (<$in>) {
	    chomp;
	    my ($driver) = /^\s*blacklist (.*)/;
	    $drivers_old{$driver}++ if $driver;
	}
	close $in;
    };
    if (_equal(\%drivers, \%drivers_old)) {
	print "Nothing changed to $FILE_BLACKLIST\n";
	return 0;
    }
    if ( -e $FILE_BLACKLIST) {
	backup_file($FILE_BLACKLIST);
    }
    my $file_new = filename_new($FILE_BLACKLIST);

    open my $out,">",$file_new or die "$! $file_new";
    for my $key (sort keys %drivers_old) {
	print $out "blacklist $key\n";
    }
    my $changed=0;
    for my $key (sort keys %drivers) {
	if (!exists $drivers_old{$key} ) {
	    print $out "blacklist $key\n";
	    $changed++;
	}
    }
    close $out;
    if ($changed) {
	copy($file_new, $FILE_BLACKLIST) or die "$! $file_new -> $FILE_BLACKLIST"
	if !$<;
	print "$FILE_BLACKLIST changed\n";
	unlink $file_new;
    }
    return $changed;
}

sub softdep_modules($drivers) {
    my %drivers= map { $_ => 1 } @$drivers;
    $drivers->{'nvidia*'}++ if exists $drivers{'nvidia'};
    my %drivers_old;
    my $in;
    open $in,"<",$FILE_SOFTDEP and do {
	while (<$in>) {
	    chomp;
	    my ($driver) = /^\s*softdep (.*?) pre: vfio-pci/;
	    $drivers_old{$driver}++ if $driver;
	}
	close $in;
    };
    if ( _equal(\%drivers, \%drivers_old) ) {
	print "Nothing changed to $FILE_SOFTDEP\n";
	return 0 
    }

    if ( -e $FILE_SOFTDEP) {
	backup_file($FILE_SOFTDEP);
    }
    my $file_new = filename_new($FILE_SOFTDEP);

    open my $out,">",$file_new or die "$! $file_new";
    for my $key (sort keys %drivers_old) {
	print $out "softdep $key pre: vfio-pci\n";
    }
    my $changed =0;
    for my $key (sort keys %drivers) {
	next if exists $drivers_old{$key};
	$changed++;
	print "$key\n";
	print $out "softdep $key pre: vfio-pci\n";
    }

    close $out;

    return 0 if !$changed;

    print "$FILE_SOFTDEP changed\n";
    print `diff $FILE_SOFTDEP $file_new`;
    exit;
    copy($file_new, $FILE_SOFTDEP) or die "$! $file_new -> $FILE_SOFTDEP"
    if !$<;

    unlink $file_new;

    return 1;
}

sub add_line($file, @lines) {
    my @old;
    my $in;
    open $in,"<",$file and do {
	@old = map { chomp ; $_ } <$in>;
    };

    my $changed = 0;
    for my $line (@lines) {
	next if grep( /^$line$/, @old);
	push @old, ($line);
	$changed++;
    }
    return 0 if !$changed;
    backup_file($file) if -e $file;
    my $file_new = filename_new($file);
    open my $out, ">",$file_new or die "$! $file_new";
    print $out join("\n",@old);
    print $out "\n";
    close $out;

    print "$file changed \n";

    copy($file_new, $file) or die "$! $file_new -> $file\n" if !$<;
    unlink $file_new;

    return 1;
}

sub add_modules_boot($devices) {
    my $line = "vfio vfio_iommu_type1 vfio_pci ids="
    .join(",",sort @$devices);

    return add_line("/etc/modules",$line);
}

sub _add_ids($devices, $value) {
    my %ids_old = map {$_ => 1 } split /,/,$value;
    my %ids =  %ids_old;
    for (@$devices) {
	$ids{$_} = 1;
    }

    return $value if _equal(\%ids_old, \%ids);

    return join(",",keys %ids);
}

sub add_modules_vfio($devices) {

    my $vfio_backup = filename_backup($FILE_VFIO);;

    if (! -e $FILE_VFIO ) {
	open my $out,">",$FILE_VFIO or die "$! $FILE_VFIO";
	close $out;
    }
    open my $in,"<",$FILE_VFIO or die "$! $FILE_VFIO";
    open my $backup,">",$vfio_backup or die "$! $vfio_backup";
    open my $new,">",filename_new($FILE_VFIO) or die "$!";

    my $changed = 0;
    my $found = 0;
    while (my $line = <$in>) {
	chomp $line;
	print $backup "$line\n";
	if ($line =~ /^(options vfio_pci ids)=(.*)/) {
	    $found++;
	    my $var = $1;
	    my $value = $2;
	    my $value_orig = $value;

	    my $ids_old = $value;
	    $ids_old =~ s/\s+.*//;

	    my ($extra) = $value =~ m{(\s+.*)};
	    $extra = '' if !defined $extra;

	    $value = _add_ids($devices, $ids_old).$extra;
	    print $new "$var=$value\n";
	    $changed++ if $value_orig ne $value;
	} else {
	    print $new "$line\n";
	}
    }
    if (!$found) {
	$changed++;
	print $new "options vfio_pci ids=".join(",",sort @$devices)
	    ." disable_vga=1"
	    ."\n";
    }
    close $in;
    close $backup or die $!;
    close $new;

    if (!$changed) {
	print "$FILE_VFIO not changed\n";
	unlink $vfio_backup;
	unlink $new;
    } else {
	print "$FILE_VFIO changed\n";
	copy(filename_new($FILE_VFIO), $FILE_VFIO);
    }

}

sub add_ignore_msrs() {
    return add_line($FILE_KVM,"options kvm ignore_msrs=1");
}

sub add_ids_initramfs($devices) {
    my $line = "vfio vfio_iommu_type1 vfio_virqfd vfio_pci ids="
    .join(",", sort @$devices);

    return add_line($FILE_INITRAMFS, $line);
}

sub update_grub_initramfs() {
    for my $cmd (['update-grub'],['update-initramfs','-u']) {
	my ($in, $out, $err);
	print join(" ",@$cmd)."\n";
	next if $<;
	run3($cmd, \$in, \$out, \$err);
	warn $err if $err;
	print $out if $out;
    }
}

sub reboot() {
    print "Reboot now [y/n] ?";
    my $what = 'n';
    if (!$<) {
	$what =<STDIN>;
    } else {
	$what = 'y';
	print "$what\n";
    };
    if ( $what =~ /^y$/i || $what =~ /^yes$/i) {
	if ($<) {
	    warn "Please re-run as root to reboot\n";
	    return;
	}
	`reboot`;
    }
}

sub select_device() {
    my @cmd = ("lspci","-D");
    my ($in, $out, $err);

    run3(\@cmd, \$in, \$out, \$err);

    my $n = 0;
    my %pci;
    for my $line ( split /\n/, $out ) {
	++$n;
	my ($pci) = $line =~ /^(.*?) /;
	$pci{$n} = $pci;
	print $n." $line\n";
    }

    my $what;
    for ( ;; ) {
    print "Select device number to configure as host device "
    ."( CTRL-C to abort ): ";

	$what =<STDIN>;
	chomp $what;
	last if $what && $what =~ /^\d+$/ && $what >0 && $what <=$n;
	print "Error: invalid selection '$what'\n";
    }
    $what =~ s/^0+//;
    die "Error. I can't find device '$what' in ".Dumper(\%pci)
    if !exists $pci{$what};
    return $pci{$what};
}

###############################################

my $RE = ($ARGV[0] or select_device());
warn "Testing, please re-run as root to perform changes.\n\n" if $<;

print "\n";

my ($pci,$devices, $drivers) = search_devices($RE);
if (!scalar @$devices) {
    print "No devices found for $RE\n";
    exit;
}

my $changed = 0;
$changed += configure_grub($drivers, $devices);
$changed += blacklist_modules($drivers);
$changed += softdep_modules($drivers);
$changed += add_modules_boot($devices);
$changed += add_modules_vfio($devices);
$changed += add_ignore_msrs();
$changed += add_ids_initramfs($devices);
print "\n";
if ( $changed ) {
    update_grub_initramfs();
    reboot();
}
