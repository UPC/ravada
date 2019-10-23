package Ravada::Volume::Class;

use Data::Dumper qw(Dumper);
use File::Copy;
use Moose::Role;

no warnings "experimental::signatures";
use feature qw(signatures);

requires 'clone';
requires 'backing_file';
requires 'prepare_base';

around 'prepare_base' => \&_around_prepare_base;
around 'clone' => \&_around_clone;

sub _around_prepare_base($orig, $self) {
    confess "Error: unknown VM " if !defined $self->vm;

    confess if !$self->capacity;

    my $storage_pool = ($self->vm->base_storage_pool or $self->vm->default_storage_pool_name);
    $self->vm->_check_free_disk($self->capacity, $storage_pool);
    my $base_file = $orig->($self);
    confess if !$base_file;

    return $base_file if ! $self->clone_base_after_prepare;

    $self->vm->remove_file($self->file);

    my $base = Ravada::Volume->new(
        file => $base_file
        ,is_base => 1
        ,vm => $self->vm
    );
    $base->clone(file => $self->file);

    return $base_file;
}

sub _around_clone($orig, $self, %args) {
    my $name = delete $args{name};
    my $file_clone = ( delete $args{file} or $self->clone_filename($name));

    confess "Error: unkonwn args ".Dumper(\%args) if keys %args;
    confess "Error: empty clone filename" if !defined $file_clone || !length($file_clone);

    return Ravada::Volume->new(
        file => $orig->($self, $file_clone)
        ,vm => $self->vm
    );
}

sub copy_file($self, $src, $dst) {
    if ($self->vm->is_local) {
        File::Copy::copy($src,$dst) or die "$! $src -> $dst";
        return $dst;
    }
    my @cmd = ('/bin/cp' ,$src, $dst );
    my ($out, $err) = $self->vm->run_command(@cmd);
    die $err if $err;
}

1;
