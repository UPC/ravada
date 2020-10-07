package LibCAS::Client;

require 5.008_008;

use strict;
use warnings;

use HTTP::Cookies;
use LWP::UserAgent;
use URI;
use XML::LibXML;

use LibCAS::Client::Response::Error;
use LibCAS::Client::Response::Failure;
use LibCAS::Client::Response::AuthenSuccess;
use LibCAS::Client::Response::ProxySuccess;

=head1 NAME

LibCAS::Client - A perl module for authenticating and validating against Jasig's CAS server

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

LibCAS::Client provides an OO interface for generating URLs and validating tickets for
Jasig's Central Authentication Service (CAS).

Using the module should hopefully be straight forward, something similar to:

	my $cas = LibCAS::Client->new(cas_url => 'https://my-cas-server/cas');
	my $login_url = $cas->login_url(service => 'my_service_name');
	
	# Do a HTTP redirect to $login_url to have CAS prompt for credentials
	# or to have the CAS server issue a service ticket.
	
	my $r = $cas->service_validate(service => 'my_service_name', ticket => 'ticket_from_login');
	
	if ($r->is_success()) {
		# Do things for successful authentication
	} elsif ($r->is_failure()) {
		# Do things for failed authentication
	} else {
		# Anything that makes it here is an error
	}

=cut 

my $cas_url = "https://localhost/cas";
my $cas_login_path    = "/login";
my $cas_logout_path   = "/logout";
my $cas_validate_path = "/validate"; # CAS 1.0
my $cas_proxy_path    = "/proxy"; # CAS 2.0
my $cas_serviceValidate_path = "/serviceValidate"; # CAS 2.0
my $cas_proxyValidate_path   = "/proxyValidate"; # CAS 2.0

=head1 METHODS

=head2 new

Create a new instance of the LibCAS::Client object.  Valid parameters are:

=over

=item I<cas_url> - The base URL to the CAS server, defaults to C<< https://localhost/cas >>

=item I<cas_login_path> - The path to the CAS login service, defaults to C<< /login >>

=item I<cas_logout_path> - The path to the CAS logout service, defaults to C<< /logout >>

=item I<cas_validate_path> - The path to the CAS v1.0 validation service, defaults to C<< /validate >>

=item I<cas_proxy_path> - The path to the CAS proxy service, defaults to C<< /proxy >>

=item I<cas_serviceValidate_path> - The path to the CAS v2.0 service validation service, defaults to C<< /serviceValidate >>

=item I<cas_proxyValidate_path> - The path to the CAS v2.0 proxy validation service, defaults to C<< /proxyValidate >>

=back

=cut

sub new {
	my $this = shift;
	my %args = @_;

	my $self = {
		cas_url => $cas_url,
		cas_login_path    => $cas_login_path,
		cas_logout_path   => $cas_logout_path,
		cas_validate_path => $cas_validate_path,
		cas_proxy_path    => $cas_proxy_path,
		cas_serviceValidate_path => $cas_serviceValidate_path,
		cas_proxyValidate_path   => $cas_proxyValidate_path,
		debug => 0
	};
	
	map { $self->{$_} = $args{$_} } keys %args;

	my $ssl_opts = {
		verify_hostname => 0,
		SSL_ca_path  => undef,
		SSL_ca_file  => undef,
		SSL_use_cert => 0,
		SSL_verify_mode => 0
	};

	$self->{_ua} = LWP::UserAgent->new( 
		agent => "Authen-CAS/$VERSION",
		ssl_opts => $ssl_opts,
		cookie_jar => HTTP::Cookies->new()
	);
	
	my $class = ref($this) || $this;
	
	bless($self,$class);
	return $self;
}

=head2 login_url

Generate the login url needed for the CAS server, depending on the C<< cas_url >> and C<< cas_login_path >>
parameters passed during object construction.

Valid parameters to the C<< login_url >> method are:

=over

=item I<service> [optional] - The name of the service to authenticate for.

=item I<renew> [optional] - Bypass any existing single sign-on session, and require the client to represent their credentials.

