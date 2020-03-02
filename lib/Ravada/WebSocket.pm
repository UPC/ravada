package Ravada::WebSocket;

use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw( lock_hash unlock_hash);
use Moose;

no warnings "experimental::signatures";
use feature qw(signatures);

my $DEBUG=0;

has clients => (
    is => 'ro'
    ,isa => 'HashRef'
    ,default => sub { return {}}
);

has ravada => (
    is => 'ro'
    ,isa => 'Ravada::Front'
    ,required => 1
);

my %SUB = (
                  list_alerts => \&_list_alerts
                  ,list_isos  => \&_list_isos
                  ,list_nodes => \&_list_nodes
               ,list_machines => \&_list_machines
          ,list_machines_user => \&_list_machines_user
        ,list_bases_anonymous => \&_list_bases_anonymous
               ,list_requests => \&_list_requests
                ,machine_info => \&_get_machine_info
                ,ping_backend => \&_ping_backend
                     ,request => \&_request
);

######################################################################


sub _list_alerts($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    my $ret_old = $args->{ret};
    my @ret = map { $_->{time} = time; $_ } $user->unshown_messages();

    my @ret2=();

    my %new;
    for my $alert (@ret) {
        my $cmd_machine = $alert->{subject};
        $cmd_machine =~ s{(.*?\s.*?)\s+.*}{$1};
        $new{$cmd_machine}++;
    }

    for my $alert (@$ret_old) {
        my $cmd_machine = $alert->{subject};
        $cmd_machine =~ s{(.*?\s.*?)\s+.*}{$1};
        push @ret2,($alert) if time - $alert->{time} < 10
            && $cmd_machine && !$new{$cmd_machine};
    }

    return [@ret2,@ret];
}

sub _list_isos($rvd, $args) {
    my ($type) = $args->{channel} =~ m{/(.*)};
    $type = 'KVM' if !defined $type;

    return $rvd->iso_file($type);
}

sub _list_nodes($rvd, $args) {
    my ($type) = $args->{channel} =~ m{/(.*)};
    my @nodes = $rvd->list_vms($type);
    return \@nodes;
}

sub _request($rvd, $args) {
    my ($id_request) = $args->{channel} =~ m{/(.*)};
    my $req = Ravada::Request->open($id_request);
    my $command_text = $req->command;
    $command_text =~ s/_/ /g;
    return {command => $req->command, command_text => $command_text
            ,status => $req->status, error => $req->error};
}

sub _list_machines($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login)
        or die "Error: uknown user $login";
    return []
        unless (
            $user->can_list_machines
            || $user->can_list_own_machines()
            || $user->can_list_clones()
            || $user->can_list_clones_from_own_base()
            || $user->is_admin()
        );
    return $rvd->list_machines($user);
}

sub _list_machines_user($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login)
        or die "Error: uknown user $login";

    my $client = $args->{client};
    my $ret = $rvd->list_machines_user($user, {client => $client});
    return $ret;
}

sub _list_bases_anonymous($rvd, $args) {
    my $remote_ip = $args->{remote_ip} or die "Error: no remote_ip arg ".Dumper($args);
    return $rvd->list_bases_anonymous($remote_ip);
}


sub _list_requests($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";
    return [] unless $user->is_operator || $user->is_admin;
    return $rvd->list_requests;
}

sub _get_machine_info($rvd, $args) {
    my ($id_domain) = $args->{channel} =~ m{/(\d+)};
    my $domain = $rvd->search_domain_by_id($id_domain) or do {
        warn "Error: domain $id_domain not found.";
        return {};
    };


    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    my $info = $domain->info($user);
    if ($info->{is_active} && !$info->{ip}) {
       Ravada::Request->refresh_machine(id_domain => $info->{id}, uid => $user->id);
    }

    return $info;
}

