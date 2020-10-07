package LibCAS::Client::Response::Success;

use strict;
use warnings;

use base "LibCAS::Client::Response";

our $VERSION = '0.01';

sub new {
	my $this  = shift;	
	my $class = ref($this) || $this;
	
	return $class->SUPER::new(@_, ok => 1);
}

1;