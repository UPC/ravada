package Ravada::Volume::QCOW2;

use Data::Dumper;
use Hash::Util qw(lock_hash);
use Moose;

extends 'Ravada::Volume';
with 'Ravada::Volume::Class';

no warnings "experimental::signatures";
use feature qw(signatures);

has 'capacity' => (
    isa => 'Int'
    ,is => 'ro'
    ,lazy => 1
    ,builder => '_get_capacity'
);

our $QEMU_IMG = "qemu-img";

sub prepare_base($self) {
    my $format;
    eval {
        $format = $self->_qemu_info('file format')
    };
    confess $@ if $@;

    my $base_img = $self->base_filename();

    confess "Error: '$base_img' already exists" if -e $base_img;

    if ($format && $format eq 'qcow2') {
        $self->_copy($base_img, '0400');
    } else {
        $self->_convert($base_img);
    }

    return $base_img;

}

sub _convert($self, $dst) {
    my $file_img = $self->file;
    my $base_img = $self->base_filename();
    my @cmd = _cmd_convert($file_img,$base_img);
    my ($out, $err) = $self->vm->run_command( @cmd );
    warn $out  if $out;
    confess "$?: $err"   if $err;

    if (! $self->vm->file_exists($base_img)) {
        chomp $err;
        chomp $out;
        die "ERROR: Output file $base_img from node ".$self->vm->name." not created at "
        ."\n"
        ."ERROR: '".($err or '')."'\n"
        ."  OUT: '".($out or '')."'\n"
        ."\n"
        .join(" ",@cmd);
    }

}

sub _copy($self, $dst, $mode=undef) {
    my $src = $self->file;

    if (!$self->vm || $self->vm->type ne 'KVM') {
        return $self->_copy_sys($dst,$mode);
    }
    my $vol = $self->vm->search_volume($src);

    confess "Error: '$src' not found in ".$self->vm->name." [ ".$self->vm->type." ]" if !$vol;
    my $vol_capacity = $vol->get_info()->{capacity};
    #my $sp = $self->vm->vm->get_storage_pool_by_volume($vol);
    my ($path) = $dst =~ m{(.*)/};
    my $sp = $self->vm->vm->get_storage_pool_by_target_path($path);
    if (!$sp) {
        warn "Warning: pool not found in $path, reverting to ".$vol->get_path;
        $sp = $self->vm->vm->get_storage_pool_by_volume($vol);
    }

    _refresh_sp($self->vm,$sp);
    my $pool_capacity = $sp->get_info()->{capacity};

    die "Error: '$dst' too big to fit in ".$sp->get_name.". ".Ravada::Utils::number_to_size($vol_capacity)." > ".Ravada::Utils::number_to_size($pool_capacity)."\n"
    if $vol_capacity>$pool_capacity;

    my $xml = $vol->get_xml_description();
    my $doc = XML::LibXML->load_xml(string => $xml);

    my ($name) = $dst =~ m{.*/(.*)};

    $doc->findnodes('/volume/name/text()')->[0]->setData($name);
    $doc->findnodes('/volume/key/text()')->[0]->setData($dst);
    $doc->findnodes('/volume/target/path/text()')->[0]->setData( $dst);
    $doc->findnodes('/volume/target/permissions/mode/text()')->[0]
        ->setData( $mode ) if $mode;

    my $vol_dst;
    my $err;
    for ( 1 .. 5 ) {
        eval {
            $vol_dst = $sp->clone_volume($doc->toString, $vol);
        };
        $err = $@;
        last if !$err
            || (ref($err) eq 'Sys::Virt::Error'
                && $err->code == 1) ; #internal error: pool 'default' has asynchronous jobs running
        sleep 1;
    }
    die $err if $err;

    _refresh_sp($self->vm,$vol_dst);

    return $vol_dst;
}

sub _copy_sys($self, $dst, $mode=undef) {
    my $file = $self->file;
    if ($self->vm) {
        my ($out, $err) = $self->vm->run_command("cp",$file,$dst);
    } else {
        copy($file,$dst);
    }
    $self->_chmod($mode) if $mode;
}

sub clone($self, $file_clone) {
    my $n = 10;
    for (;;) {
        my @stat = stat($self->file);
        last if time-$stat[9] || $n--<0;
        sleep 1;
        die "Error: ".$self->file." looks active" if $n-- <0;
    }
    confess if $self->file =~ /ISO$/i;
    confess if $file_clone =~ /ISO$/i;

    my $base_format = lc(Ravada::Volume::_type_from_file($self->file, $self->vm));
    my ($out, $err);
    for ( 1 .. 3 ) {
        my @cmd = ($QEMU_IMG,'create'
            ,'-F',$base_format
            ,'-f','qcow2'
            ,"-b", $self->file
            ,$file_clone
        );
        ($out, $err) = $self->vm->run_command(@cmd);
        last if !$err || $err !~ /Failed to get .*lock/;
        sleep 1;
    }
    confess $self->vm->name." ".$err if $err;

    my $vol;
    for ( 1 .. 3 ) {
        $vol = $self->vm->search_volume($file_clone);
        last if $vol;
    }
    if ($vol) {
        _refresh_sp($self->vm, $vol);
    } else {
        $self->vm->refresh_storage();
    }

    return $file_clone;
}

