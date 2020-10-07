package LibCAS::Client::Response::Error;

use strict;
use warnings;

use base "LibCAS::Client::Response";

our $VERSION = '0.01';

sub new {
	my $this  = shift;
	my $class = ref($this) || $this;
	
	return $class->SUPER::new(@_, error => 'internal error', ok => undef);
}

sub error {
	my $self  = shift;
	my $error = shift;
	
	if (defined $error) {
		$self->{error} = $error;
	}
	
	return $self->{error};
}

1;