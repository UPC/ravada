package LibCAS::ModPerl2;

=head1 NAME

LibCAS::ModPerl2 - An Apache mod_perl (version 2) handler to enable CAS authentication.

=head1 VERSION

Version 0.01

=head1 CONFIGURATION

This handler is expected to be used as a PerlAccessHandler wherever the directive is allowed.

The following handler options can be set using the PerlSetVar directive:

=over

=item I<secure> [optional] - If set, all requests will requre CAS validation.  Otherwise, determining
if CAS authentication is required can be controlled by the 'secure' URL parameter in the request.

=item I<casPrefix> [optional] - The url to the CAS server, which will be used in the LibCAS
constructor as the cas_url parameter.  If not provided, it will use the default LibCAS setting.

=back

=head2 Apache config file example

Here's an example of how to configure this handler for a given location,
and require CAS authentication for all requests:

<Location "/path/">
    SetHandler perl-script
    PerlAccessHandler LibCAS::ModPerl2
    PerlResponseHandler Some::Other::Module
    PerlSetVar casPrefix https://cas-server/cas
    PerlSetVar secure 1
</Location>

Here's an example of how to configure this handler for a given location,
but not require CAS authentication for all requests (instead, depend on the 'secure' URL parameter):

<Location "/path/">
    SetHandler perl-script
    PerlAccessHandler LibCAS::ModPerl2
    PerlResponseHandler Some::Other::Module
    PerlSetVar casPrefix https://cas-server/cas
</Location>

=cut

use strict;
use warnings;

use Apache2::Const -compile => qw(:common :log :http);
use Apache2::Log;
use Apache2::RequestRec;
use Apache2::URI;
use APR::Table;

use LibCAS::Client;

our $VERSION = '0.01';

sub handler {
	my $r = shift;
	my $status = Apache2::Const::FORBIDDEN;
	
	my $config_secure = $r->dir_config('secure') || 0;
	my $cas_host = $r->dir_config('casPrefix');
	
	# Get query string values as a hashref
	my $args = parse_args($r->args());
	
	my $secure = resolve_secure($config_secure, $args->{'secure'});
	
	# Do CAS stuff here
	my $cas;
    my $cas_service = build_cas_service($r);
    
    if ($args->{'ticket'}) {
    	# We have a ticket URL parameter, validate against CAS server
    	# regardless if the $secure flag is set or not.  If validation
    	# is successful, then we'll process the request.  If validation
    	# fails, we'll redirect to the CAS login page.
    	$cas = LibCAS::Client->new(cas_url => $cas_host) if ! $cas;
    	
    	my $cas_resp = $cas->service_validate(service => $cas_service, ticket => $args->{'ticket'});
    	
    	if ($cas_resp->is_success()) {
    		$status = Apache2::Const::OK;
    	} elsif ($cas_resp->is_failure()) {
    		my $code = $cas_resp->code;
    		
    		if ($code ne 'INVALID_TICKET' && $code ne 'INVALID_SERVICE') {
    			my $status;

    			$r->warn('CAS ticket validation failed, CODE => '.$cas_resp->code.
    				' MESSAGE => '.$cas_resp->message);
    			$r->log->debug('CAS server response was: '.$cas_resp->response());
 
    			if ($code eq 'INTERNAL_ERROR') {
    				$status = Apache2::Const::SERVER_ERROR;
    			} else {
    				$status = Apache2::Const::FORBIDDEN;
    			}
    			
    			$r->status($status);
    		} else {
    			$status = Apache2::Const::REDIRECT;
    			$r->headers_out->set('Location' => $cas->login_url(service => $cas_service));
    			$r->status($status);
    		}
    	} else {
    		$status = Apache2::Const::SERVER_ERROR;
    		
    		use Data::Dumper;
    		$r->log_error("Unexpected result from CAS ticket validation: ".Dumper($cas_resp));
    		$r->status($status);
    	}
    } else {
    	if (is_true($secure)) {
    		# We're supposed to be authenticated, redirect to CAS login
    		# so we can get a service ticket to process the request.
    		$status = Apache2::Const::REDIRECT;
    		$cas = LibCAS::Client->new(cas_url => $cas_host) if ! $cas;

    		$r->headers_out->set('Location' => $cas->login_url(service => $cas_service));
    		$r->status($status);
    	} else {
    		# 'Unsecured' request, continue
    		$status = Apache2::Const::OK;
    	}
    }
    
    return $status;
}

sub parse_args {
	my $args = shift;
	my %parsed;

    return undef if ! $args;

    foreach my $arg (split('&', $args)) {
        my ($key,$value) = split('=', $arg, 2);
		$parsed{$key} = $value;
    }

	return \%parsed;
}

sub is_true {
    my $value = shift;

    if (defined $value && ($value =~ /^true$/i || $value =~ /^yes$/i || $value > 0)) {
        return 1;
    } else {
        return 0;
    }
}

sub resolve_secure {
	my ($config, $param) = @_;
	my $secure = 0;
	
	if (is_true($config)) {
		# If config directive specifies secure, then we're secure no matter
		# what a client passes us
		$secure = 1;
	} else {
		# config directive says not secure, or undef, so use what the client passes in
		$secure = is_true($param);
	}
	
	return $secure;
}

sub build_cas_service {
	my $r = shift;
	my $args = parse_args($r->args());

	my $uri = URI->new($r->construct_url());

	if (defined $args) {
		my %query_string = %$args;
		delete $query_string{'ticket'};

		$uri->query_form(\%query_string);	
	}

	$r->log->info("CAS service URL is: ".$uri);
	return $uri;
}

1;