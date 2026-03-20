package Ravada::WebSocket;

use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw( lock_hash unlock_hash);
use Mojo::JSON qw(decode_json);
use Moose;
use Ravada::Front::Log;

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
                  ,list_iso_images  => \&_list_iso_images
                  ,list_nodes => \&_list_nodes
           ,list_host_devices => \&_list_host_devices
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

                 ,log_active_domains => \&_log_active_domains
                 ,list_networks => \&_list_networks
);

our %TABLE_CHANNEL = (
    list_alerts => 'messages'
    ,list_machines => 'domains'
    ,list_machines_user_including_privates => ['domains','bookings','booking_entries'
        ,'booking_entry_ldap_groups', 'booking_entry_users','booking_entry_bases']
    ,list_requests => 'requests'
    ,machine_info => 'domains'
    ,log_active_domains => 'log_active_domains'
    ,list_networks => 'virtual_networks'
);

lock_hash(%TABLE_CHANNEL);

my $TZ;
######################################################################


sub _list_alerts($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    my $ret_old = $args->{ret};
    my @ret = map { $_->{time} = time; $_ } $user->unshown_messages();

    my @ret2;
    for my $alert (@$ret_old) {
        push @ret2,($alert) if time - $alert->{time} < 10
         && ! grep {defined $_->{id_request} && defined $alert->{id_request}
         && $_->{id_request} == $alert->{id_request} } @ret;
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
    my ($id_vm) = $args->{channel} =~ m{/(.*)};
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    return $rvd->iso_file($id_vm, $user->id);
}

sub _list_iso_images($rvd, $args) {
    my ($type) = $args->{channel} =~ m{/(.*)};
    $type = 'KVM' if !defined $type;

    my $images=$rvd->list_iso_images($type);
    return $images;
}

sub _list_nodes($rvd, $args) {
    my ($type) = $args->{channel} =~ m{/(.*)};
    my @nodes = $rvd->list_vms($type);
    return \@nodes;
}

sub _request_exists($rvd, $id_request) {

    my $sth = $rvd->_dbh->prepare(
        "SELECT id FROM requests WHERE id=?"
    );
    $sth->execute($id_request);
    my ($id_found) = $sth->fetchrow;
    return $id_found;
}

sub _request($rvd, $args) {
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login);

    my ($id_request) = $args->{channel} =~ m{/(.*)};
    return if ! _request_exists($rvd, $id_request);
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

    return (0,[])
        if !$user->can_view_admin_machines;

    return if exists $args->{_list_machines_last}
            && time -  $args->{_list_machines_last} < 2;

    $args->{_list_machines_time} = 0 if !$args->{_list_machines_time};
    $args->{_list_machines_last} = 0 if !$args->{_list_machines_last};

    $args->{_list_machines_time}++;

    my @id_base = (undef);

    push @id_base,(keys(%{$args->{show_clones}}))
    if exists $args->{show_clones};

    my @filter = ( id_base => \@id_base );
    push @filter,("status" => "active") if $args->{show_active};

    push @filter,("name" => $args->{show_name}) if $args->{show_name};

    if ($args->{_list_machines_time} == 1 ) {
        return (0, $rvd->list_machines($user, @filter));
    } elsif( $args->{_list_machines_time} <= 2 || $args->{_list_machines_time} > 60
        || _count_different($rvd, $args, 'domains')) {
        $args->{_list_machines_time}=2;
        return (0,$rvd->list_machines($user, @filter));
    }

    my $seconds = time - $args->{_list_machines_last} + 60;
    my $list_changed = $rvd->list_machines($user
        , date_changed => Ravada::Utils::now($seconds)
        , @filter
    );

    return (1,$list_changed);

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
        }
        lock_hash(%$item);
    }
    return @list2;
}

sub _add_show_clones_parent($rvd, $args, $id) {
    my $sth = $rvd->_dbh->prepare(
        "SELECT id_base FROM domains where id=?"
    );
    $sth->execute($id);
    my ($id_base) = $sth->fetchrow;
    if ($id_base && ! exists $args->{show_clones}->{$id_base}) {
            if (!$args->{show_clones}->{$id_base}) {
                $args->{show_clones}->{$id_base}=1;
                _add_show_clones_parent($rvd, $args, $id_base);
                delete $args->{_list_machines_time};
            }
    }

}

