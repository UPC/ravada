use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use DateTime;
use Hash::Util qw(lock_hash);
use Test::More;
use YAML qw(DumpFile);

use Ravada::HostDevice::Templates;

use 5.010;

no warnings "experimental::signatures";
use feature qw(signatures);


use lib 't/lib';
use Test::Ravada;

my $GROUP = 'test_bookings_ldap';
my $GROUP_LOCAL;
my ($USER_YES_NAME_1, $USER_YES_NAME_2, $USER_NO_NAME) = ( 'mcnulty','bunk','stringer');
my ($USER_2_NAME,$USER_3_NAME)=('bubbles','walon');

our $TZ;

use_ok('Ravada::Booking');

###################################################################
my ($USER_YES_1, $USER_YES_2, $USER_NO, $USER_2, $USER_3);
my ($USER_LOCAL_YES_1, $USER_LOCAL_YES_2, $USER_LOCAL_NO, $USER_LOCAL_2, $USER_LOCAL_3);

sub  _init_local() {
    $GROUP_LOCAL = create_group() if !$GROUP_LOCAL;

    for my $ref ( \($USER_LOCAL_YES_1, $USER_LOCAL_YES_2, $USER_LOCAL_NO, $USER_LOCAL_2, $USER_LOCAL_3)) {
        my $user = create_user();
        $$ref=$user;
    }
    $USER_LOCAL_YES_1->add_to_group($GROUP_LOCAL);
    $USER_LOCAL_YES_2->add_to_group($GROUP_LOCAL);
}

sub _init_ldap(){

    my $group = _add_posix_group();
    my $n = 0;
    for my $name ($USER_YES_NAME_1, $USER_YES_NAME_2, $USER_NO_NAME, $USER_2_NAME, $USER_3_NAME) {
        create_ldap_user($name,$n, 1);

        _add_to_posix_group($group,$name)
        if $name eq $USER_YES_NAME_1 || $name eq $USER_YES_NAME_2;

        Ravada::Auth::LDAP->new( name => $name , password => $n);

        $n++;
    }

    $USER_YES_1 = Ravada::Auth::SQL->new(name => $USER_YES_NAME_1);
    $USER_YES_2 = Ravada::Auth::SQL->new(name => $USER_YES_NAME_2);
    $USER_NO = Ravada::Auth::SQL->new(name => $USER_NO_NAME);
    $USER_2 = Ravada::Auth::SQL->new(name => $USER_2_NAME);
    $USER_3 = Ravada::Auth::SQL->new(name => $USER_3_NAME);

}

sub _add_to_posix_group($group, $user_name) {

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $mesg = $group->add(memberUid => $user_name)->update($ldap);
    die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code != 20;

    my @member = $group->get_value('memberUid');

    my ($found) = grep /^$user_name$/,@member;

    ok( $found, "Expecting $user_name in $GROUP");
}

sub _add_posix_group {
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    ok($ldap) or confess;

    my $base = "ou=groups,".Ravada::Auth::LDAP::_dc_base();

    my $mesg;
    for ( 1 .. 10 ) {
        $mesg = $ldap->add(
        cn => $GROUP
        ,dn => "cn=$GROUP,$base"
        ,attrs => [ cn => $GROUP
                    ,objectClass=> [ 'posixGroup' ]
                    ,gidNumber => 999
                ]
    );
    last if !$mesg->code;
    warn "Error ".$mesg->code." adding $GROUP ".$mesg->error
        if $mesg->code && $mesg->code != 68;

        Ravada::Auth::LDAP::init();
        $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    }

    $mesg = $ldap->search( filter => "cn=$GROUP",base => $base );
    my @group = $mesg->entries;
    ok($group[0],"Expecting group $GROUP") or return;
    return $group[0];
}


sub _remove_domains(@bases) {
    for my $base (@bases) {
        for my $clone ($base->clones) {
            my $d_clone = Ravada::Domain->open($clone->{id});
            $d_clone->remove(user_admin);
        }
        $base->remove(user_admin);
    }
}

sub _now() { return _now_days(0) }
sub _today() { return _date(_now_days(0)) }
sub _yesterday() { return _date(_now_days(-1)) }
sub _monday() {
    my $now = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
    return $now->add( days => -$now->day_of_week+1);
}

sub _now_days($days) {
    my $now = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
    return $now->add( days => $days );
}


sub _now_seconds($seconds) {
    my $now = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
    return $now->add( seconds => $seconds)->hms();
}

sub _date($dt) {
    confess if !ref($dt);
    return $dt->ymd;
}

# our tests won't work if we are at hh:59
sub _wait_end_of_hour($seconds=0) {
    for (;;) {
        my $now = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
        last if $now->minute <59
        && ( $now->minute>0 || $now->second>$seconds);
        diag("Waiting for hour:01 to run booking tests "
            .$now->hour.":".$now->minute.".".$now->second);
        sleep 1;
    }

}

sub test_booking_oneday_dow($vm, $mode) {
    return test_booking_oneday($vm, $mode, 1);
}

sub test_booking_oneday_date_end($vm, $mode) {
    return test_booking_oneday($vm, $mode, 0,1);
}

sub test_booking_oneday_date_end_dow($vm, $mode) {
    return test_booking_oneday($vm,$mode, 1,1);
}


sub test_booking_oneday($vm, $mode, $dow=0, $date_end=0) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);
    confess if !ref($mode) || ref($mode) ne 'HASH';

    for my $key (keys %$mode) {
        next if $key =~ /^(local|ldap)$/;
        die "Mode incorrect. It should be ldap,local or both ".Dumper($mode);
    }

    my $today = DateTime->from_epoch( epoch => time(), time_zone => $TZ);
    my @args;
    push @args, ( day_of_week => $today->day_of_week)   if $dow;
    push @args, ( date_end => $today->ymd)              if $date_end;
    push @args , ( ldap_groups => $GROUP )              if $mode->{'ldap'};
    push @args , ( local_groups => $GROUP_LOCAL->id )       if $mode->{'local'};

    my $booking = Ravada::Booking->new(
        bases => $base->id
        , users => [$USER_2_NAME , $USER_3->id]
        , date_start => $today->ymd
        , time_start => "08:00"
        , time_end => "09:00"
        , title => 'comunicacions multimedia'
        , description => 'blablabla'
        , id_owner => user_admin->id
        , @args
    );

    is(scalar($booking->entries),1) or exit;
    $booking->remove();
    $base->remove(user_admin);
}