=item I<gateway> [optional] - Do not require the client to present credentials if a single sign-on has not been established. 

=back

=cut

sub login_url {
	my $self = shift;
	my %args = @_;
	
	my %query_string = ();
	
	my $cas_uri = URI->new($self->{cas_url}.$self->{cas_login_path});
	
	if ($args{'service'}) {
		$query_string{'service'} = $args{'service'};
	}
	
	if ($args{'renew'} && _is_true($args{'renew'})) {
		$query_string{'renew'} = 'true';
	}
	
	if ($args{'gateway'} && _is_true($args{'gateway'})) {
		$query_string{'gateway'} = 'true';
	}
	
	return _build_url($cas_uri, \%query_string);
}

=head2 logout_url

Generate the logout url needed for the CAS server, depending on the C<< cas_url >> and C<< cas_logout_path >>
parameters passed during object construction.

B<NOTE:> Calling this method will destroy the single sign-on session, which may affect the client's ability
to access other applications protected by this CAS server.

Valid parameters to the C<< logout_url >> method are:

=over

=item I<url> [optional] - A URL to be displayed on the logout page. 

=back

=cut

sub logout_url {
	my $self = shift;
	my %args = @_;
	
	my %query_string = ();
	
	my $cas_uri = URI->new($self->{cas_url}.$self->{cas_logout_path});
	
	if ($args{'url'}) {
		$query_string{'url'} = $args{'url'};
	}
	
	return _build_url($cas_uri, \%query_string);
}

=head2 validate_url

Generate the URL that performs CAS protocol version 1.0 service ticket validation.

Valid parameters to the C<< validate_url >> method are:

=over

=item I<service> [required] - The name of the service which the ticket was issued for.

=item I<ticket> [required] - The service ticket issued by the CAS server.

=item I<renew> [optional] - If set, this option will only allow validation to pass if the ticket was
issued immediatly after the client presents their credentials.  It will fail if the service ticket
that is presented was issued from a single sign-on session.

=back

=cut

sub validate_url {
	my $self = shift;
	
	my $cas_uri = URI->new($self->{cas_url}.$self->{cas_validate_path});

	my $query_string = _parse_validate_args(@_) || return;
	
	return _build_url($cas_uri, $query_string);
}

=head2 service_validate_url

Generate the URL that performs CAS protocol version 2.0 service ticket validation, and generate proxy-
granting tickets, if requested.

Valid parameters to the C<< service_validate_url >> method are:

=over

=item I<service> [required] - The name of the service which the ticket was issued for.

=item I<ticket> [required] - The service ticket issued by the CAS server.

=item I<renew> [optional] - If set, this option will only allow validation to pass if the ticket was
issued immediatly after the client presents their credentials.  It will fail if the service ticket
that is presented was issued from a single sign-on session.

=item I<pgtUrl> [optional] - The URL of the proxy callback.

=back

=cut

sub service_validate_url {
	my $self = shift;
	
	my $cas_uri = URI->new($self->{cas_url}.$self->{cas_serviceValidate_path});
	
	my $query_string = _parse_validate20_args(@_) || return;
	
	return _build_url($cas_uri, $query_string);
}

=head2 proxy_url

Generate the URL to the CAS server for generating proxy tickets.

Valid parameters to the C<< proxy_url >> method are:

=over

=item I<pgt> [required] - The proxy granting ticket.

=item I<targetService> [required] - The service identifier for the back-end service.

=back

=cut

sub proxy_url {
	my $self = shift;
	my %args = @_;
	
	my %query_string = ();
	
	my $cas_uri = URI->new($self->{cas_url}.$self->{cas_proxy_path});	
	
	if (! $args{'pgt'} || ! $args{'targetService'}) {
		$@ = "pgt and targetService parameters must be supplied";
		return;
	} else {
		$query_string{'pgt'} = $args{'pgt'};
		$query_string{'targetService'} = $args{'targetService'};
	}
	
	return _build_url($cas_uri, \%query_string);
}

=head2 proxy_validate_url