sub _show_clones_parents($rvd, $args, $list) {

    for my $item (@$list) {
        my $id_base = $item->{id_base};
        if ($id_base && ! exists $args->{show_clones}->{$id_base}) {
            if (!$args->{show_clones}->{$id_base}) {
                $args->{show_clones}->{$id_base}=1;
                _add_show_clones_parent($rvd, $args, $id_base);
                delete $args->{_list_machines_time};
            }
        }
    }

    return 1 if !exists $args->{_list_machines_time};
    return 0;
}

sub _list_machines_tree($rvd, $args) {
    my ($refresh,$list_orig) = _list_machines($rvd, $args);

    return if $refresh && !scalar(@$list_orig);

    if ( _show_clones_parents($rvd, $args, $list_orig)) {
        ($refresh,$list_orig) = _list_machines($rvd, $args);
    }

    $args->{_list_machines_last} = time;

    return {action => 'refresh'
        , data => $list_orig
        , n_active => _count_domains_active($rvd)
    } if $refresh;

    my @list = sort { lc($a->{name}) cmp lc($b->{name}) }
                grep {!exists($_->{id_base}) || !$_->{id_base} }
                @$list_orig;
    my @ordered = _list_children($list_orig, \@list);
    return { 'action' => 'new'
        , data => \@ordered
        , n_active => _count_domains_active($rvd)
    };
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

sub _list_host_devices($rvd, $args) {
    my ($id_vm) = $args->{channel} =~ m{/(\d+)};

    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login)
        or die "Error: uknown user $login";

    my $sth = $rvd->_dbh->prepare( "SELECT id,name,list_command,list_filter,devices_node,date_changed "
        ." FROM host_devices WHERE id_vm=?");

    $sth->execute($id_vm);

    my @found;
    while (my $row = $sth->fetchrow_hashref) {
        _list_domains_with_device($rvd, $row);
        _list_devices_node($rvd, $row);
        push @found, $row;
        next unless _its_been_a_while_channel($args);
        my $req = Ravada::Request->list_host_devices(
            uid => $user->id
            ,id_host_device => $row->{id}
        );
    }
    return \@found;
}

sub _list_devices_node($rvd, $row) {
    my $devices = {};
    eval {
    $devices = decode_json($row->{devices_node}) if $row->{devices_node};
    };
    warn "Warning: $@ $row->{devices_node}" if $@;
    $row->{_n_devices}=0;

    my %ret;
    my %attached = _list_devices_attached($rvd);
    if (%$devices) {
        $row->{_nodes} = [sort keys %{$devices}];
        for (@{$row->{_nodes}}) {
            my $current = $devices->{$_};
            if (ref($current) eq 'ARRAY') {
                $row->{_n_devices} += scalar(@{$devices->{$_}});
            } elsif (ref($current) eq 'HASH') {
                $row->{_n_devices} += scalar(@{$devices->{$_}->{list}});
            }
        }
        $row->{_loading} = 0;
        for my $id_node ( keys %$devices ) {
            my @devs;
            my $current = $devices->{$id_node};
            my $error =  '';
            if (ref($current) eq 'HASH') {
                $current = $devices->{$id_node}->{list};
                $error = ($devices->{$id_node}->{error} or '');
            }
            for my $name ( @$current ) {
                my $dev = { name => $name };

                $dev->{domain} = $attached{"$id_node.$name"}
                if exists $attached{"$id_node.$name"};

                push @devs,($dev);
            }
            $ret{$id_node} = {error => $error , list => \@devs};
        }
    } else {
        $row->{_nodes} = [];
    }

    $row->{devices_node} = \%ret;
}

sub _list_devices_attached($rvd) {
    my $sth=$rvd->_dbh->prepare(
        "SELECT d.id,d.name,d.is_base, d.status, l.id, l.name "
        ."     ,l.id_vm "
        ." FROM host_devices_domain hdd, domains d"
        ." LEFT JOIN host_devices_domain_locked l"
        ."    ON d.id=l.id_domain "
        ." WHERE  d.id= hdd.id_domain "
        ."  ORDER BY d.name"
    );
    $sth->execute();
    my %devices;
    while ( my ($id,$name,$is_base, $status, $is_locked, $device, $id_vm) = $sth->fetchrow ) {
        next if !$device;
        $is_locked = 0 if !$is_locked || $status ne 'active';
        my $domain = {     id => $id       ,name => $name, is_locked => $is_locked
                      ,is_base => $is_base ,device => $device
        };
        $devices{"$id_vm.$device"} = $domain;
    }
    return %devices;

}