sub test_booking_datetime($vm) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $today = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
    my $week = DateTime->from_epoch( epoch => time() , time_zone => $TZ )->add( days => 7 );
    my $booking = Ravada::Booking->new(
        bases => $base->id
        , ldap_groups => $GROUP
        , users => [$USER_2_NAME , $USER_3->id]
        , date_start => ''.$today
        , date_end => ''.$week
        , time_start => "08:00"
        , time_end => "09:00"
        , title => 'comunicacions multimedia'
        , description => 'blablabla'
        , id_owner => user_admin->id
    );

    is(scalar($booking->entries),2) or exit;
    my @bookings = Ravada::Booking::bookings(
        date => $today->ymd
        ,time => '08:00'
    );
    is(scalar(@bookings),1) or die Dumper(\@bookings);

    @bookings = Ravada::Booking::bookings(
        date => $today->ymd
        ,time => '08:44'
    );
    is(scalar(@bookings),1) or die Dumper(\@bookings);

    @bookings = Ravada::Booking::bookings(
        date => $today->ymd
        ,time => '09:00'
    );
    is(scalar(@bookings),0) or die Dumper(\@bookings);

    @bookings = Ravada::Booking::bookings(
        date => $today->ymd
        ,time => '09:01'
    );
    is(scalar(@bookings),0) or die Dumper(\@bookings);

    $booking->remove();
    $base->remove(user_admin);
}



sub test_booking($vm, $clone0_no1, $clone0_no2, $clone0_as, $base0) {

    my $base2 = create_domain($vm);

    $clone0_no1->start(user => user_admin);
    $clone0_no2->start(user => user_admin);
    $clone0_as->start(user => user_admin);

    my $seconds = 60;
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);
    my $clone_no = $base->clone(name => new_domain_name, user => $USER_NO);
    my $clone_yes = $base->clone(name => new_domain_name, user => $USER_YES_1);

    my $seconds_wait = 20;
    _wait_end_of_hour(+$seconds_wait);
    my $date_start = _yesterday();
    my $date_end = _date(_now_days(7));
    my $time_start = _now_seconds(-$seconds_wait);
    my $time_end = _now_seconds($seconds);

    my $today = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
    my $tomorrow = DateTime->from_epoch( epoch => time() , time_zone => $TZ )->add(days => 1);

    $USER_2->remove();

    my @users_yes;
    @users_yes = ($USER_2_NAME , $USER_3->id);
    push @users_yes,( $USER_LOCAL_2->name, $USER_LOCAL_3->name);

    my $booking = Ravada::Booking->new(
        bases => $base->id
        , ldap_groups => $GROUP
        , local_groups => $GROUP_LOCAL->id
        , users => \@users_yes
        , date_start => $date_start
        , date_end => $date_end
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $today->day_of_week.''.$tomorrow->day_of_week
        , title => 'comunicacions multimedia'
        , description => 'blablabla'
        , id_owner => user_admin->id
    );

    my @entries0 = $booking->entries();
    is(scalar(@entries0),3) or die Dumper(\@entries0);

    test_list_machines_user($vm);

    test_bookings_week($base->id);

    my @entries = $booking->entries();
    is(scalar(@entries),3) or die Dumper(\@entries);
    for my $entry ( @entries ) {
        my @groups = $entry->ldap_groups;
        is($groups[0], $GROUP);
        my @users = $entry->users();
        is(scalar(@users),scalar(@users_yes),Dumper(\@users));
    };

    _test_user_allowed_ldap($base);
    _test_user_allowed_local($base);

    eval { $clone_no->start(user => $USER_NO) };
    like($@,qr/Resource .*booked/i );
    is($clone_no->is_active,0);

    eval { $clone_yes->start(user => $USER_YES_1) };
    is($@, '');
    is($clone_yes->is_active,1);

    test_shut_others($clone0_no1, $clone0_no2, $clone0_as);

    _change_seconds($booking);

    eval { $clone_no->start(user => $USER_NO) };
    is($@, '');
    is($clone_no->is_active,1);

    $booking->remove();
    test_booking_removed($booking, @entries);
    _remove_domains($base, $base2, $base0);

}

sub _test_user_allowed_ldap($base) {
    is(Ravada::Booking::user_allowed($USER_YES_1, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_YES_1->id, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_YES_1->name, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_2_NAME, $base->id),1, $USER_2_NAME) or exit;
    is(Ravada::Booking::user_allowed($USER_3, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_NO->name, $base->id ),0);
    is(Ravada::Booking::user_allowed($USER_NO->id, $base->id ),0);
    is(Ravada::Booking::user_allowed($USER_NO, $base->id ),0)
}

sub _test_user_allowed_local($base) {
    is(Ravada::Booking::user_allowed($USER_LOCAL_YES_1, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_LOCAL_YES_1->id, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_LOCAL_YES_1->name, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_LOCAL_2->name, $base->id),1, $USER_LOCAL_2->name) or exit;
    is(Ravada::Booking::user_allowed($USER_LOCAL_3, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO->name, $base->id ),0);
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO->id, $base->id ),0);
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO, $base->id ),0)
}
sub test_bookings_week_2days($vm) {
    my $base = create_domain($vm);

    my $dow1 = _monday()->day_of_week;
    my $dow2 = _monday()->add(days=>1)->day_of_week;

    my $hour = "08";
    my $time_start = "$hour:00";
    my $time_end = ($hour + 1).":00";

    my $booking = Ravada::Booking->new(
        bases => $base->id
        , date_start => _monday()->ymd
        , date_end => _monday()->add(days=>3)->ymd
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $dow1.$dow2
        , title => 'comunicacions multimedia'
        , description => 'blablabla'
        , id_owner => user_admin->id
    );

    is(scalar($booking->entries),2);
    $hour = "0$hour" if length($hour) < 2;

    my $bookings = Ravada::Booking::bookings_week(id_base => $base->id);
    my $key1 = ($dow1-1).".$hour";
    my $key2 = ($dow2-1).".$hour";
    my $book1 = $bookings->{$key1};
    my $book2 = $bookings->{$key2};

    ok($book1," Expecting a booking for $key1 ".Dumper($booking->id,$bookings)) or exit;
    ok($book2," Expecting a booking for $key2.".Dumper($bookings)) or exit;

    my ($entry) = $booking->entries;
    my @bases = $entry->bases;
    $entry->change( bases => [] );

    is(scalar(keys %{Ravada::Booking::bookings_week()}),2);
    is(scalar(keys %{Ravada::Booking::bookings_week( id_base => $base->id)}),1);

    $entry->change( bases => \@bases );
    is(scalar(keys %{Ravada::Booking::bookings_week()}),2);
    my $bookings_after_reset = Ravada::Booking::bookings_week( id_base => $base->id);
    is_deeply($bookings_after_reset, $bookings,''.Dumper($bookings_after_reset,$bookings));

    $base->remove(user_admin);
    $booking->remove();
}


