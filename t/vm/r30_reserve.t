use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use DateTime;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my $GROUP = 'students';
my ($USER_YES_NAME_1, $USER_YES_NAME_2, $USER_NO_NAME) = ( 'mcnulty','bunk','stringer');
my ($USER_2_NAME,$USER_3_NAME)=('bubbles','walon');

use_ok('Ravada::Booking');

###################################################################
my ($USER_YES_1, $USER_YES_2, $USER_NO, $USER_2, $USER_3);

sub _init_ldap(){

    my $group = _add_posix_group();
    my $n = 0;
    for my $name ($USER_YES_NAME_1, $USER_YES_NAME_2, $USER_NO_NAME, $USER_2_NAME, $USER_3_NAME) {
        create_ldap_user($name,$n,1);

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
    $group->add(memberUid => $user_name);
    my $mesg = $group->update($ldap);
    # 20: no such object
    die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code != 20;

    my @member = $group->get_value('memberUid');

    my ($found) = grep /^$user_name$/,@member;

    ok( $found, "Expecting $user_name in $GROUP");
}

sub _add_posix_group {
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();

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

sub _now_days($days) {
    my $now = DateTime->now();
    return $now->add( days => $days );
}


sub _now_seconds($seconds) {
    my $now = DateTime->now();
    return $now->add( seconds => $seconds)->hms();
}

sub _date($dt) {
    confess if !ref($dt);
    return $dt->ymd;
}

# our tests won't work if we are at hh:59
sub _wait_end_of_hour() {
    for (;;) {
        my $now = DateTime->now();
        return if $now->minute <59;
        diag("Waiting for end of hour to run booking tests "
            .$now->hour.":".$now->minute.".".$now->second);
        sleep 1;
    }
}

sub test_booking($vm, $clone0_no1, $clone0_no2, $clone0_as) {

    $clone0_no1->start(user => user_admin);
    $clone0_no2->start(user => user_admin);
    $clone0_as->start(user => user_admin);

    my $seconds = 60;
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);
    my $clone_no = $base->clone(name => new_domain_name, user => $USER_NO);
    my $clone_yes = $base->clone(name => new_domain_name, user => $USER_YES_1);

    _wait_end_of_hour();
    my $date_start = _yesterday();
    my $date_end = _date(_now_days(7));
    my $time_start = _now_seconds(-10);
    my $time_end = _now_seconds($seconds);

    my $today = DateTime->now();
    my $tomorrow = DateTime->now()->add(days => 1);

    my $sth = connector->dbh->prepare("DELETE FROM users WHERE id=? ");
    $sth->execute($USER_2->id);

    my $booking = Ravada::Booking->new(
        id_base => $base->id
        , ldap_groups => $GROUP
        , users => [$USER_2_NAME , $USER_3->id]
        , date_start => $date_start
        , date_end => $date_end
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $today->day_of_week.''.$tomorrow->day_of_week
        , title => 'comunicacions multimedia'
        , description => 'blablabla'
        , id_owner => user_admin->id
    );

    test_bookings_week($base->id);

    my @entries = $booking->entries();
    is(scalar(@entries),3);
    for my $entry ( @entries ) {
        my @groups = $entry->groups;
        is($groups[0], $GROUP);
        my @users = $entry->users();
        is(scalar(@users),2,Dumper(\@users));
    };
    is(Ravada::Booking::user_allowed($USER_YES_1, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_YES_1->id, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_YES_1->name, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_2_NAME, $base->id),1, $USER_2_NAME) or exit;
    is(Ravada::Booking::user_allowed($USER_3, $base->id),1);
    is(Ravada::Booking::user_allowed($USER_NO->name, $base->id ),0);
    is(Ravada::Booking::user_allowed($USER_NO->id, $base->id ),0);
    is(Ravada::Booking::user_allowed($USER_NO, $base->id ),0)
        or die Dumper(''.localtime(time),\@entries);

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
    _remove_domains($base);

}

sub test_bookings_week($id_base) {
    my $today = DateTime->now();

    my $bookings = Ravada::Booking::bookings_week(id_base => $id_base);
    my $dow = $today->day_of_week - 1;
    my $hour = $today->hour;
    $hour = "0$hour" if length($hour) < 2;

    my $book_today = $bookings->{"$dow.$hour"};
    my $key_tomorrow = ''.($dow+1).".$hour";
    my $book_tomorrow = $bookings->{$key_tomorrow};

    ok($book_today," Expecting a booking for $dow.$hour ".Dumper($bookings)) or exit;
    ok($book_tomorrow," Expecting a booking for $key_tomorrow ".Dumper($bookings))
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
    rvd_back->_process_requests_dont_fork(1);

    is($clone_as->is_active,1) or exit;
    is($clone_no1->is_active,0,$clone_no1->name." should be down") or exit;
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

sub test_conflict_day_of_week_exact($vm, $base) {
    my $today = DateTime->now();
    my $tomorrow = DateTime->now()->add(days => 1);
    my $dow = $today->day_of_week.''.$tomorrow->day_of_week;
    test_conflict_generic_dow($vm,$base,"09:00","11:00",$dow,6);
}

sub test_conflict_day_of_week_partial($vm, $base) {
    my $today = DateTime->now();
    my $tomorrow = DateTime->now()->add(days => 1);
    my $dow = $tomorrow->day_of_week;
    test_conflict_generic_dow($vm,$base,"09:00","11:00",$dow,3);
}

sub test_non_conflict_day_of_week($vm, $base) {
    my $day_after_tomorrow = DateTime->now()->add(days => 2);
    my $dow = $day_after_tomorrow->day_of_week;
    test_conflict_generic_dow($vm,$base,"09:00","11:00",$dow,0);
}

sub test_conflict_generic_dow($vm, $base, $conflict_start, $conflict_end, $dow, $n_expected=undef) {
    return test_conflict_generic( $vm, $base, $conflict_start, $conflict_end, $n_expected, $dow);
}


sub test_conflict_generic($vm, $base, $conflict_start, $conflict_end, $n_expected=undef, $dow=undef) {

    my $date_start = _yesterday();
    my $date_end = _now_days(15);
    my $time_start = "09:00";
    my $time_end = "11:00";

    my $today = DateTime->now();
    my $tomorrow = DateTime->now()->add(days => 1);
    my $booking = Ravada::Booking->new(
        id_base => $base->id
        , ldap_groups => $GROUP
        , date_start => $date_start
        , date_end => $date_end
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $today->day_of_week.''.$tomorrow->day_of_week
        , title => 'garden'
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

    $base->remove(user_admin);
}



sub test_search_booking($vm) {

    my $base = create_domain($vm);
    _wait_end_of_hour();
    my $date_start = _yesterday();
    my $date_end = _now_days(15);
    my $time_start = _now()->hms;
    my $time_end = _now_seconds(5);

    my $today = DateTime->now();
    my $tomorrow = DateTime->now()->add(days => 1);
    my $booking = Ravada::Booking->new(
        id_base => $base->id
        , ldap_groups => $GROUP
        , date_start => $date_start
        , date_end => $date_end
        , time_start => $time_start
        , time_end => $time_end
        , day_of_week => $today->day_of_week.''.$tomorrow->day_of_week
        , title => 'garden'
        , description => 'blablabla long'
        , id_owner => user_admin->id
        , date_created => time
        , date_changed => time
    );
    my @entries = $booking->entries();
    is(scalar @entries,6,Dumper(\@entries)) or exit;

    my $booking2 = Ravada::Booking->search( date => _today());
    ok($booking2,"Expecting booking for today") or exit;
    is($booking2->id, $booking->id);

    $booking2 = Ravada::Booking->search( title => 'arden' );
    is($booking2->id, $booking->id);

    $booking2 = Ravada::Booking->search( title => 'arden' , description => 'lon' );
    is($booking2->id, $booking->id);

    $booking2->change( description => 'beblebleble do do');

    my $booking3 = Ravada::Booking->new( id => $booking2->id );
    is($booking3->id, $booking2->id);

    $booking2->remove();

    $booking2 = Ravada::Booking->search( title => 'arden' );
    is($booking2, undef);
    test_booking_removed($booking3->id, @entries);

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

        for my $table (qw(booking_entry_users booking_entry_ldap_groups)) {
            $sth = connector->dbh->prepare("SELECT * from $table where id=?");
            $sth->execute($id_entry);
            ($found) = $sth->fetchrow;

            is($found,undef,"Expecting $id_entry removed from $table ");
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

    return($clone_no1, $clone_no2, $clone_as);
}

sub test_conflict($vm) {
    my $base = create_domain($vm);
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

###################################################################

init('t/etc/ravada_ldap.conf');
clean();

delete $Ravada::CONFIG->{ldap}->{ravada_posix_group};
_init_ldap();

for my $vm_name ( vm_names()) {
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        test_conflict($vm);
        test_search_booking($vm);

        test_booking($vm , _create_clones($vm));
    }
}

end();
done_testing();
