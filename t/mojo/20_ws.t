use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use DateTime;
use Mojo::JSON 'decode_json';
use Test::More;
use Test::Mojo;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $USERNAME;
my $PASSWORD = "$$ $$";

my $USER;

my $TZ;

########################################################################################

=pod

sub _init_mojo_client {
    return if $USERNAME;
    $T->get_ok('/')->status_is(200)->content_like(qr/name="login"/);

    my $user_admin = user_admin();
    my $pass = "$$ $$";

    $USERNAME = $user_admin->name;
    $PASSWORD = $pass;

    mojo_login($T, $user_admin->name, $pass) or exit;
    $T->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);
}

=cut

sub list_machines_user($t, $headers={}){
    mojo_check_login($t);
    $t->websocket_ok("/ws/subscribe" => $headers)->send_ok("list_machines_user")->message_ok->finish_ok;

    confess if !$t->message || !$t->message->[1];

    my $name = base_domain_name();
    my @machines = grep { $_->{name} =~ /^$name/ } @{decode_json($t->message->[1])};
    _clean_machines_info(\@machines);
    return @machines;
}

sub _clean_machines_info($machines) {
    for my $m (@$machines) {
        for my $key (keys %$m ) {
            delete $m->{$key} unless $key =~ /id|name|base|clone/;
        }
    }
}

sub list_machines($t) {
    $t->websocket_ok("/ws/subscribe")->send_ok("list_machines_tree")->message_ok->finish_ok;
    return if !$t->message || !$t->message->[1];

    my $name = base_domain_name();
    my $message = decode_json($t->message->[1]);
    my @machines = grep { $_->{name} =~ /^$name/ } @{$message->{data}};
    _clean_machines_info(\@machines);
    return @machines;
}

sub _create_bases($t, $vm_name) {
    my @base;
    for ( 0 .. 1 ) {
        my $base =  mojo_create_domain($t, $vm_name);
        push @base, ($base);
    }
    return @base;
}

sub test_bases($t, $bases) {
    mojo_check_login($t);
    my $n_bases = 0;
    my $n_machines = scalar(@$bases);
    for my $base ( @$bases ) {

        mojo_request($t, "force_shutdown", { id_domain => $base->id });

        my $url = "/machine/prepare/".$base->id.".json";
        $t->get_ok($url)->status_is(200);
        wait_mojo_request($t, $url);
        wait_request(debug => 0, background => 1);
        mojo_check_login($t);
        $n_bases++;
        my @machines_user0 = list_machines_user($t);
        my @machines_user;
        for ( 1 .. 20 ) {
            @machines_user = grep {$_->{is_base}} list_machines_user($t);
            last if scalar(@machines_user)==$n_bases;
            sleep 1;
            $t->get_ok($url)->status_is(200);
            wait_request();
        }
        is(@machines_user, $n_bases, Dumper(\@machines_user)) or die Dumper(\@machines_user0);
        my $n_clones = 2;
        mojo_request($t, "clone", { id_domain => $base->id, number => $n_clones });
        $n_machines += $n_clones;

        my @machines = list_machines($t);
        is( scalar(@machines), scalar(@$bases)
            , Dumper([[ map { $_->{name} } @machines]
                    , [ map { $_->name } @$bases  ]
                    ])) or exit;
    }
}

sub _login_non_admin($t) {
    mojo_logout($t);
    my $user_name = new_domain_name().".doe";
    remove_old_user($user_name);
    $USER = create_user($user_name, $$);
    mojo_login($t, $user_name,$$);
}

sub _new_login_non_admin($t) {
    my $user_name = new_domain_name();
    remove_old_user($user_name);
    my $user = create_user($user_name, $$);
    mojo_login($t, $user_name,$$);
    return $user;
}
sub test_bases_non_admin($t,$bases) {
    my $n_public = 0;
    for my $base (@$bases) {
        is(list_machines_user($t),$n_public);
        $base->is_public(1);
        is($base->is_public, 1);
        is(list_machines_user($t),++$n_public);
    }
}

sub _prepare_base($base) {

    $base->is_public(1) unless $base->is_public();

    return if $base->is_base();
    Ravada::Request->prepare_base( uid => user_admin->id
        ,id_domain => $base->id
    );
    wait_request();
}