sub _refresh_sp($vm, $vol) {
    my $sp;
    if (ref($vol) eq 'Sys::Virt::StoragePool') {
        $sp = $vol;
    } else {
        $sp = $vm->vm->get_storage_pool_by_volume($vol);
    }
    for ( 1 .. 3 ) {
        eval { $sp->refresh() };
        my $err = $@;
        last if !$err;
        warn $err;
        sleep 1;
    }

}

sub _get_capacity($self) {
    my $size = $self->_qemu_info('virtual size');
    my ($capacity) = $size =~ /\((\d+) /;
    return $capacity;
}

sub _cmd_convert($base_img, $qcow_img) {

    return    ($QEMU_IMG,'convert',
                '-O','qcow2', $base_img
                ,$qcow_img
        );

}

sub _cmd_copy {
    my ($base_img, $qcow_img) = @_;

    return ('/bin/cp'
            ,$base_img, $qcow_img
    );
}

sub backing_file($self) {
    return $self->_qemu_info('backing file');
}

sub rebase($self, $new_base) {

    my $base_format = lc(Ravada::Volume::_type_from_file($new_base, $self->vm));
    my @cmd = ($QEMU_IMG,'rebase'
        ,'-f','qcow2'
        ,'-F',$base_format
        ,'-b',$new_base,$self->file);
    my ($out, $err) = $self->vm->run_command(@cmd);
    confess $err if $err && $err !~ /Failed to get write lock/;
    warn "Warning: $err" if $err;

}

sub spinoff($self) {
    my $file = $self->file;
    my $volume_tmp  = $self->file.".$$.tmp";

    $self->vm->remove_file($volume_tmp);

    my @cmd = ($QEMU_IMG
        ,'convert'
        ,'-O','qcow2'
        ,$file
        ,$volume_tmp
    );
    my ($out, $err) = $self->vm->run_command(@cmd);
    warn $out  if $out;
    warn $err   if $err;
    confess "ERROR: Temporary output file $volume_tmp not created at "
    .join(" ",@cmd)
    .($out or '')
    .($err or '')
    ."\n"
    if (! $self->vm->file_exists($volume_tmp) );

    $self->copy_file($volume_tmp,$file) or die "$! $volume_tmp -> $file";
    $self->vm->refresh_storage_pools();
    $self->vm->remove_file($volume_tmp);
}

sub block_commit($self) {
    my @cmd = ($QEMU_IMG,'commit','-q','-d');
    my ($out, $err) = $self->vm->run_command(@cmd, $self->file);
    warn $err   if $err;
}

sub _qemu_info($self, $field=undef) {
    if ( exists $self->{_qemu_info} ) {
        return $self->{_qemu_info} if !defined $field;
        confess "Unknown field $field ".Dumper($self->{_qemu_info})
            if !exists $self->{_qemu_info}->{$field};

        return $self->{_qemu_info}->{$field};
    }

    if  ( ! $self->vm->file_exists($self->file) ) {
        return if defined $field;
        return {};
    }
    my @cmd = ( $QEMU_IMG,'info',$self->file,'-U');

    my ($out, $err) = $self->vm->run_command(@cmd);
    confess $err if $err;

    my %info = (
        'backing file'=> undef
        ,'backing file format' => ''
    );
    for my $line (split /\n/, $out) {
        last if $line =~ /^Format/;
        my ($field, $value) = $line =~ /(.*?):\s*(.*)/;
        $info{$field} = $value;
    }
    lock_hash(%info);
    $self->{_qemu_info} = \%info;

    return $info{$field};
}

sub compact($self, $keep_backup=1) {
    my $vol_backup = $self->backup();

    my @cmd = ( "virt-sparsify"
        , "--in-place"
        , $self->file
    );
    my ($out, $err) = $self->vm->run_command(@cmd);
    die "Error: I can't sparsify ".$self->file." , backup file stored on $vol_backup : $err"
    if $err;

    @cmd = ("qemu-img", "check", $self->file);
    ($out, $err) = $self->vm->run_command(@cmd);
    die "Error: problem checking ".$self->file." after virt-sparsify $err" if $err;

    my ($du_backup, $du_backup_err) = $self->vm->run_command("du","-m",$vol_backup);
    my ($du, $du_err) = $self->vm->run_command("du","-m",$self->file);
    chomp $du_backup;
    $du_backup =~ s/(^\d+).*/$1/;
    chomp $du;
    $du =~ s/(^\d+).*/$1/;

    unlink $vol_backup or die "$! $vol_backup"
    if !$keep_backup;

    return int(100*($du_backup-$du)/$du_backup)." % compacted. ";
}

1;
