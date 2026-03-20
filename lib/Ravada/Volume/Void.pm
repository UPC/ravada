package Ravada::Volume::Void;

use Data::Dumper;
use Moose;
use YAML qw(Load Dump);

extends 'Ravada::Volume';
with 'Ravada::Volume::Class';

no warnings "experimental::signatures";
use feature qw(signatures);

our $QEMU_IMG = "/usr/bin/qemu-img";

sub prepare_base($self, $uid=undef) {
    my $base_file = $self->base_filename();

    my $data = $self->_load();
    $data->{is_base} = 1;
    $data->{origin} = $self->file;

    my $backing_file = $data->{backing_file};
    if ($backing_file) {
        my $data2 = Load($self->vm->read_file($self->file));
        for (keys %$data2) {
            $data->{$_} = $data2->{$_} if !exists $data->{$_};
        }
    }

    $self->vm->write_file($base_file, Dump($data));

    return $base_file;
}

sub capacity($self) {
    my $info = {};
    eval { $info = $self->_load(); };
    warn $@ if $@;
    confess "Unknown capacity for ".$self->file.Dumper($info)
        if !exists $info->{capacity};

    return $info->{capacity};
}

sub _load($self) {
    return Load($self->vm->read_file($self->file));
}

sub _save($self, $data, $file = $self->file) {
    $self->vm->write_file($file, Dump($data));
}

sub clone($self, $clone_file) {
    confess "Warning: volume ".$self->file." is not a base" if !$self->is_base;
    my $data = {
        backing_file => $self->file
        ,capacity => $self->capacity
    };
    my $data2 = Load($self->vm->read_file($self->file));
    for (keys %$data2) {
        next if /^(origin|capacity|is_base)$/;
        $data->{$_} = $data2->{$_} if !exists $data->{$_};
    }

    confess if $clone_file =~ /\.iso$/;
    $self->vm->write_file($clone_file, Dump($data));
    return $clone_file;
}

sub backing_file($self) {
    my $data = $self->_load();
    return ( $data->{backing_file} or undef);
}

sub rebase($self, $file) {
    my $data = $self->_load();
    $data->{backing_file} = $file;
    $self->_save($data);
}

sub spinoff($self) {
    my $data = $self->_load();
    confess "Error: no backing file ".Dumper($self->file,$data)
        if !$self->backing_file;
    my $data_bf = Load($self->vm->read_file($self->backing_file));
    for my $key (keys %$data_bf) {
        next if $key =~ /^(origin|capacity|is_base)$/;
        $data->{$key} = $data_bf->{$key} unless exists $data->{$key};
    }
    delete $data->{backing_file};
    $self->_save($data);
}

sub block_commit($self) {
    my $data = $self->_load();
    confess "Error: no backing file ".Dumper($self->file,$data)
        if !$self->backing_file;
    my $data_bf = Load($self->vm->read_file($self->backing_file));
    for my $key (keys %$data) {
        next if $key =~ /^(origin|capacity|is_base|backing_file)$/;
        $data_bf->{$key} = $data->{$key};
    }
    $self->_save($data_bf, $self->backing_file);

}

sub compact($self, $keep_backup) {
    $self->backup() if $keep_backup;

    return $self->info->{target}." 100% compacted. ";
}
1;
