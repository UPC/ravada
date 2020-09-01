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

our $QEMU_IMG = "/usr/bin/qemu-img";

sub prepare_base($self) {

    my $file_img = $self->file;
    my $base_img = $self->base_filename();
    confess $base_img if $base_img !~ /\.ro/;

    confess "Error: '$base_img' already exists" if -e $base_img;

    my @cmd = _cmd_convert($file_img,$base_img);

    my $format;
    eval {
        $format = $self->_qemu_info('file format')
    };
    confess $@ if $@;
    @cmd = _cmd_copy($file_img, $base_img)
    if $format && $format eq 'qcow2' && !$self->backing_file;

    my ($out, $err) = $self->vm->run_command( @cmd );
    warn $out  if $out;
    confess "$?: $err"   if $err;

    if (! $self->vm->file_exists($base_img)) {
        chomp $err;
        chomp $out;
        die "ERROR: Output file $base_img not created at "
        ."\n"
        ."ERROR: '".($err or '')."'\n"
        ."  OUT: '".($out or '')."'\n"
        ."\n"
        .join(" ",@cmd);
    }

    chmod 0555,$base_img;

    return $base_img;

}

sub clone($self, $file_clone) {
    my $n = 10;
    for (;;) {
        my @stat = stat($self->file);
        last if time-$stat[9] || $n--<0;
        sleep 1;
        die "Error: ".$self->file." looks active" if $n-- <0;
    }
    my @cmd = ($QEMU_IMG,'create'
        ,'-F','qcow2'
        ,'-f','qcow2'
        ,'-F','qcow2'
        ,"-b", $self->file
        ,$file_clone
    );
    my ($out, $err) = $self->vm->run_command(@cmd);
    confess $self->vm->name." ".$err if $err;

    return $file_clone;
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
    my @cmd = ($QEMU_IMG,'rebase'
        ,'-f','qcow2'
        ,'-F','qcow2'
        ,'-b',$new_base,$self->file);
    my ($out, $err) = $self->vm->run_command(@cmd);
    confess $err if $err;

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
    $self->vm->remove_file($volume_tmp) or die "ERROR $! removing $volume_tmp";
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

    return {} if ! $self->vm->file_exists($self->file);
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

1;