This method performs the same functions as the C<< service_validate_url >> method, with the added
benefit of being able to validate proxy tickets as well.

Valid parameters for C<< proxy_validate_url >> are the same as they are for C<< service_validate_url >>

=cut

sub proxy_validate_url {
	my $self = shift;
	
	my $cas_uri = URI->new($self->{cas_url}.$self->{cas_proxyValidate_path});
	
	my $query_string = _parse_validate20_args(@_) || return;
	
	return _build_url($cas_uri, $query_string);
}

sub authenticate {
	my $self = shift;
	my %args = @_;
	
	my $r;
	
	if (! $args{username} || ! $args{password}) {
		$r = LibCAS::Client::Response::Error->new(error => "username and password parameters must be supplied");
	} else {
		my $query_string = $self->_get_hidden_form_params();
		
		$query_string->{username} = $args{username};
		$query_string->{password} = $args{password};

		if ($args{service}) {
			$query_string->{service} = $args{service};
		}
		
		if ($args{'warn'} && _is_true($args{'warn'})) {
			$query_string->{'warn'} = $args{'warn'};
		}
		
		if (! $query_string->{'lt'}) {
			$r = LibCAS::Client::Response::Error->new(error => $@);
		} else {			
			my $response = $self->{_ua}->post($self->login_url(), Content => $query_string);
			
			if ($response->is_success()) {
				$r = LibCAS::Client::Response::AuthenSuccess->new(user => $args{username});
			} else {
				$r = LibCAS::Client::Response::Error->new(error=>_create_http_error_message($response));
			}
		}
	}
	
	return $r;
}

=head2 validate

Validate a service ticket using CAS protocol version 1.0.  Supported arguments for this method are the
same as they are for the C<< validate_url >> method.

Returns an LibCAS::Client::Response object to denote whether or not the validation was successful.  Success,
failure, or error conditions can be checked by calling the C<< is_success() >>, C<< is_failure() >>, or
C<< is_error() >> methods on the returned object.

=cut

sub validate {
	my $self = shift;
	my $r;
	
	my $url = $self->validate_url(@_);
	
	if (! $url) {
		$r = LibCAS::Client::Response::Error->new(error => "URL generation failed: ".$@);
	}

	my $response = $self->do_http_request($url);
	
	if (! $response) {
		$r = LibCAS::Client::Response::Error->new(error => $@);
	}
	
	if ($response =~ /^no\n\n$/) {
		$r = LibCAS::Client::Response::Failure->new(code => 'V1_VALIDATE_FAILURE', response => $response);
	} elsif ($response =~ /^yes\n([^\n]+)\n$/){
		$r = LibCAS::Client::Response::AuthenSuccess->(user => $1, response => $response);
	} else {
		$r = LibCAS::Client::Response::Error->new(error => "Invalid response from CAS", response => $response);
	}
	
	return $r;
}

=head2 service_validate

Validate a service ticket using CAS protocol version 2.0.  Supported arguments for this method are the
same as they are for the C<< service_validate_url >> method.

Returns an LibCAS::Client::Response object to denote whether or not the validation was successful.  Success,
failure, or error conditions can be checked by calling the C<< is_success() >>, C<< is_failure() >>, or
C<< is_error() >> methods on the returned object.

=cut

sub service_validate {
	my $self = shift;
	my $r;
	
	my $url = $self->service_validate_url(@_);
	
	if (! $url) {
		$r = LibCAS::Client::Response::Error->new(error => "URL generation failed: ".$@);
	} else {
		$r = $self->_do_v2_validation_request($url);
	}
	
	return $r;
}

=head2 proxy

Obtain a proxy ticket to services that have a proxy granting ticket, and will be using proxy
authentication to a back-end service.  Supported arguments for this method are the
same as they are for the C<< service_validate_url >> method.

Returns an LibCAS::Client::Response object to denote whether or not the validation was successful.  Success,
failure, or error conditions can be checked by calling the C<< is_success() >>, C<< is_failure() >>, or
C<< is_error() >> methods on the returned object.

=cut

