package Ravada::Domain::Void;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use YAML qw(LoadFile DumpFile);

with 'Ravada::Domain';

has 'domain' => (
    is => 'ro'
    ,isa => 'Str'
    ,required => 1
);

our $DIR_TMP = "/var/tmp/rvd_void";

#######################################3

sub BUILD {
    my $self = shift;

    my $args = $_[0];
    
    mkdir $DIR_TMP or die "$! when mkdir $DIR_TMP"
        if ! -e $DIR_TMP;

    $self->add_volume(name => 'void-diska' , size => 1, path => "$DIR_TMP/".$self->name.".img")
        if !$args->{id_base};
}

sub name { 
    my $self = shift;
    return $self->domain;
};

sub display {
    my $self = shift;

    my $ip = $self->_vm->ip();
    return "void://$ip:0000/";
}

sub is_active {
    my $self = shift;

    return $self->_value('is_active');
}

sub pause {
    my $self = shift;
    $self->_store(is_paused => 1);
}

sub resume {
    my $self = shift;
    return $self->_store(is_paused => 0 );
}

sub remove {
    my $self = shift;

    $self->remove_disks();
}

sub is_paused {
    my $self = shift;

    return $self->_value('is_paused');
}

sub _store {
    my $self = shift;

    my ($var, $value) = @_;

    my $data = {};

    my ($disk) = $self->disk_device();
    $data = LoadFile($disk)   if -e $disk;

    $data->{$var} = $value;

    DumpFile($disk, $data);

}

sub _value{
    my $self = shift;

    my ($var) = @_;

    my ($disk) = $self->disk_device();

    my $data = {} ;
    $data = LoadFile($disk) if -e $disk;
    
    return $data->{$var};

}


sub shutdown {
    my $self = shift;
    $self->_store(is_active => 0);
}

sub shutdown_now {
    my $self = shift;
    my $user = shift;
    return $self->shutdown(user => $user);
}

sub start {
    my $self = shift;
    $self->_store(is_active => 1);
}

sub prepare_base {
    my $self = shift;

    for my $file_qcow ($self->list_volumes) {;
        $file_qcow .= ".qcow";

        open my $out,'>',$file_qcow or die "$! $file_qcow";
        print $out "$file_qcow\n";
        close $out;
        $self->_prepare_base_db($file_qcow);
    }
}

sub disk_device {
    my $self = shift;
    return "$DIR_TMP/".$self->name.".img";
}

sub list_disks {
    return disk_device(@_);
}

sub _vol_remove {
    my $self = shift;
    my $file = shift;
    unlink $file or die "$! $file"
        if -e $file;
}

sub remove_disks {
    my $self = shift;
    my @files = $self->list_disks;
    for my $file (@files) {
        next if ! -e $file;
        $self->_vol_remove($file);
        if ( -e $file ) {
            unlink $file or die "$! $file";
        }
    }

}

=head2 add_volume

Adds a new volume to the domain

    $domain->add_volume($size);

=cut

sub add_volume {
    my $self = shift;
    my %args = @_;

    $args{path} = "$DIR_TMP/".$self->name.".$args{name}.img"
        if !$args{path};

    confess "Volume path must be absolute , it is '$args{path}'"
        if $args{path} !~ m{^/};

    return if -e $args{path};

    my %valid_arg = map { $_ => 1 } ( qw( name size path vm));

    for my $arg_name (keys %args) {
        confess "Unknown arg $arg_name"
            if !$valid_arg{$arg_name};
    }
    confess "Missing name " if !$args{name};
#    TODO
#    confess "Missing size " if !$args{size};

    my $data = { };
    $data = LoadFile($self->disk_device) if -e $self->disk_device;

    $data->{device}->{$args{name}} = \%args;
    DumpFile($self->disk_device, $data);

    open my $out,'>>',$args{path} or die "$! $args{path}";
    print $out "";
    close $out;

}

sub list_volumes {
    my $self = shift;
    my $data = LoadFile($self->disk_device) if -e $self->disk_device;

    return () if !exists $data->{device};
    my @vol;
    for my $dev (keys %{$data->{device}}) {
        push @vol,($data->{device}->{$dev}->{path});
    }
    return @vol;
}

sub screenshot {}

1;
