package Ravada::Volume;

use warnings;
use strict;

=head1 NAME

Ravada::Volume - Volume management library

=cut

use Carp qw(carp confess croak cluck);
use Data::Dumper;
use File::Copy;
use Hash::Util qw(lock_hash unlock_hash);
use JSON::XS;
use Moose;

use Ravada::Volume::ISO;
use Ravada::Volume::Void;
use Ravada::Volume::RAW;
use Ravada::Volume::QCOW2;

no warnings "experimental::signatures";
use feature qw(signatures);

has 'file' => (
    isa => 'Any'
    ,is => 'ro'
    ,required => 0
);

has 'vm' => (
    does => 'Ravada::VM'
    ,is => 'rw'
    ,required => 0
);

has 'domain' => (
    isa => 'Object'
    ,is => 'rw'
    ,required => 0
);

has 'is_base' => (
    isa => 'Int'
    ,is => 'ro'
    ,required => 0
    ,default => sub { 0 }
);

has 'info' => (
    isa => 'HashRef'
    ,is => 'ro'
    ,required => 0
);

has 'name' => (
    isa => 'Str'
    ,is => 'ro'
    ,required => 0
    ,lazy => 1
    ,builder => '_get_name'
);

# after prepare base the original file is cloned so it gets empty
has 'clone_original' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => sub { 1 }
);

sub _type ($file) {
    my ($ext) = $file =~ m{.*\.(.*)};
    confess if $ext =~ /-/;
    my %type = (
        void => 'Void'
        ,img => 'QCOW2'
    );

    return $type{$ext} if exists $type{$ext};
    return uc($ext);
}

sub BUILD($self, $arg) {
    my $class;
    if (exists $arg->{file} && $arg->{file}) {
        $class = "Ravada::Volume::"._type($arg->{file});
    } elsif (exists $arg->{info}) {
        if (exists $arg->{info}->{device} && $arg->{info}->{device} eq 'cdrom') {
            $class = "Ravada::Volume::ISO";
        } else {
            confess "I can't guess class from ".Dumper($arg);
        }
    } else {
        confess "Error: either provide file or info";
    }
    eval { $class->meta->rebless_instance($self) };
    confess $@ if $@;
    $self->vm($self->domain->_vm) if !$arg->{vm} && $self->domain;

    if ($arg->{info} && keys %{$arg->{info}}) {
        $self->set_info(capacity => $self->capacity)
        if ! exists $arg->{info}->{capacity} 
            && $arg->{file}
            && $self->vm
            && $self->vm->file_exists($arg->{file})
            ;
        $self->_cache_volume_info() if $arg->{domain};
    } else {
        $arg->{info} = $self->_get_cached_info();
    }
}

sub _get_name($self) {
    return $self->info->{name} if $self->info && exists $self->info->{name};

    my ($name) = $self->file =~ m{.*/(.*)};
    return $name if $name;

    return $self->file if $self->file;

    confess "Error: I can't get a name for volume ".Dumper($self);
}

sub type($self) {
    return $self->info->{type};
}

sub base_filename($self) {

    my $ext = $self->base_extension();
    my $base_img = $self->file;

    confess "Error: Undefined VM" if !defined $self->vm;

    my $dir_base = $self->vm->dir_base($self->capacity);

    $base_img =~ s{(.*)/(.*)\.\w+$}{$dir_base/$2\.ro.$ext};

    confess "Error: base and original file are the same"
        if $base_img eq $self->file;

    return $base_img;

}

sub clone_filename($self, $name = undef) {
    my $file_base = $self->file;

    my ($dir,$base_name,$ext) = $file_base =~ m{(.*)/(.*)\.ro\.(.*)};
    confess "Error: $file_base doesn't look like a base" if !$base_name;

    $base_name =~ s/(.*)\.(SWAP)$/$1/;
    $ext = "SWAP.$ext" if $2 eq 'SWAP';

    $name = $base_name."-".Ravada::Utils::random_name(4) if !$name;

    my $new_name = "$name.$ext";

    return $self->vm->dir_clone()."/".$new_name;
}

sub restore ($self) {
    my $base = Ravada::Volume->new(
              vm => $self->vm
           ,file => $self->backing_file
        ,is_base => 1
    );
    $base->clone(
        file => $self->file
    );
}

sub base_extension($self) {
    my ($ext) = ref($self) =~ /.*::(\w+)/;
    return lc($ext);
}

sub set_info($self, $name, $value) {
    $self->{info}->{$name} = $value;
    $self->_cache_volume_info() if $self->domain();
}

sub _dbh($self) {
    return $self->domain->_dbh if $self->domain;
    return $self->vm->_dbh if $self->vm;
    confess "No domain nor vm";

}

sub _get_cached_info($self) {
    return if !$self->domain;
    my $sth = $self->_dbh->prepare(
        "SELECT * from volumes "
        ." WHERE name=? "
        ."   AND id_domain=? "
        ." ORDER by n_order"
    );
    $sth->execute($self->name, $self->domain->id);
    my $row = $sth->fetchrow_hashref();

    return if !$row || !keys %$row;
    if ( $row->{info} ) {
        $row->{info} = decode_json($row->{info})
    }
    return $row;
}

sub _cache_volume_info($self) {
    my $info = $self->info();
    confess if !defined $info;
    confess if !defined $self->domain;
    my %info = %{$info};
    my $name = $self->name or confess "No volume name";
    my $row = $self->_get_cached_info();
    if (!$row) {
        my $file = (delete $info{file} or '');
        confess "Error: Missing n_order field ".Dumper(\%info) if !exists $info{n_order};
        my $n_order = delete $info{n_order};

        eval {
        my $sth = $self->domain->_dbh->prepare(
            "INSERT INTO volumes (id_domain, name, file, n_order, info) "
            ."VALUES(?,?,?,?,?)"
        );
        $sth->execute($self->domain->id
            ,$name
            ,$file
            ,$n_order
            ,encode_json(\%info));
        };
        confess "$name / $n_order \n".$@ if $@;
        return;
    }
    for (keys %{$row->{info}}) {
        $info{$_} = $row->{info}->{$_} if !exists $info{$_};
    }
    my $file = (delete $info{file} or $row->{file});
    my $n_order = (delete $info{n_order} or $row->{n_order});
    warn "Error: Missing file field ".Dumper(\%info, $row)
        if !defined $file || !length($file);
    my $sth = $self->domain->_dbh->prepare(
        "UPDATE volumes set info=?, name=?,file=?,id_domain=?,n_order=? WHERE id=?"
    );
    $sth->execute(encode_json(\%info), $name, $file, $self->domain->id, $n_order, $row->{id});
}

1;