sub proxy {
	my $self = shift;
	my $r;
	
	my $url = $self->proxy_url(@_);
	
	if (! $url) {
		$r = LibCAS::Client::Response::Error->new(error => "URL generation failed: ".$@);
	} else {
		my $response = $self->do_http_request($url);
		
		if (! $response) {
			$r = LibCAS::Client::Response::Error->new(error => $@);
		} else {
			$r = _parse_v2_proxy_xml_response($response);
		}
	}
	
	return $r;
}

=head2 proxy_validate

Validate a service ticket, or a proxy ticket, using CAS protocol version 2.0.  Supported arguments for this method are the
same as they are for the C<< proxy_validate_url >> method.

Returns an LibCAS::Client::Response object to denote whether or not the validation was successful.  Success,
failure, or error conditions can be checked by calling the C<< is_success() >>, C<< is_failure() >>, or
C<< is_error() >> methods on the returned object.

=cut

sub proxy_validate {
	my $self = shift;
	my $r;
	
	my $url = $self->proxy_validate_url(@_);
	
	if (! $url) {
		$r = LibCAS::Client::Response::Error->new(error => "URL generation failed: ".$@);
	} else {
		$r = $self->_do_v2_validation_request($url);
	}
	
	return $r;
}

sub do_http_request {
	my $self = shift;
	my $url  = shift;

	my $response = $self->{_ua}->get($url);

	if (! $response->is_success) {
		$@ = _create_http_error_message($response);
		return;
	} else {
		return $response->content;
	}
}

sub _get_hidden_form_params {
	# There are a number of hidden form fields that are needed to successfully log in
	# programatically.  
	my $self = shift;

	my $response = $self->{_ua}->get($self->login_url());
	my $parser   = XML::LibXML->new();
	
	my %params;
	
	eval {
		if ($response->is_success()) {			
			my $doc = $parser->parse_html_string($response->content(), {recover => 1});
			my @nodes = $doc->findnodes('//input[@type="hidden"]');
			
			%params = map { $_->getAttribute('name') => $_->getAttribute('value') } @nodes;
			
			if (! $params{'lt'}) {
				die "Could not find login ticket";
			}
		} else {
			die _create_http_error_message($response);
		}
	};
	
	if ($@) {
		return;
	} else {
		return \%params;
	}
}

sub _parse_v2_proxy_xml_response {
	my $xml = shift;
	my ($r, $doc, $node);

	my $parser = XML::LibXML->new();

	eval {
		my $doc = $parser->parse_string($xml);
		
		if ($node = $doc->find('/cas:serviceResponse/cas:proxySuccess')->get_node(1)) {
			my $tkt = $node->find('./cas:proxyTicket')->get_node(1)->textContent;
			
			if ($tkt) {
				$r = LibCAS::Client::Response::ProxySuccess->new(proxy_ticket => $tkt, response => $doc);
			} else {
				die "Invalid CAS Response, could not find proxyTicket information";
			}
		} elsif ($node = $doc->find('/cas:serviceResponse/cas:proxyFailure')->get_node(1)) {
			if ($node->hasAttribute('code')) {
				my $code = $node->getAttribute('code');
				my $msg  = $node->textContent;
				
				$msg =~ s/^\s+//;
				$msg =~ s/\s+$//;
				
				$r = LibCAS::Client::Response::Failure->new(code => $code, message => $msg, response => $doc);
			} else {
				die "Invalid CAS Response, could not find proxy failure code attribute";
			}
		} else {
			die "Invalid CAS Response"
		}
	};
	
	if ($@) {
		$r = LibCAS::Client::Response::Error->new(error => $@, response => $doc);
	}
	
	return $r;
}

