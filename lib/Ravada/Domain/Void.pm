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

our $TMP_DIR = "/var/tmp/rvd_void";

#######################################3

sub BUILD {
    my $self = shift;
    
    mkdir $TMP_DIR or die "$! when mkdir $TMP_DIR"
        if ! -e $TMP_DIR;

    $self->_store(name => $self->name);
}

sub name { 
    my $self = shift;
    return $self->domain;
};

sub display {
    return 'void://hostname:000/';
}

sub is_active {
    my $self = shift;

    return $self->_value('is_active');
}

sub pause {
    my $self = shift;
    $self->_store(is_active => 0);
}
sub remove {
    my $self = shift;

    $self->_store(is_active => 0);
}

sub _store {
    my $self = shift;

    my ($var, $value) = @_;

    my $data = {};
    $data = LoadFile($self->disk_device )   if -e $self->disk_device();
    $data->{$var} = $value;
    DumpFile($self->disk_device , $data);

}

sub _value{
    my $self = shift;

    my ($var) = @_;

    my $data = LoadFile($self->disk_device );
    
    return $data->{$var};

}


sub shutdown {
    my $self = shift;
    $self->_store(is_active => 0);
}

sub start {
    my $self = shift;
    $self->_store(is_active => 1);
}

sub prepare_base {
    my $self = shift;

    # TODO do it for many devices. Requires new table in SQL db
    my $file_qcow = $self->disk_device;
    $file_qcow .= ".qcow";

    open my $out,'>',$file_qcow or die "$! $file_qcow";
    print $out "$file_qcow\n";
    close $out;
    $self->_prepare_base_db($file_qcow);

}

sub disk_device {
    my $self = shift;
    return "$TMP_DIR/".$self->name.".img";
}

sub list_disks {
    return disk_device(@_);
}

sub _vol_remove {
    return;
}

sub remove_disks {
    my $self = shift;
    for my $file ($self->list_disks) {
        if (! -e $file ) {
            warn "WARNING: $file already removed for ".$self->domain->get_name."\n";
            next;
        }
        $self->_vol_remove($file);
        if ( -e $file ) {
            unlink $file or die "$! $file";
        }
    }

}

1;
