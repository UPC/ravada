package Ravada::WebSocket;

use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw( lock_hash unlock_hash);
use Moose;
no warnings "experimental::signatures";
use feature qw(signatures);

my $DEBUG=0;
my $T0 = time;

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
                  ,list_bases => \&_list_bases
                  ,list_isos  => \&_list_isos
                  ,list_nodes => \&_list_nodes
               ,list_machines => \&_list_machines
          ,list_machines_tree => \&_list_machines_tree
          ,list_machines_user => \&_list_machines_user
          ,list_machines_user_including_privates => \&_list_machines_user_including_privates
        ,list_bases_anonymous => \&_list_bases_anonymous
               ,list_requests => \&_list_requests
                ,machine_info => \&_get_machine_info
                   ,node_info => \&_get_node_info
                ,ping_backend => \&_ping_backend
                     ,request => \&_request

# bookings
                 ,list_next_bookings_today => \&_list_next_bookings_today
);

our %TABLE_CHANNEL = (
    list_alerts => 'messages'
    ,list_machines => 'domains'
    ,list_machines_tree => 'domains'
    ,list_machines_user_including_privates => ['domains','bookings','booking_entries'
        ,'booking_entry_ldap_groups', 'booking_entry_users','booking_entry_bases']
    ,list_requests => 'requests'
);

my $A_WHILE;
my $LIST_MACHINES_FIRST_TIME = 1;
my $TZ;
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

sub _list_bases($rvd, $args) {
    my $domains = $rvd->list_bases();
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";
    my @domains_show = @$domains;
    if (!$user->is_admin) {
        @domains_show = ();
        for (@$domains) {
            push @domains_show,($_) if $_->{is_public};
        }
    }
    return \@domains_show;
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
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login);

    my ($id_request) = $args->{channel} =~ m{/(.*)};
    my $req = Ravada::Request->open($id_request);
    my $command_text = $req->command;
    $command_text =~ s/_/ /g;

    my $info = $req->info($user);
    $info->{command_text} = $command_text;

    return $info;
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

    if ($LIST_MACHINES_FIRST_TIME) {
        $LIST_MACHINES_FIRST_TIME = 0;
        return $rvd->list_machines($user, id_base => undef);
    }

    return $rvd->list_machines($user);
}
sub _list_children($list_orig, $list, $level=0) {
    my @list2;
    for my $item (sort {$a->{name} cmp $b->{name} } @$list) {
        unlock_hash(%$item);
        $item->{_level} = $level;
        push @list2,($item);
        my @children = grep { defined($_->{id_base}) && $_->{id_base} == $item->{id} }
                        @$list_orig;
        if ( scalar(@children) ) {
            my @children2 = _list_children($list_orig,\@children, $level+1);
            push @list2,(@children2);
            $item->{has_clones} = scalar @children2;
        } else {
            $item->{has_clones} = 0;
        }
        lock_hash(%$item);
    }
    return @list2;
}

sub _list_machines_tree($rvd, $args) {
    my $list_orig = _list_machines($rvd, $args);
    my @list = sort { lc($a->{name}) cmp lc($b->{name}) }
                grep {!exists($_->{id_base}) || !$_->{id_base} }
                @$list_orig;
    return [_list_children($list_orig, \@list)];
}

sub _list_machines_user($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login)
        or die "Error: uknown user $login";

    my $client = $args->{client};
    my $ret = $rvd->list_machines_user($user, {client => $client});
    return $ret;
}

sub _list_machines_user_including_privates($rvd, $args) {
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
    if ($info->{is_active} && ( !exists $info->{ip} || !$info->{ip})) {
       Ravada::Request->refresh_machine(id_domain => $info->{id}, uid => $user->id);
    }

    return $info;
}

sub _get_node_info($rvd, $args) {
    my ($id_node) = $args->{channel} =~ m{/(\d+)};
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    return {} if!$user->is_admin;

    my $node = Ravada::VM->open(id => $id_node, readonly => 1);
    $node->_data('hostname');
    $node->{_data}->{is_local} = $node->is_local;
    $node->{_data}->{has_bases} = scalar($node->list_bases);
    return $node->{_data};

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
        "SELECT id,command, status,date_req "
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
    my @reqs = _list_recent_requests($rvd, 120);

    my $requested = scalar( grep { $_->{status} eq 'requested' } @reqs );

    # If there are requests in state different that requested it's ok
    if ( scalar(@reqs) > $requested ) {
        _its_been_a_while(1);
        return 2;
    }

    my ($ping_backend)
    = grep {
        $_->{command} eq 'ping_backend'
    } @reqs ;

    if (!$ping_backend) {
        return 0 if $requested && _its_been_a_while();
        my @now = localtime(time);
        my $seconds = $now[0];
        Ravada::Request->ping_backend() if $seconds < 5;
        return 1;
    }

    if ($ping_backend->{status} eq 'requested') {
        return 0 if _its_been_a_while();
        return 1;
    }

    _its_been_a_while(1);
    return 1;
}