sub _parse_v2_validate_xml_response {
	my $xml = shift;
	my ($r, $doc, $node);

	my $parser = XML::LibXML->new();

	eval {
		my $doc = $parser->parse_string($xml);
		
		if ($node = $doc->find('/cas:serviceResponse/cas:authenticationSuccess')->get_node(1)) {
			my $user = $node->find('./cas:user')->get_node(1)->textContent;
			
			if ($user) {
				my $pgt = $node->find('./cas:proxyGrantingTicket')->get_node(1);
				$pgt = $pgt->textContent if $pgt;
				
				my $proxies = $node->findnodes('./cas:proxies/cas:proxy');
				$proxies = [ map $_->textContent, @$proxies ] if $proxies;
				
				$r = LibCAS::Client::Response::AuthenSuccess->new(
						user => $user,
						pgt  => $pgt,
						proxies => $proxies,
						response => $doc
					);
			} else {
				die "Invalid CAS Response, could not find user information";
			}
		} elsif ($node = $doc->find('/cas:serviceResponse/cas:authenticationFailure')->get_node(1)) {
			if ($node->hasAttribute('code')) {
				my $code = $node->getAttribute('code');
				my $msg  = $node->textContent;
				
				$msg =~ s/^\s+//;
				$msg =~ s/\s+$//;
				
				$r = LibCAS::Client::Response::Failure->new(code => $code, message => $msg, response => $doc);
			} else {
				die "Invalid CAS Response, could not find validation failure code attribute";
			}
		} else {
			die "Invalid CAS Response"
		}
	};
	
	if ($@) {
		$r = LibCAS::Client::Response::Error(error => $@, response => $doc);
	}
	
	return $r;
}

sub _do_v2_validation_request {
	my $self = shift;
	my $url  = shift;
	my $r;
	
	my $response = $self->do_http_request($url);
	
	if (! $response) {
		$r = LibCAS::Client::Response::Error->new(error => $@);
	} else {
		$r = _parse_v2_validate_xml_response($response);
	}
	
	return $r;
}

sub _build_url {
	my $uri = shift;
	my $query_string = shift;
	
	if ($query_string) {
		$uri->query_form($query_string);
	}
	
	return $uri->canonical;
}

sub _parse_validate20_args {
	my %args = @_;

	my $query_string = _parse_validate_args(%args) || return;
	
	if ($args{'pgtUrl'}) {
		$query_string->{'pgtUrl'} = $args{'pgtUrl'};
	}
	
	return $query_string;
}

sub _parse_validate_args {
	my %args = @_;
	my %query_string = ();

	if (! $args{'service'} || ! $args{'ticket'}) {
		$@ = "service and ticket parameters must be specified";
		return;
	} else {
		$query_string{'service'} = $args{'service'};
		$query_string{'ticket'}  = $args{'ticket'};
	}
	
	if ($args{'renew'} && _is_true($args{'renew'})) {
		$query_string{'renew'} = 'true';
	}
	
	return \%query_string;
}

sub _is_true {
	my $arg = shift;
	my $is_true = 0;
	
	if (defined $arg) {
		if ($arg =~ /^\d+$/ && $arg > 0) {
			$is_true = 1;
		} else {
			if ($arg =~ /^true$/i || $arg =~ /^t$/i ||
			    $arg =~ /^yes$/i || $arg =~ /^y$/i) {
				$is_true = 1;    	
			}
		}
	}
	
	return $is_true;
}

sub _create_http_error_message {
	my $response = shift;
	
	return "HTTP request failed: ".$response->code.": ".$response->message." -> ".$response->content;
}

=head1 AUTHOR

"Mike Morris", C<< <"michael.m.morris at gmail.com"> >>

=head1 BUGS

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc LibCAS::Client

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=LibCAS>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/LibCAS>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/LibCAS>

=item * Search CPAN

L<http://search.cpan.org/dist/LibCAS/>

=back

=head1 ACKNOWLEDGEMENTS

This code is derived from L<Authen::CAS::Client|http://search.cpan.org/~pravus/Authen-CAS-Client-0.05/>
and L<AuthCAS|http://search.cpan.org/~osalaun/AuthCAS/>, with the added ability to customize the paths for
the services on the CAS server, and use URI and XML parsing libs.

Documentation for the CAS protocol can be found at L<http://www.jasig.org/cas/protocol>

=head1 LICENSE AND COPYRIGHT

Copyright 2012 "Michael Morris".

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;