sub test_bookings_week($id_base) {
    my $today = DateTime->from_epoch( epoch => time() , time_zone => $TZ );

    my $bookings = Ravada::Booking::bookings_week(id_base => $id_base);
    my $dow = $today->day_of_week - 1;
    my $hour = $today->hour;
    $hour = "0$hour" if length($hour) < 2;

    my $book_today = $bookings->{"$dow.$hour"};
    my $key_tomorrow = ''.($dow+1).".$hour";
    my $book_tomorrow = $bookings->{$key_tomorrow};

    ok($book_today," Expecting a booking for $dow.$hour ".Dumper($bookings)) or exit;
    ok($book_tomorrow," Expecting a booking for $key_tomorrow ".Dumper($bookings)) or confess
    if $dow != 6;

    my $n_exp = 2;
    # expect 1 booking if today is sunday
    $n_exp = 1 if $today->day_of_week ==7 ;
    is(scalar (keys %$bookings),$n_exp,"Expecting $n_exp bookings for this week");

    my $bookings_no = Ravada::Booking::bookings_week(id_base => $id_base
        , user_name => $USER_NO->name
    );
    is(scalar(keys %$bookings_no),0);
    $bookings_no = Ravada::Booking::bookings_week( user_name => $USER_NO->name);
    is(scalar(keys %$bookings_no),0);

    my $bookings_yes = Ravada::Booking::bookings_week(id_base => $id_base
        , user_name => $USER_YES_1->name
    );
    is_deeply($bookings_yes, $bookings);

}

sub test_shut_others($clone_no1, $clone_no2, $clone_as) {
    $clone_no1->start(user => user_admin)  if !$clone_no1->is_active();
    $clone_no2->start(user => user_admin)  if !$clone_no2->is_active();
    $clone_as->start(user => user_admin)   if !$clone_as->is_active();

    delete_request('enforce_limits');
    my $req = Ravada::Request->enforce_limits();
    rvd_back->_process_requests_dont_fork();
    is($req->status , 'done');
    is($req->error, '');
    rvd_back->_process_requests_dont_fork();
    for my $clone ( $clone_no1, $clone_no2, $clone_as ){
        for my $req ( $clone->list_requests(1) ) {
            $req->at(time);
        }
    }
    rvd_back->_process_requests_dont_fork();

    is($clone_as->is_active,1) or exit;
    is($clone_no1->is_active,0,$clone_no1->name." should be down, owner: "
        .$clone_no1->_data('id_owner')) or exit;
    is($clone_no2->is_active,0,$clone_no2->name." should be down") or exit;

}

sub _change_seconds($booking) {
    my $sth = connector->dbh->prepare("UPDATE booking_entries SET time_end = ? "
        ." WHERE id=? ");

    for my $entry ($booking->entries) {
        $sth->execute("00:00", $entry->id);
    }
}

sub test_conflict_exact($vm, $base) {
    test_conflict_generic($vm,$base,"09:00","11:00");
}

sub test_conflict_before($vm, $base) {
    test_conflict_generic($vm,$base,"08:00","10:00");
}

sub test_conflict_after($vm, $base) {
    test_conflict_generic($vm,$base,"10:00","11:00");
}

sub test_conflict_over($vm, $base) {
    test_conflict_generic($vm,$base,"08:30","11:30");
}

sub test_conflict_inside($vm, $base) {
    test_conflict_generic($vm,$base,"09:30","10:30");
}

sub test_non_conflict_before($vm, $base) {
    test_conflict_generic($vm,$base,"08:00","08:30",0);
}

sub test_non_conflict_after($vm, $base) {
    test_conflict_generic($vm,$base,"12:00","13:00",0);
}

sub test_conflict_hour_sharp($vm, $base) {
    test_conflict_generic($vm,$base,"11:00","12:00",0);
}

sub test_conflict_day_of_week_exact($vm, $base) {
    my $today = DateTime->from_epoch( epoch => time() , time_zone => $TZ );
    my $tomorrow = DateTime->from_epoch( epoch => time() , time_zone => $TZ )->add(days => 1);
    my $dow = $today->day_of_week.''.$tomorrow->day_of_week;
    test_conflict_generic_dow($vm,$base,"09:00","11:00",$dow,6);
}

sub test_conflict_day_of_week_partial($vm, $base) {
    my $today = DateTime->from_epoch( epoch => time(), time_zone => $TZ);
    my $tomorrow = DateTime->from_epoch( epoch => time(), time_zone => $TZ)->add(days => 1);
    my $dow = $tomorrow->day_of_week;
    test_conflict_generic_dow($vm,$base,"09:00","11:00",$dow,3);
}

sub test_non_conflict_day_of_week($vm, $base) {
    my $day_after_tomorrow = DateTime->from_epoch( epoch => time(), time_zone => $TZ)->add(days => 2);
    my $dow = $day_after_tomorrow->day_of_week;
    test_conflict_generic_dow($vm,$base,"09:00","11:00",$dow,0);
}

sub test_conflict_generic_dow($vm, $base, $conflict_start, $conflict_end, $dow, $n_expected=undef) {
    return test_conflict_generic( $vm, $base, $conflict_start, $conflict_end, $n_expected, $dow);
}