sub _list_domains_with_device($rvd,$row) {
    my $id_hd = $row->{id};

    my %devices;
    eval {
        my $devices = decode_json($row->{devices});
        %devices = map { $_ => { name => $_ } } @$devices;
    } if $row->{devices};
    my $sth=$rvd->_dbh->prepare("SELECT d.id,d.name,d.is_base, d.status, l.id, l.name "
        ." FROM host_devices_domain hdd, domains d"
        ." LEFT JOIN host_devices_domain_locked l"
        ."    ON d.id=l.id_domain "
        ." WHERE  d.id= hdd.id_domain "
        ."  AND hdd.id_host_device=?"
        ."  ORDER BY d.name"
    );
    $sth->execute($id_hd);
    my ( @domains, @bases);
    while ( my ($id,$name,$is_base, $status, $is_locked, $device) = $sth->fetchrow ) {
        $is_locked = 0 if !$is_locked || $status ne 'active';
        $device = '' if !$device;
        my $domain = {     id => $id       ,name => $name, is_locked => $is_locked
                      ,is_base => $is_base ,device => $device
        };
        $devices{$device}->{domain} = $domain if exists $devices{$device} && $is_locked;
        if ($is_base) {
            push @bases, ($domain);
        } else {
            push @domains, ($domain);
        }
    }
    for my $dev ( values %devices ) {
        _get_domain_with_device($rvd, $dev);
    }

    $row->{_domains} = \@domains;
    $row->{_bases} = \@bases;
}

sub _get_domain_with_device($rvd, $dev) {
    my $sql =
        "SELECT d.id, d.name, d.is_base, d.status "
        ." FROM host_devices_domain_locked l, domains d "
        ." WHERE l.id_domain = d.id "
        ."   AND l.name=?"
        ;

    my $sth = $rvd->_dbh->prepare($sql);
    $sth->execute($dev->{name});
    my @domains;
    while ( my ($id,$name,$is_base, $status, $is_locked, $device) = $sth->fetchrow ) {
        $is_locked = 0 if !$is_locked || $status ne 'active';
        $device = '' if !$device;
        my $domain = {     id => $id       ,name => $name, is_locked => $is_locked
                      ,is_base => $is_base ,device => $device
        };
        $dev->{domain} = $domain;# if $is_locked;
    }
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
        return;
    };


    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    my $info = $domain->info($user);
    if ($info->{is_active} && ( !exists $info->{ip} || !$info->{ip})) {
       Ravada::Request->refresh_machine(id_domain => $info->{id}, uid => $user->id);
    }
    unlock_hash(%$info);
    $info->{_date_changed} = $domain->_data('date_changed');
    lock_hash(%$info);
    return $info;
}

sub _get_node_info($rvd, $args) {
    my ($id_node) = $args->{channel} =~ m{/(\d+)};
    my $login = $args->{login} or die "Error: no login arg ".Dumper($args);
    my $user = Ravada::Auth::SQL->new(name => $login) or die "Error: uknown user $login";

    return {} if!$user->is_admin;

    my $sth = $rvd->_dbh->prepare("SELECT * FROM vms WHERE id=?");
    $sth->execute($id_node);
    my $data = $sth->fetchrow_hashref;
    $data->{is_local}=0;
    $data->{is_local}=1 if $data->{hostname} eq 'localhost'
        || $data->{hostname} eq '127.0.0,1'
        || !$data->{hostname};

    $data->{bases}=_list_bases_node($rvd, $data->{id});

    return $data;
}

sub _list_bases_node($rvd, $id_node) {
    my $sth = $rvd->_dbh->prepare(
        "SELECT d.id FROM domains d,bases_vm bv"
        ." WHERE d.is_base=1"
        ."  AND d.id = bv.id_domain "
        ."  AND bv.id_vm=?"
        ."  AND bv.enabled=1"
    );
    my @bases;
    $sth->execute($id_node);
    while ( my ($id_domain) = $sth->fetchrow ) {
        push @bases,($id_domain);
    }
    $sth->finish;
    return \@bases;
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
        _its_been_a_while($args, 1);
        return 2;
    }

    my ($ping_backend)
    = grep {
        $_->{command} eq 'ping_backend'
    } @reqs ;

    if (!$ping_backend) {
        return 0 if $requested && _its_been_a_while($args);
        my @now = localtime(time);
        my $seconds = $now[0];
        Ravada::Request->ping_backend() if $seconds < 5;
        return 1;
    }

    if ($ping_backend->{status} eq 'requested') {
        return 0 if _its_been_a_while($args);
        return 1;
    }

    _its_been_a_while($args, 1);
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

