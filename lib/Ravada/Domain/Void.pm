package Ravada::Domain::Void;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;

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

}

sub name { 
    my $self = shift;
    return $self->domain;
};

sub display {
    return 'void://hostname:000/';
}

sub is_active {}

sub pause {}
sub remove {
    my $self = shift;
    $self->_remove_domain_db();
    $self->remove_disks();
}
sub shutdown {}
sub shutdown_now {
    my $self = shift;
    return $self->shutdown(@_);
}
sub start {}
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
    my $self = shift;
    my $file = shift;
    unlink $file or die "$! $file"
        if -e $file;
}

sub remove_disks {
    my $self = shift;
    for my $file ($self->list_disks) {
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
}


1;
