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

sub create_domain {
 	my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-create','-n',$name,'-t','ubuntu');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
	return;
}


sub remove_domain {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-destroy','-n',$name,'-f');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;
}

sub search_domain {
    my $self = shift;
    my $container_name = $self->name;
#    my $name = shift;
    my @cmd = ('lxc-info','-n',$container_name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return ( $? );
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
