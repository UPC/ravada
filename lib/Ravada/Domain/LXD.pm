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

1;