sub test_conflict_generic($vm, $base, $conflict_start, $conflict_end, $n_expected=undef, $dow=undef) {

    state $count_booking_generic = 0;

    my $date_start = _yesterday();
    my $date_end = _now_days(15);
    my $time_start = "09:00";
    my $time_end = "11:00";

    my $today = DateTime->from_epoch( epoch => time(), time_zone => $TZ);
    my $tomorrow = DateTime->from_epoch( epoch => time(), time_zone => $TZ)->add(days => 1);
    my $booking = Ravada::Booking->new(
        bases => $base->id
        , ldap_groups => $GROUP
        , date_start => $date_start
        , date_end => $date_end
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $today->day_of_week.''.$tomorrow->day_of_week
        , title => 'garden '.$count_booking_generic
        , description => 'blablabla long'
        , id_owner => user_admin->id
    );
    $n_expected = scalar($booking->entries()) if !defined $n_expected;

    my @conflicts = Ravada::Booking::bookings_range(
        date_start => _now_days(0)
        ,date_end => $date_end
        ,time_start => $conflict_start
        ,time_end => $conflict_end
        ,day_of_week => $dow
    );
    is(scalar(@conflicts), $n_expected,Dumper(\@conflicts)) or confess;
    $booking->remove();

}


sub _create_booking( $base , $options=undef ) {
    _wait_end_of_hour();
    my $date_start = _yesterday();
    my $date_end = _now_days(15);
    my $time_start = _now()->hms;
    my $time_end = _now_seconds(5);

    my $today = DateTime->from_epoch( epoch => time(), time_zone => $TZ);
    my $tomorrow = DateTime->from_epoch( epoch => time(), time_zone => $TZ)->add(days => 1);
    my @args;
    push @args,(bases => $base->id)     if $base;
    push @args,(options => $options)    if $options;

    my $booking = Ravada::Booking->new(
        @args
        , ldap_groups => $GROUP
        , users => $USER_YES_NAME_1
        , date_start => $date_start
        , date_end => $date_end
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $today->day_of_week.''.$tomorrow->day_of_week
        , title => 'garden'
        , description => 'blablabla long'
        , id_owner => user_admin->id
        , date_created => time
    );
    return $booking;
}

sub test_search_change_remove_booking($vm) {

    my $base = create_domain($vm);
    my $booking = _create_booking($base);
    my @entries = $booking->entries();
    is(scalar @entries,6,Dumper(\@entries)) or exit;

    my $booking2 = Ravada::Booking->search( date => _today());
    ok($booking2,"Expecting booking for today") or exit;
    is($booking2->id, $booking->id);

    $booking2 = Ravada::Booking->search( title => 'arden' );
    is($booking2->id, $booking->id);

    $booking2 = Ravada::Booking->search( title => 'arden' , description => 'lon' );
    is($booking2->id, $booking->id);

    my $new_description = "beblebleble do do ".time;
    $booking2->change( description => $new_description);

    my $booking3 = Ravada::Booking->new( id => $booking2->id );
    is($booking3->id, $booking2->id);
    is($booking3->_data('description'), $new_description );

    test_change_entry($vm,$booking);
    test_change_entry_next($vm, $booking);
    test_change_entry_day_of_week($vm, $booking);

    test_remove_entry($booking);
    $booking->remove();

    $booking = _create_booking($base);
    test_remove_entry_next($booking);
    $booking->remove();

    $booking = _create_booking($base);
    test_remove_entry_day_of_week($booking);

    $booking->remove();
    test_booking_removed($booking);
    $base->remove(user_admin);
}

sub test_change_entry($vm, $booking) {
    my ($entry) = $booking->entries();
    my $time_start = $entry->_data('time_start');

    my ($min) = $time_start =~ /:(\d+)/;
    my $new_min = '03';
    $new_min = '00' if $min eq $new_min;

    my $new_time = "00:$new_min";

    isnt($new_time,$time_start) or exit;

    $entry->change( time_start => $new_time );

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );
    is($new_entry->_data('time_start'), $new_time);

    test_change_groups($entry);
    test_change_local_groups($entry);
    test_change_users($entry);
    test_change_bases($vm,$entry);
}

sub test_change_groups($entry) {
    my @groups = $entry->ldap_groups();
    my @groups2 = sort (@groups,"new.group");

    $entry->change( ldap_groups => \@groups2 );
    my @new_groups = sort $entry->ldap_groups;
    is_deeply( \@new_groups ,\@groups2) or die Dumper(\@new_groups,\@groups2);

    #clear groups
    @groups2 = sort ("new.group2");
    $entry->change( ldap_groups => \@groups2 );
    @new_groups = sort $entry->ldap_groups;
    is_deeply( \@new_groups ,\@groups2) or die Dumper(\@new_groups,\@groups2);
}

sub test_change_local_groups($entry) {
    my @groups = $entry->local_groups();
    my $new_group_1 = create_group();
    my @groups2 = sort (@groups, $new_group_1->name);

    $entry->change( local_groups => \@groups2 );
    my @new_groups = sort $entry->local_groups;
    is_deeply( \@new_groups ,\@groups2) or die Dumper(\@new_groups,\@groups2);

    #clear groups
    my $new_group_2 = create_group();
    @groups2 = $new_group_2->id;
    $entry->change( local_groups => \@groups2 );
    @new_groups = sort $entry->local_groups;

    my @groups3 = ($new_group_2->name);
    is_deeply( \@new_groups ,\@groups3) or die Dumper(\@new_groups,\@groups3);
}


sub test_change_users($entry) {
    test_change_users_with_name($entry);
    test_change_users_with_id($entry);
}

sub test_change_users_with_name($entry) {
    my $user_new = create_user(new_domain_name(),'a');
    my @users = $entry->users();
    my @users2 = sort (@users,$user_new->name);

    $entry->change( users => \@users2 );
    my @new_users = sort $entry->users;
    is_deeply( \@new_users ,\@users2) or die Dumper(\@new_users,\@users2);

    #clear users
    my $user_new2 = create_user(new_domain_name(),'a');
    @users2 = ($user_new2->name);
    $entry->change( users => \@users2 );
    @new_users = sort $entry->users;
    is_deeply( \@new_users ,\@users2) or die Dumper(\@new_users,\@users2);

}
sub test_change_users_with_id($entry) {
    my $user_new = create_user(new_domain_name(),'a');
    my @users = $entry->users();
    my @users2 = sort (@users,$user_new->id);
    my @users2_expected = sort (@users,$user_new->name);

    $entry->change( users => \@users2 );
    my @new_users = sort $entry->users;
    is_deeply( \@new_users ,\@users2_expected) or die Dumper(\@new_users,\@users2_expected);

    #clear users
    my $user_new2 = create_user(new_domain_name(),'a');
    @users2 = ($user_new2->id);
    @users2_expected = ($user_new2->name);
    $entry->change( users => \@users2 );
    @new_users = sort $entry->users;
    is_deeply( \@new_users ,\@users2_expected) or die Dumper(\@new_users,\@users2_expected);

}