sub _now {
     return DateTime->from_epoch( epoch => time() , time_zone => $TZ )
}

sub _list_next_bookings_today($rvd, $args) {

    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my @ret = Ravada::Booking::bookings_range(
        time_start => _now()->add(seconds => 1)->hms
        , show_user_allowed => $login
    );
    return \@ret;
}

sub _its_been_a_while($reset=0) {
    if ($reset) {
        $A_WHILE = 0;
    }
    if (!$A_WHILE) {
        $A_WHILE = time;
        return 0;
    }
    return time - $A_WHILE > 5;
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
    for my $key (keys %$h1) {
        next if exists $h1->{$key} && exists $h2->{$key}
        && !defined $h1->{$key} && !defined $h2->{$key};
        if (!exists $h2->{$key}
            || !defined $h1->{$key} && defined $h2->{$key}
            || defined $h1->{$key} && !defined $h2->{$key}
            || _different($h1->{$key}, $h2->{$key})) {
            unlock_hash(%$h1);
            lock_hash(%$h1);
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

    $TZ = DateTime::TimeZone->new(name => $self->ravada->settings_global()
        ->{backend}->{time_zone}->{value})
    if !defined $TZ;

    Mojo::IOLoop->recurring(1 => sub {
            for my $key ( keys %{$self->clients} ) {
                my $ws_client = $self->clients->{$key}->{ws};
                my $channel = $self->clients->{$key}->{channel};
                _send_answer($self, $ws_client, $channel, $key);
            }
        });

}

sub _old_info($self, $key, $new_count=undef, $new_changed=undef) {
    my $args = $self->clients->{$key};

    $args->{"_count_$key"} = $new_count if defined $new_count;
    $args->{"_changed_$key"} = $new_changed if defined $new_changed;

    my $old_count = ($args->{"_count_$key"}  or 0 );
    my $old_changed = ($args->{"_changed_$key"}  or '' );

    return ($old_count, $old_changed);
}

sub _date_changed_table($self, $table) {
    my $rvd = $self->ravada;
    my $sth = $rvd->_dbh->prepare("SELECT MAX(date_changed) FROM $table");
    $sth->execute;
    my ($date) = $sth->fetchrow;
    return ($date or '');
}

sub _count_table($self, $table) {
    my $rvd = $self->ravada;
    my $sth = $rvd->_dbh->prepare("SELECT count(*) FROM $table");
    $sth->execute;
    my ($count) = $sth->fetchrow;
    return $count;
}


sub _new_info($self, $key) {
    my $channel = $self->clients->{$key}->{channel};
    $channel =~ s{/.*}{};

    my $table0 = $TABLE_CHANNEL{$channel} or return;
    if (!ref($table0)) {
        $table0 = [$table0];
    }

    my $count = '';
    my $date = '';

    for my $table (@$table0) {
        $count .= ":" if $count;
        $count .= $self->_count_table($table);

        $date .= ":" if $date;
        $date .= $self->_date_changed_table($table)
    }
    return ($count, $date);

}

sub _send_answer($self, $ws_client, $channel, $key = $ws_client) {
    $channel =~ s{/.*}{};
    my $exec = $SUB{$channel} or die "Error: unknown channel $channel";

    my $old_ret = $self->clients->{$key}->{ret};
    my ($old_count, $old_changed) = $self->_old_info($key);
    my ($new_count, $new_changed) = $self->_new_info($key);

    return $old_ret if defined $new_count && defined $new_changed
    && $old_count eq $new_count && $old_changed eq $new_changed;

    $self->_old_info($key, $new_count, $new_changed)
    unless $channel =~ /list_machines/ && $LIST_MACHINES_FIRST_TIME;

    my $ret = $exec->($self->ravada, $self->clients->{$key});

    if ( _different($ret, $old_ret )) {

        warn "WS: send $channel" if $DEBUG;
        $ws_client->send( { json => $ret } );
        $self->clients->{$key}->{ret} = $ret;
    }
    $self->unsubscribe($key) if $channel eq 'ping_backend' && $ret eq 2;
}

sub subscribe($self, %args) {
    my $ws = $args{ws};
    my %args2 = %args;
    delete $args2{ws};
    warn "Subscribe ".Dumper(\%args2) if $DEBUG;
    $self->clients->{$ws} = {
        ws => $ws
        , %args
        , ret => undef
    };
    if ($args{channel} =~ /list_machines/) {
        $LIST_MACHINES_FIRST_TIME = 1 ;
    }
    $self->_send_answer($ws,$args{channel});
}

sub unsubscribe($self, $ws) {
    delete $self->clients->{$ws};
}

1;
