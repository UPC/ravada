package Ravada::Volume::Void;

use Data::Dumper;
use Moose;
use YAML qw(Load Dump);

extends 'Ravada::Volume';
with 'Ravada::Volume::Class';

no warnings "experimental::signatures";
use feature qw(signatures);

our $QEMU_IMG = "/usr/bin/qemu-img";

sub prepare_base($self) {
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
    my $info = $self->_load();
    confess "Unknown capacity for ".$self->file.Dumper($info)
        if !exists $info->{capacity};

    return $info->{capacity};
}

sub _load($self) {
    return Load($self->vm->read_file($self->file));
}

sub _save($self, $data) {
    $self->vm->write_file($self->file, Dump($data));
}

sub clone($self, $clone_file) {
    confess "Error: volume is not a base" if !$self->is_base;
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
    my $backing_file = $data->{backing_file}
        or confess "Error: No backing file from ".Dumper($data);
}

sub rebase($self, $file) {
    my $data = $self->_load();
    $data->{backing_file} = $file;
    $self->_save($data);
}

1;
