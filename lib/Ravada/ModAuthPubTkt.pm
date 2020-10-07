package Ravada::ModAuthPubTkt;

=pod
=head1 NAME
pubtkt - Generate Tickets for mod_auth_pubtkt
=head1 VERSION
version 0.1
=cut
our $VERSION = '0.1';

=pod
=head1 SYNOPSIS
    use mod_auth_pubtkt;
    ## NOTE: "key.priv.pem" and "key.pub.pem" must already exist.
    ## running these should suffice:
    ##   openssl genrsa -out key.priv.pem 1024
    ##   openssl rsa -in key.priv.pem -out key.pub.pem -pubout
    my $ticket = pubtkt_generate(
    		privatekey => "key.priv.pem",
    		keytype    => "rsa",
    		clientip   => undef,  # or a valid IP address
    		userid     => "102",  # or any ID that makes sense to your application, e.g. email
    		validuntil => time() + 86400, # valid for one day
    		graceperiod=> 3600,   # grace period of an hour
    		tokens     => undef,  # comma separated string of tokens.
    		userdata   => undef   # any application specific data to pass.
                 );
    ## $ticket string will look something like:
    ## "uid=102;validuntil=1337899939;graceperiod=1337896339;tokens=;udata=;sig=h5qR" \
    ## "yZZDl8PfW8wNxPYkcOMlAxtWuEyU5bNAwEFT9lztN3I7V13SaGOHl+U6wB+aMkvvLQiaAfD2xF/Hl" \
    ## "+QmLDEvpywp98+5nRS+GeihXTvEMRaA4YVyxb4NnZujCZgX8IBhP6XBlw3s7180jxE9I8DoDV8bDV" \
    ## "k/2em7yMEzLns="

    my $ok = pubtkt_verify (
    		publickey => "key.pub.pem",
    		keytype   => "rsa",
    		ticket    => $ticket
    	);
    die "Ticket verification failed.\n" if not $ok;
