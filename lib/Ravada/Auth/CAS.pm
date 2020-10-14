package Ravada::Auth::CAS;

use strict;
use warnings;

use Data::Dumper;
use LibCAS::Client;
use Ravada::ModAuthPubTkt;

=head1 NAME

Ravada::Auth::CAS - CAS library for Ravada

=cut

use LibCAS::Client;

use Moose;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

sub BUILD {
    my $self = shift;
    my ($params) = @_;
    die "ERROR: Ticket not found"
        if !$params->{ticket};
    $self->{ticket} = $params->{ticket};
    die "ERROR: Login failed '".$self->name."'"
        if !$self->login;
    return $self;
}

sub add_user($name, $password, $storage='rfc2307', $algorithm=undef) { }

sub remove_user { }

sub search_user { }

sub _generate_session_ticket
{
    my ($name) = @_;
    my $cookie;
    eval { $cookie = Ravada::ModAuthPubTkt::pubtkt_generate(privatekey => $$CONFIG->{cas}->{cookie}->{priv_key}, keytype => $$CONFIG->{cas}->{cookie}->{type}, userid => $name, validuntil => time() + $$CONFIG->{cas}->{cookie}->{timeout}); };
    return $cookie;
}

sub _get_session_userid_by_ticket
{
    my ($cookie) = @_;
    my $result;
    eval { $result = Ravada::ModAuthPubTkt::pubtkt_verify(publickey => $$CONFIG->{cas}->{cookie}->{pub_key}, keytype => $$CONFIG->{cas}->{cookie}->{type}, ticket => $cookie); };
    die $@ ? $@ : 'Cannot validate ticket' if ((! $result) || ($@));
    my %data = Ravada::ModAuthPubTkt::pubtkt_parse($cookie);
    die 'Ticket is expired' if ($data{validuntil} < time());
    return $data{uid};
}

sub login($self) {
    my $userid = _get_session_userid_by_ticket($self->{ticket});
    die 'Ticket user id do not coincides with received user id' if ($self->name ne $userid);
    return $self->name;
}

sub login_external($ticket, $cookie) {
    my $cas_client = LibCAS::Client->new(cas_url => $$CONFIG->{cas}->{url});
    if ($ticket) {
        my $result = $cas_client->service_validate(service => $$CONFIG->{cas}->{service}, ticket => $ticket);
        if ($result->is_success) {
            my $name = $1 if ($result->response =~ m/<cas:user>(.+)<\/cas:user>/);
            return undef if (! $name);
            my $self = Ravada::Auth::CAS->new(name => $name, ticket => _generate_session_ticket($name));
            return $self;
        }
        else {
            my $error;
            $error = $result->message if ($result->is_failure());
            $error = $result->error if ($result->is_error());
            die sprintf("ERROR: %s", $error || "Login failed");
        }
    } elsif ($cookie) {
        my $userid = _get_session_userid_by_ticket($cookie);
        my $self = Ravada::Auth::CAS->new(name => $userid, ticket => $cookie);
        return $self;
    } else {
        return { redirectTo => $cas_client->login_url(service => $$CONFIG->{cas}->{service}) };
    }
}

sub is_admin { }

sub is_external { }

sub init { }

1;