sub test_change_bases($vm,$entry) {
    test_change_bases_with_name($vm,$entry);
    test_change_bases_with_id($vm,$entry);
}

sub test_change_bases_with_name($vm,$entry) {
    my $base_new = create_domain($vm);
    my @bases = $entry->bases();
    my @bases2 = sort (@bases,$base_new->name);

    $entry->change( bases => \@bases2 );
    my @new_bases = sort $entry->bases;
    is_deeply( \@new_bases ,\@bases2) or die Dumper(\@new_bases,\@bases2);

    #clear bases
    my $base_new2 = create_domain($vm);
    @bases2 = ($base_new2->name);
    $entry->change( bases => \@bases2 );
    @new_bases = sort $entry->bases;
    is_deeply( \@new_bases ,\@bases2) or die Dumper(\@new_bases,\@bases2);

    _remove_domains($base_new, $base_new2);
}

sub test_change_bases_with_id($vm,$entry) {
    my $base_new = create_domain($vm);
    my @bases = $entry->bases();
    my @bases2 = sort (@bases,$base_new->id);
    my @bases2_expected = sort (@bases,$base_new->name);

    $entry->change( bases => \@bases2 );
    my @new_bases = sort $entry->bases;
    is_deeply( \@new_bases ,\@bases2_expected) or die Dumper(\@new_bases,\@bases2_expected);

    #clear bases
    my $base_new2 = create_domain($vm);
    @bases2 = ($base_new2->id);
    @bases2_expected = ($base_new2->name);
    $entry->change( bases => \@bases2 );
    @new_bases = sort $entry->bases;
    is_deeply( \@new_bases ,\@bases2_expected) or die Dumper(\@new_bases,\@bases2_expected);

    _remove_domains($base_new, $base_new2);
}

sub test_change_entry_next($vm, $booking) {
    test_change_entry_next_time($booking);
    test_change_entry_next_users($booking);
    test_change_entry_next_groups($booking);
    test_change_entry_next_bases($vm, $booking);
}

sub test_change_entry_next_users ($booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my @users = $entry->users();
    my $user_new = create_user(new_domain_name(),'a');
    my @users2 = sort (@users,$user_new->name);

    $entry->change_next( users => \@users2);

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );

    is_deeply([sort $new_entry->users],\@users2);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is_deeply([sort $entry0_b->users],[sort $entry0->users])
        or die Dumper($entry0_b->id,[sort $entry0_b->users], [sort $entry0->users]);

    is_deeply([sort $entry_b->users],\@users2);
    my $found = 0;
    for (@next_b) {
        is_deeply([sort $_->users],\@users2);
        $found++;
    }
    ok($found) or exit;

}

sub test_change_entry_next_groups($booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my @ldap_groups = $entry->ldap_groups();
    my $user_new = create_user(new_domain_name(),'a');
    my @ldap_groups2 = sort (@ldap_groups,$user_new->name);

    $entry->change_next( ldap_groups => \@ldap_groups2);

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );

    is_deeply([sort $new_entry->ldap_groups],\@ldap_groups2);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is_deeply([sort $entry0_b->ldap_groups],[sort $entry0->ldap_groups])
        or die Dumper($entry0_b->id,[sort $entry0_b->ldap_groups], [sort $entry0->ldap_groups]);

    is_deeply([sort $entry_b->ldap_groups],\@ldap_groups2);
    my $found = 0;
    for (@next_b) {
        is_deeply([sort $_->ldap_groups],\@ldap_groups2);
        $found++;
    }
    ok($found) or exit;

}

sub test_change_entry_next_bases($vm,$booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my @bases = $entry->bases();
    my $base_new = create_domain($vm);
    my @bases2 = sort (@bases,$base_new->name);

    $entry->change_next( bases => \@bases2);

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );

    is_deeply([sort $new_entry->bases],\@bases2);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is_deeply([sort $entry0_b->bases],[sort $entry0->bases])
        or die Dumper($entry0_b->id,[sort $entry0_b->bases], [sort $entry0->bases]);

    is_deeply([sort $entry_b->bases],\@bases2);
    my $found = 0;
    for (@next_b) {
        is_deeply([sort $_->bases],\@bases2);
        $found++;
    }
    ok($found) or exit;

    $base_new->remove(user_admin);
}

sub test_change_entry_next_time($booking) {
    my ($entry0, $entry,@next) = $booking->entries();
    my $time_start = $entry->_data('time_start');

    my ($min,$sec) = $time_start =~ /:(\d+):(\d+)/;
    my $new_min = ($min+1) % 60;
    $new_min = "0$new_min" if length($new_min)<2;

    my $new_time = "00:$new_min:$sec";

    isnt($new_time,$time_start) or exit;

    $entry->change_next( time_start => $new_time );

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );
    is($new_entry->_data('time_start'), $new_time) or exit;

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is($entry0_b->_data('time_start'), $entry0->_data('time_start'));
    is($entry_b->_data('time_start'), $new_time
        ,"Expecting changed ".$entry_b->id." ".$entry_b->_data('date_booking')) or exit;
    my $found = 0;
    for (@next_b) {
       is( $_->_data('time_start'), $new_time
         ,"Expecting no changed ".$_->id." ".$_->_data('date_booking')) or exit;
        $found++;
    }
    ok($found) or exit;

}

sub test_change_entry_day_of_week($vm, $booking) {
    test_change_entry_dow_time($booking);
    test_change_entry_dow_users($booking);
    test_change_entry_dow_groups($booking);
    test_change_entry_dow_bases($vm, $booking);

}

