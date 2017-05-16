package Ravada::Domain::LXD;
use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

with 'Ravada::Domain';

has 'domain' => (
      is => 'ro'
    ,isa => 'Str'
    ,required => 1
);

###############################################################3
#
our $LXC = `which lxc`;
chomp $LXC;
die "Missing lxc"   if !$LXC;

our $LXD = `which lxd`;
chomp $LXD;
die "Missing lxd"   if !$LXD;
#
#
###############################################################3

sub display {
}

sub is_active {}

sub name {
    my $self = shift;
    return $self->domain;
}

sub pause { }

sub remove {
    my $self = shift;

    my @cmd = ($LXC,'delete',$self->name);
    my ($in, $out, $err);

    run3(\@cmd, \$in, \$out, \$err);
    die $err if $?;
    warn $out if$out;
}

sub shutdown {}

sub start {}

sub _prepare_base_file {
    #TODO
}

sub _do_force_shutdown {
    #TODO
}

sub prepare_base {
    my $self = shift;

    my $file_base = $self->_prepare_base_file();
    $self->_prepare_base_db($file_base);
}

sub add_volume {}

sub clean_swap_volumes {}

sub disk_device {}

sub disk_size {}

sub force_shutdown {}

sub get_info {}

sub hybernate {}

sub is_hibernated {}

sub is_paused {}

sub list_volumes {}

sub rename {}

sub resume {}

sub set_max_mem {}

sub set_memory {}

sub shutdown_now {}

sub spinoff_volumes {}

sub screenshot {}

1;