sub test_list_machines_non_admin($t, $bases) {
    mojo_logout($t);
    _login_non_admin($t);
    _prepare_base($bases->[0]);

    my $url = "/machine/clone/".$bases->[0]->id.".html";
    $t->get_ok($url)->status_is(200) or die $url;
    wait_request(background => 1, debug => 1);
    my @list_bases = list_machines_user($t);
    my $clone;
    for my $base (@list_bases) {
        next if !$base->{list_clones};
        for my $c2 (@{$base->{list_clones}}) {
            $clone = $c2;
            last;
        }
        last if $clone;
    }
    $clone = _clone($bases->[0], $USER) if !$clone;

    my @list_machines = list_machines($t);
    is(scalar(@list_machines),0) or die Dumper([map {[$_->{id_base},$_->{name}]} @list_machines]);

    Ravada::Request->force_shutdown(
        uid => user_admin->id
        ,id_domain => $clone->{id}
    );
    my $req = Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $clone->{id}
    );
    wait_request(background => 1);
    user_admin->grant($USER,'shutdown_clones');
    is($USER->is_operator,1);
    is($USER->can_list_clones_from_own_base(),1);

    for ( 1 .. 5 ) {
        @list_machines = list_machines($t);
        last if scalar(@list_machines)==1;
        sleep 1;
        wait_request($req->id);
    }
    is(scalar(@list_machines),1,$USER->name." / $$ should see one machine") or exit;
    my ($base) = $list_machines[0];

    my $user2 = create_user();
    _clone($base, $user2);
    @list_machines = list_machines($t);
    is(scalar(@list_machines),2,$USER->name." / $$ should see 2 machines") or exit;

    my ($clone2) = grep { $_->{id_owner} == $user2->id } @list_machines;
    ok($clone2);

    test_shutdown($USER, $clone2);
    user_admin->revoke($USER,'shutdown_clones');
    remove_domain_and_clones_req($base);
}

sub test_shutdown($user, $clone) {
    if (!$clone->{status} eq 'active') {
        my $req = Ravada::Request->shutdown(
            uid => $user->id
            ,id_domain => $clone->{id}
        );
        wait_request();
    }
    my $req = Ravada::Request->shutdown(
        uid => $user->id
        ,id_domain => $clone->{id}
    );
    wait_request();
    is($req->error,'');
    my $clone2 = Ravada::Front::Domain->open($clone->{id});
    is($clone2->_data('status'),'shutdown');
}

sub _clone($base0, $user) {
    my $base = $base0;
    $base = Ravada::Front::Domain->open($base0->{id})
    if ref($base) !~ /^Ravada/;
    
    _prepare_base($base);
    
    my $clone;
    my $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
    );
    wait_request(debug => 1);
    is($req->error,'') or exit;
    is($req->status,'done') or exit;
    ($clone) = $base->clones();
    die "Error: no clone found for base ".$base->name if !$clone;
    return $clone;
}

sub test_bases_access($t,$bases) {
    for (@$bases) { $_->is_public(1) };

    my $base0 = $bases->[0];
    my      $type = 'client';
    my     $value = 'ca-ca';
    my $attribute = 'Accept-Language';
    $base0->grant_access(
              type => $type
        ,attribute => $attribute
            ,value => $value
    );

    _new_login_non_admin($t);
    my @list_machines = list_machines_user($t);
    is(scalar(@list_machines),1,Dumper(\@list_machines));

    $t->tx->req->headers->add( $attribute => $value );
    @list_machines = grep { $_->{is_base} } list_machines_user($t ,{ $attribute => $value });
    is(scalar(@list_machines),2) or exit;

    my @access = $base0->list_access('client');
    $base0->delete_access(@access);
    @access = $base0->list_access;
    is(scalar(@access),0,Dumper(\@access));

    @list_machines = list_machines_user($t);
    is(scalar(@list_machines),2);

    for (@$bases) { $_->is_public(0) };
}

sub _monday() {
    my $now = DateTime->from_epoch( epoch => time() , time_zone => $TZ );

    return $now->add( days => 1-$now->day_of_week);

}

sub _now() {
    return DateTime->from_epoch( epoch => time() , time_zone => $TZ )
}

sub _wait_tomorrow() {
    for (;;) {
        my $now = _now();
        if ( $now->hour == 23 && $now->minute > 57 ) {
            diag("Waiting for 00:00 ".$now);
            sleep 1;
        } else {
            return;
        }
    }
}