sub test_change_entry_dow_users ($booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my @users = $entry->users();
    my $user_new = create_user(new_domain_name(),'a');
    my @users2 = sort (@users,$user_new->name);

    $entry->change_next_dow( users => \@users2);

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );

    is_deeply([sort $new_entry->users],\@users2);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is_deeply([sort $entry0_b->users],[sort $entry0->users])
        or die Dumper($entry0_b->id,[sort $entry0_b->users], [sort $entry0->users]);

    is_deeply([sort $entry_b->users],\@users2);

    my $dow = DateTime::Format::DateParse
            ->parse_datetime($entry->_data('date_booking'))
            ->day_of_week;

    my ($found_yes, $found_no) = ( 0,0 );
    for my $curr_entry (@next_b) {
        my $date = DateTime::Format::DateParse
            ->parse_datetime($curr_entry->_data('date_booking'));
        if ($date->day_of_week eq $dow) {
            is_deeply([sort $curr_entry->users],\@users2)
            or die Dumper( $curr_entry->id ,[sort $curr_entry->users],\@users2);
            $found_yes++;
        } else {
            is_deeply([sort $curr_entry->users],\@users)
            or die Dumper( $curr_entry->id ,[sort $curr_entry->users],\@users);
            $found_no++;
        }

    }
    ok($found_yes);
    ok($found_no);
}

sub test_change_entry_dow_groups($booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my @ldap_groups = $entry->ldap_groups();
    my $user_new = create_user(new_domain_name(),'a');
    my @ldap_groups2 = sort (@ldap_groups,$user_new->name);

    $entry->change_next_dow( ldap_groups => \@ldap_groups2);

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );

    is_deeply([sort $new_entry->ldap_groups],\@ldap_groups2);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is_deeply([sort $entry0_b->ldap_groups],[sort $entry0->ldap_groups])
        or die Dumper($entry0_b->id,[sort $entry0_b->ldap_groups], [sort $entry0->ldap_groups]);

    is_deeply([sort $entry_b->ldap_groups],\@ldap_groups2);

    my $dow = DateTime::Format::DateParse
            ->parse_datetime($entry->_data('date_booking'))
            ->day_of_week;

    my ($found_yes, $found_no) = ( 0,0 );
    for my $curr_entry (@next_b) {
        my $date = DateTime::Format::DateParse
            ->parse_datetime($curr_entry->_data('date_booking'));
        if ($date->day_of_week eq $dow) {
            is_deeply([sort $curr_entry->ldap_groups],\@ldap_groups2);
            $found_yes++;
        } else {
            is_deeply([sort $curr_entry->ldap_groups],\@ldap_groups);
            $found_no++;
        }

    }
    ok($found_yes);
    ok($found_no);

}

sub test_change_entry_dow_bases($vm,$booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my @bases = $entry->bases();
    my $base_new = create_domain($vm);
    my @bases2 = sort (@bases,$base_new->name);

    $entry->change_next_dow( bases => \@bases2);

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );

    is_deeply([sort $new_entry->bases],\@bases2);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is_deeply([sort $entry0_b->bases],[sort $entry0->bases])
        or die Dumper($entry0_b->id,[sort $entry0_b->bases], [sort $entry0->bases]);

    is_deeply([sort $entry_b->bases],\@bases2);
    my $dow = DateTime::Format::DateParse
            ->parse_datetime($entry->_data('date_booking'))
            ->day_of_week;

    my ($found_yes, $found_no) = ( 0,0 );
    for my $curr_entry (@next_b) {
        my $date = DateTime::Format::DateParse
            ->parse_datetime($curr_entry->_data('date_booking'));
        if ($date->day_of_week eq $dow) {
            is_deeply([sort $curr_entry->bases],\@bases2);
            $found_yes++;
        } else {
            is_deeply([sort $curr_entry->bases],\@bases);
            $found_no++;
        }

    }
    ok($found_yes);
    ok($found_no);

    $base_new->remove(user_admin);
}

sub test_change_entry_dow_time($booking) {
    my ($entry0, $entry,@next) = $booking->entries();
    my $time_start = $entry->_data('time_start');

    my ($min,$sec) = $time_start =~ /:(\d+):(\d+)/;
    my $new_min = ($min+1) % 60;
    $new_min = "0$new_min" if length($new_min)<2;

    my $new_time = "00:$new_min:$sec";

    isnt($new_time,$time_start) or exit;

    my $dow = DateTime::Format::DateParse
            ->parse_datetime($entry->_data('date_booking'))->day_of_week;

    $entry->change_next_dow( time_start => $new_time );

    my $new_entry = Ravada::Booking::Entry->new( id => $entry->id );
    is($new_entry->_data('time_start'), $new_time) or exit;

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is($entry0_b->_data('time_start'), $entry0->_data('time_start'));
    is($entry_b->_data('time_start'), $new_time
        ,"Expecting changed ".$entry_b->id." ".$entry_b->_data('date_booking')) or exit;

    is(scalar(@next),scalar(@next_b));

    my ($found_yes, $found_no) = (0,0);

    for my $curr_entry (@next_b) {
        my $date = DateTime::Format::DateParse
            ->parse_datetime($curr_entry->_data('date_booking'));
        if ($date->day_of_week eq $dow) {
            is( $curr_entry->_data('time_start'), $new_time
            ,"Expecting changed ".$curr_entry->id." ".$curr_entry->_data('date_booking'))
            or exit;
            $found_yes++;
        } else {
            isnt( $curr_entry->_data('time_start'), $new_time
            ,"Expecting no changed ".$curr_entry->id." ".$curr_entry->_data('date_booking'))
            or exit;
            $found_no++;
        }
    }
    ok($found_yes);
    ok($found_no);

}

sub test_remove_entry($booking) {
    my ($entry) = $booking->entries();

    $entry->remove();

    my $removed_entry;
    eval { $removed_entry = Ravada::Booking::Entry->new( id => $entry->id ) };
    like($@,qr(not found));
    is($removed_entry,undef,Dumper($removed_entry)) or exit;
}

sub test_remove_entry_next($booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    $entry->remove_next();

    my $removed_entry;
    eval { $removed_entry = Ravada::Booking::Entry->new( id => $entry->id ) };
    like($@,qr(not found));
    is($removed_entry, undef);

    my ($entry0_b, $entry_b,@next_b) = $booking->entries();
    is($entry0_b->id(), $entry0->id);
    is($entry_b,undef);
    is(scalar ( @next_b ), 0);

    is(scalar($booking->entries),1);

}

