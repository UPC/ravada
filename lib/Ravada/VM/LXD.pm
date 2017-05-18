package Ravada::VM::LXD;

use Data::Dumper;
use IPC::Run3;
use IO::Socket::UNIX;
use JSON::XS qw(decode_json encode_json);
use Moose;
use REST::Client;

use Ravada::Domain::LXD;

with 'Ravada::VM';

#our $SOCKET_LXD;
#our $CONNECTOR = \$Ravada::CONNECTOR;

#our $DEFAULT_SOCKET_LXD = '/var/lib/lxd/unix.socket';
#our $CURL;
our $DEFAULT_URL_LXD = "https://localhost:8443";
our $LXC;
our $LXD;
our $URL_LXD;
our $SOCK_PATH = '/var/lib/lxd/unix.socket';

sub BUILD {
    my $self = shift;

    $self->{_connection} = '';
    $self->connect();                #if !defined $SOCKET_LXD;
    #die "No LXD backend found\n"    if !$URL_LXD;
#    die "Missing curl\n"            if !$CURL;
#    die "Missing lxc\n"             if !$LXC;
#    die "Missing lxd\n"             if !$LXD;
}

sub connect {
    my $self = shift;

    return $self->_connect_http if $self->{_connection} eq 'http';
    return $self->_connect_socket if $self->{_connection} eq 'socket';

    my $client = $self->_connect_http;
    return $self->_connect_socket() if $self->host eq 'localhost' || $self->host eq '127.0.0.1';
}

sub _connect_http {
    my $self = shift;
    $LXC = `which lxc`;
    chomp $LXC;

    $LXD = `which lxd`;
    chomp $LXD;

    $URL_LXD = $DEFAULT_URL_LXD;
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
    my $client = REST::Client->new();
    die if !$client;

    #$client->addHeader('Content-Type', 'application/json');
    #$client->addHeader('charset', 'UTF-8');
    #$client->addHeader('Accept', 'application/json');

    # Try SSL_verify_mode => SSL_VERIFY_NONE.  0 is more compatible, but may be deprecated
    $client->getUseragent()->ssl_opts( SSL_verify_mode => 0 );
    #A host can be set for convienience
    $client->setHost($URL_LXD);
    #X509 client authentication

    $client->setCert(glob('~/.config/lxc/client.crt'));
    $client->setKey(glob('~/.config/lxc/client.key'));
    # lxc config trust list
    # Add cert: lxc config trust add ~/.config/lxc/client.crt


    #add a CA to verify server certificates
    # $client->setCa('/path/to/ca.file');

    #you may set a timeout on requests, in seconds
    #$client->setTimeout(10);

    $client->GET('/1.0');#->responseContent();
    if ($client->responseCode() == 200) {
        warn "Response 200 http\n";
        #$client->GET('/1.0')->responseContent();
        #my $r = decode_json( $client->responseContent() );
        #my @a = $r->{metadata}->{auth};
        #warn "   Certificate:        " . join( ", ", @a ) . "\n";
        $self->{_connection} = 'http';
        return $client;
    }
    warn "Server $URL_LXD didn't answer (TODO read setHost) code: ".$client->responseCode."\n";
}

sub _connect_socket {
    my $self = shift;

    my $client = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Peer => $SOCK_PATH,
    );
    print $client
        "GET /1.0/containers HTTP/1.1\n"
        ."Host: 127.0.0.1\n"
        ."\n";
    my $line = <$client>;
    chomp $line;
    die $line if $line !~ / 200 OK/;
    $self->{_connection} = 'socket';
    warn "Response 200 socket\n";
    return $client;
}

sub create_domain {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} or confess "Missing domain name: name => 'somename'";

    # connect each time, it is painless and the socket may close
    my $client = $self->connect();
#    my $data = {
#        name => $name,
##        architecture => 'i686',
##        profiles => ['default'],
##        ephemeral => 0,
#        source => {
#            type => 'image',
#            alias => 'ubuntu'
#        }

#    };
#    my $json_data = encode_json($data);
#    my @cmd = ( $CURL,
#        '-s',
#        '--unix-socket', $SOCKET_LXD
#        ,'-X', 'POST'
#        ,'-d', $json_data
#        ,'a/1.0/containers'
#    );
#    my ($in, $json_out, $err);
#    run3(\@cmd,\$in, \$json_out, \$err);
##    warn "OUT=$json_out\n"   if $json_out;
#    warn "ERR=$err\n"   if $err;

#    my $out = decode_json($json_out);

#    my $domain = Ravada::Domain::LXD->new( 
#       domain => $name
#        ,name => $name
#    );
#    $domain->_insert_db( name => $name);
#    return $domain;

}

sub _create_domain_socket {
    my $self = shift;
    my %args = @_;
    my $client = $self->_connect_socket();
    $args{name} = 'KAKA';

    warn "create domain $args{name}\n";
    my $data = {
        name => $args{name}
#        ,ephemeral => 'true'
        ,config => {
            #           'limit.cpu' => "2"
        }
        ,source => {
            type => 'image'
            ,mode => 'pull'
            ,protocol => 'simplestreams'
            ,server => 'https://cloud-images.ubuntu.com/releases'
            ,alias => '17.04'
        }
    };
    my @cmd = ("curl","-s","--unix-socket",$SOCK_PATH,
        ,"-X","POST",
        ,"-d",encode_json($data)
        ,"a/1.0/containers")
    ;
    warn @cmd;
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);
    warn Dumper(decode_json($out));
}

sub _create_domain_http {
    my $self = shift;
    my %args = @_;
    my $client = $self->_connect_http();

    warn "create domain $args{name}\n";
    my $data = {
        name => $args{name}
        ,architecture => 'x86_64',
#        ,ephemeral => 'true'
        ,config => {
            #           'limit.cpu' => "2"
        }
        ,source => {
            type => 'image'
            ,mode => 'pull'
            ,protocol => 'simplestreams'
            ,server => 'https://cloud-images.ubuntu.com/releases'
            ,alias => '17.04'
        }
    };
    $client->POST('/1.0/containers',encode_json($data))->responseContent();
    warn Dumper(decode_json( $client->responseContent() ));
}

sub remove_domain {
#    my $self = shift;
#    my $name = shift;
#    warn "Removing domain $name";
}

sub create_volume {}

sub list_domains {
#    my $self = shift;
#
#    my @cmd = ($LXC,'list');
#    my ($in, $out, $err);
#    run3(\@cmd, \$in, \$out, \$err);
#
#    my @list;
#
#    for my $line ( split /\n/,$out ) {
#        next if $line =~ m{^.----};
#        next if $line =~ m{NAME};
#        my ($name) = $line =~ m{([\w\d-]+)};
#        next if !$name;
#        my $domain = Ravada::Domain::LXD->new( domain => $name);
#        push @list,($domain);
#    }

#    return @list   if wantarray;
#    return scalar(@list)-1;
}

sub search_domain {}

sub search_domain_by_id {}

sub disconnect {}

1;