sub _log_active_domains($rvd, $args) {

    my ($unit, $time, $id_base) = $args->{channel} =~ m{/(\w+)/(\d+)/(.*)};
    ($unit, $time) = $args->{channel} =~ m{/(\w+)/(\d+)} if !defined $unit;

    return Ravada::Front::Log::list_active_recent($unit,$time, $id_base);
}

sub _list_networks($rvd, $args) {
    my @networks;
    my $sth = $rvd->_dbh->prepare(
        "SELECT * FROM virtual_networks ORDER BY name "
    );
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @networks,($row);
    }
    return \@networks;
}

sub _its_been_a_while_channel($args) {
    if (!$args->{a_while} || time -$args->{a_while} > 5) {
        $args->{a_while} = time;
        return 1;
    }
    return 0;
}

sub _its_been_a_while($args, $reset=0) {
    if ($reset) {
        $args->{a_while}->{_global} = 0;
    }
    if (!$args->{a_while}->{_global}) {
        $args->{a_while}->{_global} = time;
        return 0;
    }
    return time - $args->{a_while}->{_global} > 5;
}

sub _different($var1, $var2) {
    return Ravada::Utils::_different($var1, $var2);
}

sub BUILD {
    my $self = shift;

    $TZ = DateTime::TimeZone->new(name => $self->ravada->settings_global()
        ->{backend}->{time_zone}->{value})
    if !defined $TZ;

    Mojo::IOLoop->recurring(3 => sub {
            for my $key ( keys %{$self->clients} ) {
                my $ws_client = $self->clients->{$key}->{ws};
                my $channel = $self->clients->{$key}->{channel};
                $self->_send_answer($ws_client, $channel, $key);
            }
        });

}

sub _count_different($rvd, $args, $table) {
    my $count = _count_table($rvd, $table);
    my $key = "_count_".$table;
    if (!defined $args->{$key}
        || $args->{$key} != $count ) {

        $args->{$key} = $count;
        return 1;
    }
    return 0;
}

sub _old_info($self, $key, $new_count=undef, $new_changed=undef) {
    my $args = $self->clients->{$key};

    $args->{"_count_$key"} = $new_count if defined $new_count;
    $args->{"_changed_$key"} = $new_changed if defined $new_changed;

    my $old_count = ($args->{"_count_$key"}  or 0 );
    my $old_changed = ($args->{"_changed_$key"}  or '' );

    return ($old_count, $old_changed);
}

sub _clean_info($self, $key) {
    $self->_old_info($key,0,0);
}

sub _date_changed_table($self, $table, $id) {
    my $rvd = $self->ravada;
    my $sth;
    if (defined $id) {
        $sth = $rvd->_dbh->prepare("SELECT MAX(date_changed) FROM $table "
            ." WHERE id=?");
        $sth->execute($id);
    } else {
        $sth = $rvd->_dbh->prepare("SELECT MAX(date_changed) FROM $table");
        $sth->execute;
    }
    my ($date) = $sth->fetchrow;
    return ($date or '');
}

sub _count_table($rvd, $table) {
    my $sth = $rvd->_dbh->prepare("SELECT count(*) FROM $table");
    $sth->execute;
    my ($count) = $sth->fetchrow;
    return $count;
}

sub _count_domains_active($rvd) {
    my $sth = $rvd->_dbh->prepare("SELECT count(*) FROM domains "
        ." WHERE status='active'");
    $sth->execute;
    my ($count) = $sth->fetchrow;
    return $count;
}

