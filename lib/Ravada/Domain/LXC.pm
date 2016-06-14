package Ravada::Domain::LXC;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

with 'Ravada::Domain';

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################


sub name {
 #   my $self = shift;
 #   $self->_select_domain_db or return;

#    return 1 if $self->_data('name');
}

sub remove {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-destroy','-n',$name,'-f');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;
}

sub display {
    my $self = shift;

}

sub is_active {
    my $self = shift;

}

sub start {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-start','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;

}

sub shutdown {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-stop','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;

}


=head2 pause

Pauses the domain

=cut

sub pause {
    my $self = shift;

}



1;
