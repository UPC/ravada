package Ravada::VM::LXD;

use Data::Dumper;
use IPC::Run3;
use JSON::XS qw(decode_json encode_json);
use Moose;

use Ravada::Domain::LXD;

with 'Ravada::VM';

our $SOCKET_LXD;
our $CONNECTOR = \$Ravada::CONNECTOR;

our $DEFAULT_SOCKET_LXD = '/var/lib/lxd/unix.socket';
our $CURL;
our $LXC;

sub BUILD {
    my $self = shift;

    $self->connect()                if !defined $SOCKET_LXD;
    die "No LXD backend found\n"    if !$SOCKET_LXD;
    die "Missing curl\n"            if !$CURL;
    die "Missing lxc\n"             if !$LXC;
}

sub connect {
    $CURL = `which curl`;
    chomp $CURL;

    $LXC = `which lxc`;
    chomp $LXC;

    $SOCKET_LXD = $DEFAULT_SOCKET_LXD;
}

sub create_domain {
    my $self = shift;
    my %args = @_;

    my $name = $args{name} or confess "Missing domain name: name => 'somename'";

    my $data = {
        name => $name,
#        architecture => 'i686',
#        profiles => ['default'],
#        ephemeral => 0,
        source => {
            type => 'image',
            alias => 'ubuntu'
        }

    };
    my $json_data = encode_json($data);
    my @cmd = ( $CURL,
        '-s',
        '--unix-socket', $SOCKET_LXD
        ,'-X', 'POST'
        ,'-d', $json_data
        ,'a/1.0/containers'
    );
    my ($in, $json_out, $err);
    run3(\@cmd,\$in, \$json_out, \$err);
#    warn "OUT=$json_out\n"   if $json_out;
    warn "ERR=$err\n"   if $err;

    my $out = decode_json($json_out);

    my $domain = Ravada::Domain::LXD->new( 
       domain => $name
        ,name => $name
    );
    $domain->_insert_db( name => $name);
    return $domain;

}

sub remove_domain {
    my $self = shift;
    my $name = shift;
    warn "Removing domain $name";
}

sub create_volume {}

sub list_domains {
    my $self = shift;

    my @cmd = ($LXC,'list');
    my ($in, $out, $err);
    run3(\@cmd, \$in, \$out, \$err);

    my @list;

    for my $line ( split /\n/,$out ) {
        next if $line =~ m{^.----};
        next if $line =~ m{NAME};
        my ($name) = $line =~ m{([\w\d-]+)};
        next if !$name;
        my $domain = Ravada::Domain::LXD->new( domain => $name);
        push @list,($domain);
    }

    return @list   if wantarray;
    return scalar(@list)-1;
}

sub search_domain {}
sub search_domain_by_id {}

1;
