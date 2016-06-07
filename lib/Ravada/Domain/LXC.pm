package Ravada::Domain::LXC;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################
#TODO
sub name {
    my $self = shift;
}
#TODO

sub remove {
    my $self = shift;
    my $base_name = $self->name;
    my @domain = ('lxc-destroy','-n',$name,'-f');
    my ($in,$out,$err);
    run3(\@domain,\$in,\$out,\$err);
    #ok(!$?,"@domain \$?=$? , it should be 0 $err $out.");
    #}

    #run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    die "Command failed: $!" unless ($err && $? == 0);
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
