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
use feature qw(signatures state);

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;
our $ERR;

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

sub _check_user_profile {
    my $self = shift;
    my $user_sql = Ravada::Auth::SQL->new(name => $self->name);
    if ( $user_sql->id ) {
        if ($user_sql->external_auth ne 'sso') {
            $user_sql->external_auth('sso');
        }
        return;
    }

    return if ! Ravada::Front::setting(undef,'/frontend/auto_create_users');

    Ravada::Auth::SQL::add_user(name => $self->name, is_external => 1, is_temporary => 0
        , external_auth => 'sso');
}

sub _generate_session_ticket
{
    my ($name) = @_;
    my $cookie;
    die 'Can\'t read privkey file (sso->cookie->priv_key value at ravada.conf file)' if (! -r $$CONFIG->{sso}->{cookie}->{priv_key});
    eval { $cookie = Authen::ModAuthPubTkt::pubtkt_generate(privatekey => $$CONFIG->{sso}->{cookie}->{priv_key}, keytype => $$CONFIG->{sso}->{cookie}->{type}, userid => $name, validuntil => time() + $$CONFIG->{sso}->{cookie}->{timeout}); };
    return $cookie;
}

sub _get_session_userid_by_ticket
{
    my ($cookie) = @_;
    my $result;
    die 'Can\'t read pubkey file (sso->cookie->pub_key value at ravada.conf file)' if (! -r $$CONFIG->{sso}->{cookie}->{pub_key});

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
    if ($cookie) {
        my $name = _get_session_userid_by_ticket($cookie);
        my $self = Ravada::Auth::SSO->new(name => $name, ticket => $cookie);
        $self->_check_user_profile();
        return $self;
    } elsif ($ticket) {
        my $name = _validate_ticket($ticket);
        my $self = Ravada::Auth::SSO->new(name => $name, ticket => _generate_session_ticket($name));
        $self->_check_user_profile();
        return $self;
    } else {
        return { redirectTo => sprintf('%s/login?service=%s', $$CONFIG->{sso}->{url}, uri_escape($$CONFIG->{sso}->{service})) };
    }
}

sub is_admin { }

sub is_external { }

sub init {
    state $warn = 0;
    if (exists $$CONFIG->{sso} && $$CONFIG->{sso} ) {
        for my $field (qw(url service cookie)) {
            if ( !exists $$CONFIG->{sso}->{$field} ) {
                $ERR = "Error: Missing sso / $field in config file\n";
                warn $ERR unless $warn++;
                return 0;
            }
        }
        if (!$$CONFIG->{sso}->{cookie}->{type}) {
            $ERR = "Error: missing sso / cookie / type in config file\n";
            warn $ERR unless $warn++;
            return 0;
        }
        for my $field (qw(priv_key pub_key)) {
            if ( !exists $$CONFIG->{sso}->{cookie}->{$field}
            || ! $$CONFIG->{sso}->{cookie}->{$field}) {
                $ERR = "Error: Missing sso / cookie / $field in config file\n";
                warn $ERR unless $warn++;
                return 0;
            }
            my $file = $$CONFIG->{sso}->{cookie}->{$field};
            if (! -e $file) {
                $ERR = "Error: Missing or unreadable file $file\n";
                warn $ERR unless $warn++;
                return 0;

            }

        }
        return 1;
    }
    return 0;
}

1;