sub _list_recent_requests($rvd, $seconds) {
    my @now = localtime(time-$seconds);
    $now[4]++;
    for (0 .. 4) {
        $now[$_] = "0".$now[$_] if length($now[$_])<2;
    }
    my $time_recent = ($now[5]+=1900)."-".$now[4]."-".$now[3]
        ." ".$now[2].":".$now[1].":".$now[0];
    my $sth = $rvd->_dbh->prepare(
        "SELECT id,command, status "
        ." FROM requests "
        ." WHERE "
        ."  date_changed >= ? "
        ." ORDER BY date_changed "
    );
    $sth->execute($time_recent);
    my @reqs;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @reqs,($row);
    }
    return @reqs;
}

sub _ping_backend($rvd, $args) {
    my @reqs = _list_recent_requests($rvd, 20);

    my $requested = scalar( grep { $_->{status} eq 'requested' } @reqs );

    # If there are requests in state different that requested it's ok
    return 1 if scalar(@reqs) > $requested;

    my ($ping_backend)
    = grep {
        $_->{command} eq 'ping_backend'
    } @reqs ;

    if (!$ping_backend) {
        return 0 if $requested;
        my @now = localtime(time);
        my $seconds = $now[0];
        Ravada::Request->ping_backend() if $seconds < 5;
        return 1;
    }

    return 0 if $ping_backend->{status} eq 'requested';

    return 1;
}

sub _different_list($list1, $list2) {
    return 1 if scalar(@$list1) != scalar (@$list2);
    for my $i (0 .. scalar(@$list1)-1) {
        my $h1 = $list1->[$i];
        my $h2 = $list2->[$i];
        return 1 if _different($h1, $h2);
   }
    return 0;
}

sub _different_hash($h1,$h2) {
    return 1 if keys %$h1 != keys %$h2;
    for my $key (keys %$h1) {
        next if !defined $h1->{$key} && !defined $h2->{$key};
        if (!exists $h2->{$key}
            || !defined $h1->{$key} && defined $h2->{$key}
            || defined $h1->{$key} && !defined $h2->{$key}
            || _different($h1->{$key}, $h2->{$key})) {
            return 1;
        }
    }
    return 0;
}
sub _different($var1, $var2) {
    return 1 if !defined $var1 &&  defined $var2;
    return 1 if  defined $var1 && !defined $var2;
    return 1 if ref($var1) ne ref($var2);
    return _different_list($var1, $var2) if ref($var1) eq 'ARRAY';
    return _different_hash($var1, $var2) if ref($var1) eq 'HASH';
    return $var1 ne $var2;
}

sub BUILD {
    my $self = shift;
    Mojo::IOLoop->recurring(1 => sub {
            for my $key ( keys %{$self->clients} ) {
                my $ws_client = $self->clients->{$key}->{ws};
                my $channel = $self->clients->{$key}->{channel};

                $channel =~ s{/.*}{};
                my $exec = $SUB{$channel} or die "Error: unknown channel $channel";

                $self->ravada->_dbh_disconnect();
                my $ret = $exec->($self->ravada, $self->clients->{$key});
                my $old_ret = $self->clients->{$key}->{ret};
                if ( _different($ret, $old_ret )) {
                    warn "WS: send $channel" if $DEBUG;
                    $ws_client->send( { json => $ret } );
                    $self->clients->{$key}->{ret} = $ret;
                }
            }
        });

}

sub _list_machines_fast($self, $ws, $login) {
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";
    my $ret0 = $self->ravada->list_domains();

    my @ret;
    for my $dom (@$ret0) {
        next if !$user->is_admin && $dom->{id_owner} != $user->id;
        $dom->{can_start} = 1;
        $dom->{can_view} = 1;
        $dom->{can_manage} = 1;
        push @ret,($dom) if !$dom->{id_base};
    }
    $ws->send( { json => \@ret } );

}

sub subscribe($self, %args) {
    my $ws = $args{ws};
    my %args2 = %args;
    delete $args2{ws};
    warn "Subscribe ".Dumper(\%args2) if $DEBUG;
    $self->ravada->_dbh_disconnect();
    $self->clients->{$ws} = {
        ws => $ws
        , %args
        , ret => undef
    };
    if ( $args{channel} eq 'list_machines' && $0 !~ /\.t$/) {
        $self->_list_machines_fast($ws, $args{login})
    }
}

sub unsubscribe($self, $ws) {
    delete $self->clients->{$ws};
}

1;