=head1 DESCRIPTION
This module generates and verify a mod_auth_pubtkt-compatible ticket string, which should be used
as a cookie with the rest of the B<mod_auth_pubtkt> ( L<https://neon1.net/mod_auth_pubtkt/> ) system.
=head3 Common scenario:
=over 2
=item 1.
On the login server side, write perl code to authenticate users (using Apache's authenetication, LDAP, DB, etc.).
=item 2.
Once the user is authenticated, call C<pubtkt_generate> to generate a ticket, and send it back to the user as a cookie.
=item 3.
Redirect the user back to the server he/she came from.
=back
=head1 PREREQUISITES
B<openssl> must be installed (and available on the $PATH).
L<IPC::Run3> is required to run the openssl executables.
=head1 BUGS
Probably many.
=head1 LICENSE
Copyright (C) 2012 A. Gordon ( gordon at cshl dot edu ).
Apache License, same as the rest of B<mod_auth_pubtkt>
=head1 AUTHORS
A. Gordon, heavily based on the PHP code from B<mod_auth_pubtkt>.
=head1 SEE ALSO
L<https://neon1.net/mod_auth_pubtkt/>
C<test_pubtkt.pl> for a usage example.
=cut

require Exporter;
our @ISA=qw(Exporter);
our @EXPORT = qw/pubtkt_generate
		 pubtkt_verify
		 pubtkt_parse/;

use strict;
use warnings;
use Carp;
use MIME::Base64;
use File::Temp qw/tempfile/;
use IPC::Run3;


## On unix, assume it's on the $PATH.
## On Windows - you're on your own.
## TODO: make this user-configurable.
my $openssl_bin = "openssl";

=pod
=cut
sub pubtkt_generate
{
	my %args = @_;
	my $private_key_file = $args{privatekey} or croak "Missing \"privatekey\" parameter";
	croak "Invalid \"privatekey\" value ($private_key_file): file doesn't exist/not readable"
		unless -r $private_key_file;

	my $keytype = $args{keytype} or croak "Missing \"keytype\" parameter";
	croak "Invalid \"keytype\" value ($keytype): expecting 'dsa' or 'rsa'\n"
		unless $keytype eq "dsa" || $keytype eq "rsa";

	my $user_id = $args{userid} or croak "Missing \"userid\" parameter";

	my $valid_until = $args{validuntil} or croak "Missing \"validuntil\" parameter";
	croak "Invalid \"validuntil\" value ($valid_until), expecting a numeric value."
		unless $valid_until =~ /^\d+$/;

	my $grace_period = $args{graceperiod} || "";
	croak "Invalid \"graceperiod\" value ($grace_period), expecting a numeric value."
		unless $grace_period eq "" || $grace_period =~ /^\d+$/;

	my $client_ip = $args{clientip} || "";
	##TODO: better IP address validation
	croak "Invalid \"client_ip\" value ($client_ip), expecting a valid IP address."
		unless $client_ip eq "" || $client_ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;

	my $tokens = $args{tokens} || "";
	my $user_data = $args{userdata} || "";

	# Generate Ticket String
	my $tkt = "uid=$user_id;" ;
	$tkt .= "cip=$client_ip;" if $client_ip;
	$tkt .= "validuntil=$valid_until;";
	$tkt .= "graceperiod=" . ($valid_until - $grace_period) . ";" if $grace_period;
	$tkt .= "tokens=$tokens;";
	$tkt .= "userdata=$user_data";

	my $algorithm_param  = ( $keytype eq "dsa" ) ? "-dss1" : "-sha1";

	my @cmd = ( $openssl_bin,
		    "dgst", $algorithm_param,
		    "-binary",
		    "-sign", $private_key_file ) ;

	my ($stdin, $stdout, $stderr);

	$stdin = $tkt;
	run3 \@cmd, \$stdin, \$stdout, \$stderr;
	my $exitcode = $?;

	if ($exitcode != 0) {
		warn "pubtkt_generate failed: openssl returned exit code $exitcode, stderr = $stderr\n";
		return;
	}

	$tkt .= ";sig=" . encode_base64($stdout,""); #2nd param = no EOL.

	return $tkt;
}

sub pubtkt_verify
{
	my %args = @_;
	my $public_key_file = $args{publickey} or croak "Missing \"publickey\" parameter";
	croak "Invalid \"publickey\" value ($public_key_file): file doesn't exist/not readable"
		unless -r $public_key_file;

	my $keytype = $args{keytype} or croak "Missing \"keytype\" parameter";
	croak "Invalid \"keytype\" value ($keytype): expecting 'dsa' or 'rsa'\n"
		unless $keytype eq "dsa" || $keytype eq "rsa";
	my $algorithm_param  = ( $keytype eq "dsa" ) ? "-dss1" : "-sha1";

	my $ticket_str = $args{ticket} or croak "Missing \"ticket\" parameter";

	# Extract base64'd signature text
	my ($ticket_data, $sig_base64) = split /;sig=/, $ticket_str;
	warn "Pubtkt.pm: missing \"sig=\" in ticket ($ticket_str)" unless $sig_base64;
	return unless $sig_base64;

	# Decode base64 signature, and store in a temporary file
	my $sig_bin = decode_base64($sig_base64);
	warn "Pubtkt.pm: invalid base64 signature from ticket ($ticket_str)" unless length($sig_bin)>0;

	my ($fh, $temp_sig_file) = tempfile("pubtkt.XXXXXXXXX", DIR => ($args{"tempdir"} || "/tmp"), UNLINK => 1);
	print $fh $sig_bin or die "Failed to write signature data: $!";
	close $fh or die "Failed to write signature data: $!";

	# verify signature using openssl
	my @cmd = ( $openssl_bin,
		    "dgst", $algorithm_param,
		    "-verify", $public_key_file,
		    "-signature", $temp_sig_file);
	my ($stdin, $stdout, $stderr);
	$stdin = $ticket_data;
	run3 \@cmd, \$stdin, \$stdout, \$stderr;
	my $exitcode = $?;
	unlink($temp_sig_file);
	return unless $exitcode == 0;

	return 1 if ( $stdout eq "Verified OK\n" ) ;

	return ;
}

sub pubtkt_parse
{
	my $tkt = shift or croak "missing ticket string parameter";
	my @fields = split /;/, $tkt;
	my %values = map { split (/=/, $_, 2) } @fields;
	return %values;
}

1;