sub test_remove_entry_day_of_week($booking) {
    my ($entry0, $entry,@next) = $booking->entries();

    my $dow = DateTime::Format::DateParse
            ->parse_datetime($entry->_data('date_booking'))->day_of_week;

    $entry->remove_next_dow( );

    my ($entry0_b, @next_b) = $booking->entries();
    is($entry0_b->id(), $entry0->id);

    my $removed_entry;
    my ($removed_yes, $removed_no) = (0,0);
    for my $curr_entry ($entry,@next) {
        my $date = DateTime::Format::DateParse
            ->parse_datetime($curr_entry->_data('date_booking'));
        $removed_entry = undef;
        eval { $removed_entry = Ravada::Booking::Entry->new( id => $curr_entry->id) };
        my $error = $@;
        like($@,qr/^$|not found/);
        if ($date->day_of_week == $dow) {
            is($removed_entry,undef, Dumper($removed_entry)) or exit;
            like($error, qr/ not found/);
            $removed_yes++;
        } else {
            ok($removed_entry);
            is($error,'') or exit;
            $removed_no++;
        }
    }
    ok($removed_yes);
    ok($removed_no);

}



sub test_booking_removed($id,@entries) {
    my $sth = connector->dbh->prepare("SELECT * from bookings where id=?");
    $sth->execute($id);
    my ($found) = $sth->fetchrow;

    is($found,undef,"Expecting $id removed from bookings");

    $sth = connector->dbh->prepare("SELECT * from booking_entries where id_booking=?");
    $sth->execute($id);
    ($found) = $sth->fetchrow;

    is($found,undef,"Expecting $id removed from booking_entries");

    for my $entry ( @entries ) {
        my $id_entry = $entry->id;

        $sth = connector->dbh->prepare("SELECT * from booking_entries where id=?");
        $sth->execute($id);
        ($found) = $sth->fetchrow;
        is($found,undef,"Expecting $id removed from booking_entries");

        for my $table (qw(booking_entry_users booking_entry_ldap_groups booking_entry_bases)) {
            $sth = connector->dbh->prepare("SELECT * from $table where id=?");
            $sth->execute($id_entry);
            ($found) = $sth->fetchrow;

            is($found,undef,"Expecting $id_entry removed from $table ") or exit;
        }
    }
}

sub _create_clones($vm) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $user_no_1 = create_user(new_domain_name(),1);
    my $user_no_2 = create_user(new_domain_name(),1);
    my $clone_no1 = $base->clone(user => $USER_YES_2
        , name => new_domain_name."-no1"
    );

    my $clone_no2 = $base->clone(user => $user_no_1
        , name => new_domain_name."-no2"
    );

    my $clone_as = $base->clone(user => $user_no_2
        , name => new_domain_name."-autostart"
    );
    $clone_as->autostart(1, user_admin);

    return($clone_no1, $clone_no2, $clone_as, $base);
}

sub test_conflict($vm) {
    my $base = create_domain($vm);
    test_conflict_hour_sharp($vm, $base);
    test_conflict_exact($vm, $base);
    test_conflict_before($vm, $base);
    test_conflict_after($vm, $base);
    test_conflict_over($vm, $base);

    test_non_conflict_before($vm, $base);
    test_non_conflict_after($vm, $base);

    test_conflict_day_of_week_exact($vm, $base);
    test_conflict_day_of_week_partial($vm, $base);
    test_non_conflict_day_of_week($vm, $base);

    $base->remove(user_admin);
}

sub test_list_machines_user($vm) {

    my $list = rvd_front->list_machines_user(user_admin);

    # admin can see all the bases
    is(scalar(@$list),3) or confess Dumper($list);

    # user allowed can see booked base
    $list= rvd_front->list_machines_user($USER_YES_1);
    is(scalar(@$list),1) or exit;

    # user not allowed sees no bases
    $list= rvd_front->list_machines_user($USER_NO);
    is(scalar(@$list),0,"Expecting no access to ".$USER_NO->name
        ." (admin = ".$USER_NO->is_admin.")") or exit;

    my ($entry_data) = Ravada::Booking::bookings_range();
    ok($entry_data,"Expected defined first entry data in bookings range");
    ok(exists $entry_data->{id} && defined $entry_data->{id},"Expecting entry data id "
        .Dumper($entry_data)) or exit;
    my $entry = Ravada::Booking::Entry->new( id => $entry_data->{id} );
    my @bases = $entry->bases_id();
    my $id_base = $bases[0];
    my $bookings = Ravada::Booking::bookings_week(id_base => $id_base);

    # Booking with no bases allows all the bases
    $entry->change( bases => [] );
    my $entry2 = Ravada::Booking::Entry->new( id => $entry_data->{id} );
    is(scalar($entry2->bases),0);
    $list= rvd_front->list_machines_user($USER_YES_1);
    is(scalar(@$list),2) or exit;
    $entry->change( bases => \@bases );
    $entry2 = Ravada::Booking::Entry->new( id => $entry_data->{id} );
    is_deeply([$entry2->bases_id],\@bases);
    my $bookings2 = Ravada::Booking::bookings_week(id_base => $id_base);

    is_deeply($bookings2, $bookings) or exit;
}

sub _check_no_bookings() {
    for my $table ( qw(Bookings Booking_entries Booking_entry_users Booking_entry_ldap_groups Booking_entry_bases Domains)) {
        my $sth = connector->dbh->prepare("SELECT * FROM $table");
        $sth->execute();
        my @found;

        while ( my $row = $sth->fetchrow_hashref ) {
            push @found,($row);
        }
        is(scalar(@found),0,"checking $table empty") or confess Dumper(\@found);
    }
}

sub test_config {
    init();
    my $config = { 'dir_rrd' => '/var/tmp/ravada/rrd'};
    init($config,1,1);

    is(rvd_front->feature('ldap'), 0);

    eval {
        rvd_back->setting("/backend/bookings",1);
    };
    like($@, qr/LDAP required/i);

    is(rvd_back->setting('/backend/bookings'),1);
}

sub _test_list_yes($user, @bases) {
    my $list = rvd_front->list_machines_user($user);
    for my $base ( @bases ) {
        my ($found) = grep { $_->{name} eq $base->name} @$list;
        ok($found,"Expecting ".$base->name." in ".Dumper($list));
    }
}