sub _new_info($self, $key) {
    my $channel = $self->clients->{$key}->{channel};
    $channel =~ s{/(.*)}{};
    my $id;
    $id = $1 if defined $1;

    my $table0 = $TABLE_CHANNEL{$channel} or return;
    if (!ref($table0)) {
        $table0 = [$table0];
    }

    my $count = '';
    my $date = '';

    for my $table (@$table0) {
        $count .= ":" if $count;
        $count .= _count_table($self->ravada, $table);

        $date .= ":" if $date;
        $date .= $self->_date_changed_table($table, $id);
    }
    return ($count, $date);

}

sub _send_answer($self, $ws_client, $channel, $key = $ws_client) {
    $channel =~ s{/.*}{};
    my $exec = $SUB{$channel} or die "Error: unknown channel $channel";

    my $old_ret = $self->clients->{$key}->{ret};
    if (exists $TABLE_CHANNEL{$channel} && $TABLE_CHANNEL{$channel}
            && defined $self->clients->{$key}->{TIME0}->{$channel}
            && time < $self->clients->{$key}->{TIME0}->{$channel}+60) {
        my ($old_count, $old_changed) = $self->_old_info($key);
        my ($new_count, $new_changed) = $self->_new_info($key);


        return $old_ret if defined $new_count && defined $new_changed
        && $old_count eq $new_count && $old_changed eq $new_changed;

        $self->_old_info($key, $new_count, $new_changed);

    }

    $self->clients->{$key}->{TIME0}->{$channel} = time;

    my $ret;
    eval { $ret = $exec->($self->ravada, $self->clients->{$key}) };
    warn $@ if $@;

    if ( defined $ret && (!defined $old_ret || _different($ret, $old_ret ))) {

        my $short_key = $key;
        $short_key =~ s/.*HASH\((.*)\)/$1/;
        warn time." $short_key WS: send $channel " if $DEBUG;
        $ws_client->send( {json => $ret} );
        $self->clients->{$key}->{ret} = $ret;
    }
    $self->unsubscribe($key) if $channel eq 'ping_backend' && $ret eq 2;
}

sub manage_action($self, $ws, $channel, $action, $args) {
    if ($channel eq 'list_machines_tree') {

        $self->clients->{$ws}->{_list_machines_time}=0;
        if ($action eq 'show_clones') {
            my ($id, $value) = $args =~/(\d+)=(.+)/;
            if ($value eq 'true') {
                $self->clients->{$ws}->{$action}->{$id}=1;
            } else {
                delete $self->clients->{$ws}->{$action}->{$id};
            }
            return;
        } elsif ($action eq 'show_active') {
            if ($args eq 'true') {
                delete $self->clients->{$ws}->{show_clones};
                $self->clients->{$ws}->{$action}=1;
            } else {
                delete $self->clients->{$ws}->{$action};
            }
            return;
        } elsif ( $action eq 'show_name') {
            if ($args) {
                $self->clients->{$ws}->{$action}=$args;
            } else {
                delete $self->clients->{$ws}->{$action};
            }
            return;
        }
    }
    $self->clients->{$ws}->{channel} = "$channel/$action/$args";
}

sub subscribe($self, %args) {
    my $ws = $args{ws};
    my %args2 = %args;
    delete $args2{ws};
    warn "Subscribe ".Dumper(\%args2) if $DEBUG;
    if (!exists $self->clients->{$ws}) {
        $self->clients->{$ws} = {
            ws => $ws
            , %args
            , ret => undef
        };
    } else {
        return $self->unsubscribe_all()
           if $args{login} ne $self->clients->{$ws}->{login};

        my $channel0 = $args{channel};
        my ($channel,$action,$args)= $channel0 =~ m{(.*?)/(.*?)/(.*)};
        if ($channel) {
            $args{channel} = $channel;
            $self->manage_action($ws, $channel, $action, $args)
        }
        for my $key (keys %{$self->clients->{$ws}}) {
            $self->clients->{$ws}->{$key} = 1
            if $key =~ /_(time|last)$/i;
        }
    }
    $self->_clean_info($ws);
    $self->_send_answer($ws,$args{channel});
    my $channel = $args{channel};
    $channel =~ s{/.*}{};
    $self->clients->{$ws}->{TIME0}->{$channel} = 0 if $channel =~ /list_machines/i;
}

sub unsubscribe($self, $ws) {
    delete $self->clients->{$ws};
}

sub unsubscribe_all($self) {
    for my $ws ( keys %{$self->clients()} ) {
        warn $ws;
        delete $self->clients->{$ws};
    }
}

1;
