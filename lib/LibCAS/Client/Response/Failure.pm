package LibCAS::Client::Response::Failure;

use strict;
use warnings;

use base "LibCAS::Client::Response";

our $VERSION = '0.01';

sub new {
	my $this  = shift;	
	my $class = ref($this) || $this;
	
	return $class->SUPER::new(@_, message => '', ok => 0);
}

sub code {
	my $self = shift;
	my $code = shift;
	
	if (defined $code) {
		$self->{code} = $code;
	}
	
	return $self->{code};
}

sub message {
	my $self = shift;
	my $message = shift;
	
	if (defined $message) {
		$self->{message} = $message;
	}
	
	return $self->{message};
}

1;