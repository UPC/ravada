package LibCAS::Client::Response;

use strict;
use warnings;

our $VERSION = '0.01';

sub new {
	my $this = shift;
	my %args = @_;
	
	my $self = { ok => undef, response => undef};
	
	map { $self->{$_} = $args{$_} } keys %args;

	my $class = ref($this) || $this;
	
	bless($self, $class);
	return $self;
}

sub is_error {
	my $self = shift;
	return ! defined $self->{ok};
}

sub is_failure {
	my $self = shift;
	return (defined $self->{ok} && ! $self->{ok});
}

sub is_success {
	my $self = shift;
	return (defined $self->{ok} && $self->{ok});
}

sub response {
	my $self = shift;
	my $response = shift;
	
	if (defined $response) {
		$self->{response} = $response;
	}
	
	return $self->{response};
}

1;