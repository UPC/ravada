package Ravada::Domain::LXC;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

#with 'Ravada::Domain';

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################
#TODO
#sub name {
#    my $self = shift;
#}
#TODO

sub create_container {
 	my $self = shift;
    my $name = shift;
    my @domain = ('lxc-create','-n',$name,'-t','ubuntu');
    my ($in,$out,$err);
    run3(\@domain,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
	return;
}


sub remove_container {
    my $self = shift;
    my $name = shift;
    my @domain = ('lxc-destroy','-n',$name,'-f');
    my ($in,$out,$err);
    run3(\@domain,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;
}

sub search_container {
    my $self = shift;
    my $name = shift;
    my @info = ('lxc-info','-n',$name);
    my ($in,$out,$err);
    run3(\@info,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;
}

sub shutdown {
    my $self = shift;

}


=head2 pause

Pauses the domain

=cut

sub pause {
}

1;