sub test_bookings($t) {

    _wait_tomorrow();

    my $today = _now();
    my $dow_today = $today->day_of_week;
    my $tomorrow= _now()->add(days => 1);
    my $dow_tomorrow = $tomorrow->day_of_week;
    my $now = _now();

    my $time_start = _now()->add(minutes => 1);
    my $time_end = _now()->add(minutes => 2);

    my $booking_title = new_domain_name();
    my $new_day_of_week = "$dow_today$dow_tomorrow";

    my %args_booking  = (
        date_start => $today->ymd
        ,date_end => $today->add( days => 7 )->ymd
        ,time_start => $time_start->hms
        ,time_end => $time_end->hms
        ,day_of_week => $new_day_of_week
        ,title => $booking_title
        ,users => $USERNAME
    );

    test_create_booking_non_admin($t, %args_booking);

    $t->post_ok('/v1/bookings' => json => \%args_booking);
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;
    my $response = $t->tx->res->json();

    my $booking = Ravada::Booking->search( title => $booking_title);
    ok($booking,"Expecting booking titled '$booking_title'");
    is(scalar($booking->entries),3,"Expecting 3 entries $new_day_of_week "
        .Dumper([map { $_->_data('date_booking') } $booking->entries])) or exit;

    $t->websocket_ok("/ws/subscribe")->send_ok("list_next_bookings_today")
    ->message_ok->finish_ok;

    if ( !$t->message || !$t->message->[1] ) {
        ok(0,"Wrong webservice message for list next bookings today");
        $booking->remove() if $booking;
        return;
    }

    my @bookings = @{decode_json($t->message->[1])};

    my ($found) = grep { $_->{title} eq $booking_title } @bookings;
    ok($found, "Expecting $booking_title in ".Dumper(''._now()->hms,\@bookings)) or exit;

    is($found->{user_allowed},1);

    my ($booking_entry) = $booking->entries();
    test_remove_booking_entry_non_admin($t, $booking_entry->id);
    test_remove_booking_non_admin($t, $booking_entry->id);

    my $url = "/v1/booking_entry/".$booking_entry->id."/current";
    $t->delete_ok($url);
    is($t->tx->res->code(), 200 ) or die $url;

    my ($booking_entry_removed) = grep { $_->id == $booking_entry->id } $booking->entries();
    ok(!$booking_entry_removed,"Expecting entry removed ".$booking_entry->id);

    ($booking_entry) = $booking->entries();
    $url = "/v1/booking_entry/".$booking_entry->id."/all";
    $t->delete_ok($url);
    is($t->tx->res->code(), 200 ) or die $url;

    my $booking_removed;
    eval { $booking_removed = Ravada::Booking->new(id => $booking->id)};
    like($@,qr/not found/);
    ok(!$booking_removed, "Expecting booking removed ".$booking->id)
        or die Dumper($booking_removed);

    $booking->remove() if $booking_removed;

}

sub test_create_booking_non_admin($t, %args_booking) {
    _login_non_admin($t);

    $t->post_ok('/v1/bookings' => json => \%args_booking);

    is($t->tx->res->code(), 403) or exit;
    like($t->tx->res->body, qr /Access denied/);
    mojo_login($t, $USERNAME, $PASSWORD);
}

sub test_remove_booking_non_admin($t, $id) {
    _login_non_admin($t);

    $t->delete_ok("/v1/booking_entry/$id/current");
    is($t->tx->res->code(), 403) or confess;
    like($t->tx->res->body, qr /Access denied/);
    mojo_login($t, $USERNAME, $PASSWORD);
}

sub test_remove_booking_entry_non_admin($t, $id) {
    _login_non_admin($t);

    $t->delete_ok("/v1/booking_entry/$id/current");
    is($t->tx->res->code(), 403) or exit;
    like($t->tx->res->body, qr /Access denied/);
    mojo_login($t, $USERNAME, $PASSWORD);

}

sub test_node_info($vm_name) {
    my $sth = connector->dbh->prepare("SELECT * FROM vms WHERE vm_type=?");
    $sth->execute($vm_name);

    my $user = create_user(new_domain_name(), $$);

    while ( my $node = $sth->fetchrow_hashref) {
        my $ws_args = {
            channel => '/'.$node->{id}
            ,login => user_admin->name
        };

        my $node_info = Ravada::WebSocket::_get_node_info
                            (rvd_front(), $ws_args);
        if ($node->{hostname} =~ /localhost|127.0.0.1/) {
            is($node_info->{is_local},1);
        } else {
            is($node_info->{is_local},0);
        }

        $ws_args->{login} = $user->name;

        $node_info = Ravada::WebSocket::_get_node_info
                            (rvd_front(), $ws_args);

        is_deeply($node_info,{});
    }

}

########################################################################################

init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
unlike($connector->{driver} , qr/sqlite/i) or BAIL_OUT;

if (!ping_backend()) {
    diag("SKIPPING: Backend not available");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

$TZ = DateTime::TimeZone->new(name => rvd_front->settings_global()->{backend}->{time_zone}->{value});

remove_old_domains_req(0); # 0=do not wait for them
mojo_clean();

my @bookings = Ravada::Booking::bookings_range(
        time_start => _now()->add(seconds => 1)->hms
);

warn "Warning: bookings scheduled for today may spoil tests ".Dumper(\@bookings)
if @bookings;


$USERNAME = user_admin->name;
my $t = mojo_init();

for my $vm_name ( @{rvd_front->list_vm_types} ) {

    diag("Testing Web Services in $vm_name");

    test_node_info($vm_name);

    mojo_login($t, $USERNAME, $PASSWORD);
    test_bookings($t);
    my @bases = _create_bases($t, $vm_name);

    is(list_machines_user($t), scalar(@bases));
    is(list_machines($t), scalar(@bases)) or exit;

    _login_non_admin($t);
    is(list_machines_user($t), 0);

    mojo_login($t, $USERNAME, $PASSWORD);
    test_bases($t,\@bases);
    test_list_machines_non_admin($t,\@bases);

    _login_non_admin($t);
    test_bases_access($t,\@bases);

    test_bases_non_admin($t, \@bases);
    test_list_machines_non_admin($t,\@bases);
    test_bases_access($t,\@bases);

    remove_old_domains_req();
    while( list_machines_user($t) ) {
        remove_old_domains_req();
    }
}
mojo_clean($t);
remove_old_domains_req(0); # 0=do not wait for them

done_testing();
