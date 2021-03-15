package Ravada::Auth::SSO;

use strict;
use warnings;

use Data::Dumper;
use Authen::ModAuthPubTkt;
use URI::Escape;
use LWP::UserAgent;

=head1 NAME

Ravada::Auth::SSO - SSO library for Ravada

=cut

use Moose;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

sub BUILD {
    my $self = shift;
    my ($params) = @_;
    die 'ERROR: Ticket not found'
        if !$params->{ticket};
    $self->{ticket} = $params->{ticket};
    $self->{logoutURL} = sprintf('%s/logout?service=%s', $$CONFIG->{sso}->{url}, uri_escape($$CONFIG->{sso}->{service})) if ($$CONFIG->{sso}->{logout});
    die sprintf('ERROR: Login failed %s', $self->name)
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
    eval { $cookie = Authen::ModAuthPubTkt::pubtkt_generate(privatekey => $$CONFIG->{sso}->{cookie}->{priv_key}, keytype => $$CONFIG->{sso}->{cookie}->{type}, userid => $name, validuntil => time() + $$CONFIG->{sso}->{cookie}->{timeout}); };
    return $cookie;
}

sub _get_session_userid_by_ticket
{
    my ($cookie) = @_;
    my $result;
    eval { $result = Authen::ModAuthPubTkt::pubtkt_verify(publickey => $$CONFIG->{sso}->{cookie}->{pub_key}, keytype => $$CONFIG->{sso}->{cookie}->{type}, ticket => $cookie); };
    die $@ ? $@ : 'Cannot validate ticket' if ((! $result) || ($@));
    my %data = Authen::ModAuthPubTkt::pubtkt_parse($cookie);
    die 'Ticket is expired' if ($data{validuntil} < time());
    return $data{uid};
}

sub _validate_ticket
{
    my ($ticket) = @_;
    my $response = LWP::UserAgent->new->get(sprintf('%s/serviceValidate?service=%s&ticket=%s', $$CONFIG->{sso}->{url}, uri_escape($$CONFIG->{sso}->{service}), uri_escape($ticket)));
    return $1 if ($response->content =~ /<cas:user>(.+)<\/cas:user>/);
    die sprintf('Ticket validation error: %s', $response->content);
}

sub login($self) {
    my $userid = _get_session_userid_by_ticket($self->{ticket});
    die 'Ticket user id do not coincides with received user id' if ($self->name ne $userid);
    return $self->name;
}

sub login_external($ticket, $cookie) {
    if ($ticket) {
        my $name = _validate_ticket($ticket);
        my $self = Ravada::Auth::SSO->new(name => $name, ticket => _generate_session_ticket($name));
        return $self;
    } elsif ($cookie) {
        my $name = _get_session_userid_by_ticket($cookie);
        my $self = Ravada::Auth::SSO->new(name => $name, ticket => $cookie);
        return $self;
    } else {
        return { redirectTo => sprintf('%s/login?service=%s', $$CONFIG->{sso}->{url}, uri_escape($$CONFIG->{sso}->{service})) };
    }
}

sub is_admin { }

sub is_external { }

sub init { }

1;
