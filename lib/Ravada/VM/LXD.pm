package Ravada::VM::LXD;

use IO::Socket::Unix;
use JSON::XS;
use Moose;

use Ravada::Domain::LXD;

with 'Ravada::VM';

our $SOCKET_LXD;
our $CONNECTOR = \$Ravada::CONNECTOR;

our $DEFAULT_SOCKET_LXD = '/var/lib/lxd/unix.socket';

sub BUILD {
    my $self = shift;

    $self->connect()                if !defined $SOCKET_LXD;
    die "No LXD backend found\n"    if !$SOCKET_LXD;
}

sub connect {
    $SOCKET_LXD = $DEFAULT_SOCKET_LXD;
}

sub _connect_socket {
    my $client = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Peer => $SOCKET_LXD,
    );
    return $client;
}

sub create_domain {
    my $client = _connect_socket();
    my $data = {
        name => 'mynew',
        architecture => 'i686',
        profiles => ['default'],
        ephemeral => 0,
        source => {
            type => 'image',
            alias => 'ubuntu/devel'
        }

    };
    $client->send(
}

sub create_volume {}

sub list_domains {
    return ()   if wantarray;
    return 0;
}

sub search_domain {}
sub search_domain_by_id {}

1;
