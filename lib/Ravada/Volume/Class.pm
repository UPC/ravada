package Ravada::Volume::Class;

use Data::Dumper qw(Dumper);
use File::Copy;
use Moose::Role;

no warnings "experimental::signatures";
use feature qw(signatures);

requires 'clone';
requires 'backing_file';
requires 'prepare_base';
requires 'spinoff';

around 'prepare_base' => \&_around_prepare_base;
around 'clone' => \&_around_clone;

sub _around_prepare_base($orig, $self) {
    confess "Error: unknown VM " if !defined $self->vm;

    confess "Error: missing file ".$self->domain->name if !$self->file;
    confess if !$self->capacity;

    my $storage_pool = ($self->vm->base_storage_pool or $self->vm->default_storage_pool_name);
    $self->vm->_check_free_disk($self->capacity, $storage_pool);

    my $base_file = $orig->($self);
    confess "No base file returned by ".ref($self)."->prepare_base" if !$base_file;

    $self->_chmod(oct(400),$base_file);

    return $base_file if ! $self->clone_base_after_prepare;

    $self->vm->refresh_storage_pools();
    $self->vm->remove_file($self->file);

    my @domain = ();
    @domain = ( domain => $self->domain) if $self->domain;
    @domain = ( vm => $self->vm ) if !$self->domain && $self->vm;
    my $base = Ravada::Volume->new(
        file => $base_file
        ,is_base => 1
        ,@domain
    );
    $base->clone(file => $self->file);

    return $base_file;
}

sub _chmod($self, $mode, $file=$self->file) {

    my $vm;

    if ($vm && !$vm->is_local) {
        my ($out,$err) = $vm->run_command("chmod",$mode,$file);
        die $err if $err;
    } else {
        chmod $mode,$file or die "$! chmod $mode $file";
    }
}


sub _domain_file($self, $file) {
    my $sth = $self->_dbh->prepare("SELECT id_domain FROM volumes WHERE file=? "
    ." OR name=?");
    $sth->execute($file,$file);
    my ($id_domain) = $sth->fetchrow;
    return $id_domain;
}

sub _new_clone_filename($self,$name0) {
    my $extra='';
    my $clone_filename = $self->clone_filename($name0);
    return $clone_filename if $clone_filename =~ /\.iso$/;
    for (1 .. 10) {
        return $clone_filename if !$self->_domain_file($clone_filename);
        $clone_filename = $self->clone_filename($name0."-"
        .Ravada::Utils::random_name());
    }
    die "Error: I can't produce a random filename";
}

sub _around_clone($orig, $self, %args) {
    my $name = delete $args{name};
    my $file_clone = ( delete $args{file} or $self->_new_clone_filename($name));

    confess "Error: unkonwn args ".Dumper(\%args) if keys %args;
    confess "Error: empty clone filename" if !defined $file_clone || !length($file_clone);

    my $id_domain_file= $self->_domain_file($file_clone);
    if ($id_domain_file && $file_clone !~ /\.iso$/) {
        my $we = '';
        $we = "We are domain id: ".($self->domain->id)." [ ".$self->domain->name." ]"
        if $self->domain;

        confess "Error: file $file_clone already exists in domain $id_domain_file.$we"
        if !$self->domain || $self->domain->id != $id_domain_file;
    }

    my $ret = $self->new(
        file => $orig->($self, $file_clone)
        ,vm => $self->vm
    );
    $self->_chmod(oct(600), $file_clone);

    return $ret;
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

sub backup($self) {
    my $vol_backup = $self->file.".".time.".backup";
    my ($out, $err) = $self->vm->run_command("cp","--preserve=all",$self->file,$vol_backup);
        if ($err) {
        $self->vm->remove_file($vol_backup);
        die "Error: I can't backup $vol_backup $err";
    }
    return $vol_backup;
}

1;
