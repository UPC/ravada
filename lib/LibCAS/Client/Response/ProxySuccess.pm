package LibCAS::Client::Response::ProxySuccess;

use strict;
use warnings;

use base "LibCAS::Client::Response::Success";

our $VERSION = '0.01';

sub new {
	my $this  = shift;	
	my $class = ref($this) || $this;
	
	return $class->SUPER::new(@_);
}

sub proxy_ticket {
	my $self = shift;
	my $ticket = shift;
	
	if (defined $ticket) {
		$self->{proxy_ticket} = $ticket;
	}
	
	return $self->{proxy_ticket};
}