sub _test_list_no($user, @bases) {
    my $list = rvd_front->list_machines_user($user);
    for my $base ( @bases ) {
        my ($found) = grep { $_->{name} eq $base->name} @$list;
        ok(!$found,"Expecting no ".$base->name." in ".Dumper($list));
    }
}


sub _create_base_hd($vm, $id_hd) {
    my $base_hd = create_domain($vm);
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $base_hd->id
        ,name => 'usb'
    );
    wait_request(debug => 0);
    $base_hd->add_host_device($id_hd);
    $base_hd->prepare_base(user_admin);
    $base_hd->is_public(1);
    return $base_hd;
}

sub test_booking_host_devices($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($usb_hd) = grep { $_->{name} =~ /USB/ } @$templates;

    die "Error: no USB template found ".Dumper($templates) if !$usb_hd;

    my $id_hd = $vm->add_host_device(template => $usb_hd->{name});
    my $hd = Ravada::HostDevice->search_by_id($id_hd);

    if ($vm->type eq 'KVM') {
        my $config = config_host_devices('usb');
        if (!$config) {
            diag("No USB config in t/etc/host_devices.conf");
            return;
        }
        $hd->_data('list_filter' => $config);
    }

    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $base_hd = _create_base_hd($vm, $id_hd);

    _test_list_yes($USER_LOCAL_YES_1, $base, $base_hd);
    _test_list_yes($USER_LOCAL_NO, $base, $base_hd);

    my $booking = _create_booking(undef , { host_devices => 1 } );

    for my $entry ( $booking->entries ) {
        $entry->change('time_end' => _now_seconds(120));
        ok($entry->_data('options')) or exit;
        is($entry->_data('options')->{host_devices},1) or die Dumper($entry->_data('options'));
        $entry->change( local_groups => $GROUP_LOCAL->id );
    }
    my ($entry) = $booking->entries;
    $entry->change('options' => { host_devices => 2 });
    my ($entry_changed) = $booking->entries;
    is($entry_changed->_data('options')->{host_devices},2) or die Dumper($entry_changed->_data('options'));
    $entry->change('options' => { host_devices => 1 });

    _test_list_yes($USER_LOCAL_YES_1, $base, $base_hd);
    _test_list_yes($USER_LOCAL_NO, $base);
    _test_list_no($USER_LOCAL_NO, $base_hd);
    #####
    #
    # list yes

    #####
    #
    # list no
    my $list_no = rvd_front->list_machines_user($USER_LOCAL_NO);
    ok(grep { $_->{name} eq $base->name} @$list_no) or die Dumper($list_no);
    ok(!grep { $_->{name} eq $base_hd->name} @$list_no) or die Dumper($list_no);

    my $clone_yes = $base->clone(name => new_domain_name, user => $USER_LOCAL_YES_1);
    my $clone_hd_yes = $base_hd->clone(name => new_domain_name, user => $USER_LOCAL_YES_1);

    # user allowed can start anything
    is(Ravada::Booking::user_allowed($USER_LOCAL_YES_1, $clone_yes->id),1);
    is(Ravada::Booking::user_allowed($USER_LOCAL_YES_1, $clone_hd_yes->id),1);
    for my $c ( $clone_yes, $clone_hd_yes) {
        my $req_start_clone = Ravada::Request->start_domain(
            uid => $c->id_owner
            ,id_domain => $c->id
        );
        wait_request(check_error => 0);
        is($req_start_clone->error,'');
        is ($c->is_active,1);
    }

    my $clone_no = $base->clone(name => new_domain_name, user => $USER_LOCAL_NO);
    my $clone_hd_no = $base_hd->clone(name => new_domain_name, user => $USER_LOCAL_NO);

    # User allowed only to non_hd bases
    #   allowed
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO, $clone_yes->id),1) or exit;
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO, $base->id),1) or exit;
    #   denied
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO, $clone_hd_yes->id),0);
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO, $base_hd->id),0);
    #   allow when disabled host_devices
    is(Ravada::Booking::user_allowed($USER_LOCAL_NO, $clone_hd_yes->id,0),1);

    # can start when forcing no host devices
    my $req_start_hd_without = Ravada::Request->start_domain(uid => $clone_hd_no->id_owner, id_domain => $clone_hd_no->id, enable_host_devices => 0);

    Ravada::Request->enforce_limits(_force => 1);
    wait_request(check_error => 0, debug => 0);
    is($req_start_hd_without->error,'');
    is($clone_hd_no->is_active,1) or die $clone_hd_no->name;

    # user denied can not start hd
    my $req_start_no = Ravada::Request->start_domain(uid => $clone_no->id_owner, id_domain => $clone_no->id);
    my $req_start_hd_no = Ravada::Request->start_domain(uid => $clone_hd_no->id_owner, id_domain => $clone_hd_no->id);
    wait_request(check_error => 0);
    is($req_start_no->error,'');
    like($req_start_hd_no->error,qr/./);

    is($clone_no->is_active,1) or die $clone_no->name;
    is($clone_hd_no->is_active,0);

    $booking->remove();
    remove_domain($base);
    remove_domain($base_hd);
}

###################################################################

test_config();

init('t/etc/ravada_ldap.conf', 1 , 1); # flush rvd_back
clean();
$TZ = DateTime::TimeZone->new(name => rvd_front->setting('/backend/time_zone'));

delete $Ravada::CONFIG->{ldap}->{ravada_posix_group};
_init_ldap();
_init_local();

rvd_back->setting('/backend/bookings', 1);

for my $vm_name ( vm_names()) {
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        diag("Testing booking in $vm_name");

        test_booking_host_devices($vm);

        test_bookings_week_2days($vm);
        test_search_change_remove_booking($vm);

        test_booking($vm , _create_clones($vm));

        test_conflict($vm);
        test_booking_datetime($vm);

        for my $ldap (0, 1) {
            for my $local ( 0, 1) {
                my $mode = {};
                $mode->{'ldap'} = $ldap;
                $mode->{'local'} = $ldap;
                lock_hash(%$mode);
                test_booking_oneday($vm , $mode);
                test_booking_oneday_dow($vm, $mode);
                test_booking_oneday_date_end($vm, $mode);
                test_booking_oneday_date_end_dow($vm, $mode);
            }
        }

        _check_no_bookings();

    }
}

end();
done_testing();
