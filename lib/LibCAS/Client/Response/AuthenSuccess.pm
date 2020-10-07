package LibCAS::Client::Response::AuthenSuccess;

use strict;
use warnings;

use base "LibCAS::Client::Response::Success";

our $VERSION = '0.01';

sub new {
	my $this  = shift;	
	my $class = ref($this) || $this;
	
	return $class->SUPER::new(@_);
}

sub user {
	my $self = shift;
	my $user = shift;
	
	if (defined $user) {
		$self->{user} = $user;
	}
	
	return $self->{user};
}

sub pgt {
	my $self = shift;
	my $pgt  = shift;
	
	if (defined $pgt) {
		$self->{pgt} = $pgt;
	}
	
	return $self->{pgt};
}

sub proxies {
	my $self = shift;
	
	return wantarray ? @{$self->{proxies}} : $self->{proxies};
}

1;