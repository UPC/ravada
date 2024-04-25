package Ravada::Booking;

use Carp qw(carp croak);
use Data::Dumper;

use DateTime::Format::DateParse;
use Moose;

use Ravada::Booking::Entry;
use Ravada::Front;

no warnings "experimental::signatures";
use feature qw(signatures);

our $CONNECTOR = \$Ravada::CONNECTOR;
our $TZ;

sub BUILD($self, $args) {
    return $self->_open($args->{id}) if $args->{id};

    my $date = delete $args->{date_booking};
    my $date_start = delete $args->{date_start};
    my $date_end = delete $args->{date_end};

    confess "Error: supply either date or date_start"
    if (!defined $date && !defined $date_start);

    $date = $date_start     if !defined $date;
    $date_end = $date       if !defined $date_end;

    $date = _datetime($date);
    $date_end = _datetime($date_end);

    my $time_start = delete $args->{time_start} or confess "Error: missing time start";
    my $time_end = delete $args->{time_end} or confess "Error: missing time end";
    my $day_of_week = delete $args->{day_of_week};

    my %entry;
    my @fields_entry = qw ( bases ldap_groups local_groups users time_start time_end );
    for (@fields_entry) {
        $entry{$_} = delete $args->{$_};
    }

    my %fields = map { $_ => 1 } keys %$args;
    delete @fields{'title','id_owner','description','date_created','local_groups'};
    die "Error: unknown arguments ".(join("," , keys %fields)) if keys %fields;

    $self->_insert_db(%$args
        , date_start => $date->ymd
        , date_end => $date_end->ymd
    );

    $entry{id_booking} = $self->id;
    $entry{time_start} = $time_start;
    $entry{time_end} = $time_end;
    $entry{title} = $args->{title};
    $entry{description} = $args->{description};

    $day_of_week = $date->day_of_week   if !$day_of_week || $day_of_week =~ /^0+$/;

    my %dow = map { $_ => 1 } split //,$day_of_week;
    my $saved = 0 ;
    for (;;) {
        if ( $dow{$date->day_of_week()} ) {
            my $entry = Ravada::Booking::Entry->new(%entry, date_booking => $date->ymd);
            $saved++;
        }
        $date->add( days => 1 );
        last if DateTime->compare($date, $date_end) >0;
    }

    die "Error: No entries were saved $date - $date_end\n".Dumper(\%dow)
    if !$saved;

    return $self;
}

sub _datetime($dt) {
    return $dt if ref($dt);
    return DateTime::Format::DateParse->parse_datetime($dt);
}

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

sub _insert_db($self, %field) {
    my $sth = $self->_dbh->prepare("SELECT * FROM bookings");
    $sth->execute();
    my $cols = $sth->{NAME};
    foreach my $col (keys %field) {
        delete $field{$col} if !grep( /^$col$/, @$cols );
    }
    my $query = "INSERT INTO bookings "
            ."(" . join(",",sort keys %field )." )"
            ." VALUES (". join(",", map { '?' } keys %field )." ) "
    ;
    $sth = $self->_dbh->prepare($query);
    eval { $sth->execute( map { $field{$_} } sort keys %field ) };
    if ($@) {
        warn "$query\n".Dumper(\%field);
        confess $@;
    }
    my $new_id = Ravada::Utils::last_insert_id($self->_dbh) or confess "Unkown last id";
    $sth->finish;

    $sth = $self->_dbh->prepare("SELECT * FROM bookings WHERE id=? ");
    $sth->execute($new_id);
    $self->{_data} = $sth->fetchrow_hashref;

}

sub _fix_date($dt) {
    return if !ref($$dt);
    my $date = $$dt->year."-".$$dt->month."-".$$dt->day;
    $$dt = $date;
}

sub _fix_time($time) {
    confess "Error in time " if ref($$time);
    my ($h,$m, $s) = split /:/ ,$$time;
    confess "Error in time ".Dumper($time) if!defined $h || !defined $m
        || $h>23 || $m>59 || $s>59;
    $$time = $h*3600 + $m*60 + $s;
}

sub _open($self, $id) {
    my $sth = $self->_dbh->prepare("SELECT * FROM bookings WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    die "Error: booking $id not found " if !$row || !keys %$row || !exists $row->{id};
    $self->{_data} = $row;

    return $self;
}

sub id($self) { return $self->_data('id'); }

sub search($self, %args) {
    _init_connector();
    return $self->_search_date($args{date}) if $args{date};

    return $self->_search_like(%args);
}

sub _data($self, $field) {
    confess if !ref($self);
    confess "Error: field '$field' doesn't exist in ".Dumper($self->{_data}, $self)
        if !exists $self->{_data}->{$field};

    return $self->{_data}->{$field};
}


sub _dbh($self=undef) {
    _init_connector();
    return $$CONNECTOR->dbh;
}

sub _search_date($self,$date) {
    my $sth = $self->_dbh->prepare(
        "SELECT id FROM bookings "
        ."WHERE date_start <= ? "
        ."AND date_end >= ? "
    );
    _fix_date(\$date);
    $sth->execute($date, $date);
    return $self->_found($sth);
}

sub _search_datetime($self, %args) {
    my $date = delete $args{date} or confess "Error: missing date";
    my $time = delete $args{time} or confess "Error: missing time";
    my $id_base = delete $args{id_base} or confess "Error: missing id_base";
    my $sth = $self->_dbh->prepare(
        "SELECT id FROM booking_entries "
        ."WHERE date_booking = ? "
        ." AND time_start <= ? "
        ." AND time_end >= ? "
        ." AND id_base = ? "
    );
    _fix_date(\$date);
    _fix_time(\$time);
    $sth->execute($date , $time, $time, $id_base);
    return $self->_found($sth);
}

sub _found($self, $sth) {
    my @found;
    while (my $id = $sth->fetchrow) {
        push @found, Ravada::Booking->new( id => $id);
    }
    $sth->finish;

    return if !scalar(@found);
    return $found[0] if scalar(@found) == 1;
    return @found;
}

sub _search_like($self, %field) {
    my $sql = '';
    my @values;
    for my $name(sort keys %field) {
        $sql .= "AND " if $sql;
        if ($name eq 'title' || $name eq 'description') {
            $sql .=" $name like ? ";
            push @values,('%'.$field{$name}.'%');
        } else {
            $sql .=" $name = ? ";
            push @values,($field{$name});
        }
    }

    $sql = "SELECT id FROM bookings WHERE $sql";

    my $sth = $self->_dbh->prepare($sql);
    $sth->execute(@values);

    return $self->_found($sth);
}

sub change($self, %field) {
    my $sql = '';
    for my $name(sort keys %field) {
        $sql .= " , " if $sql;
        $sql .=" $name = ? "
    }

    $sql = "UPDATE bookings SET $sql WHERE id=?";

    my @values = map { $field{$_} } sort keys %field;

    my $sth = $self->_dbh->prepare($sql);
    $sth->execute(@values, $self->id);

    return $self->_open($self->id);
}

sub remove($self) {
    # TODO: make foreign keys delete cascade work
    for my $entry ( $self->entries ) {
        $entry->remove();
    }
    my $sth = $self->_dbh->prepare("DELETE FROM bookings WHERE id=? ");
    $sth->execute($self->id);
    delete $self->{_data};
}

sub TZ() {
    return $TZ if defined $TZ;
    $TZ = Ravada::Front->setting('/backend/time_zone');
}

sub _today() { return  DateTime->from_epoch( epoch => time(), time_zone => TZ())->ymd }
sub _now() { return DateTime->from_epoch( epoch => time(), time_zone => TZ())->hms }
sub _monday($date = DateTime->from_epoch( epoch => time(), time_zone => TZ())) {
    for (0..6) {
        return $date if $date->day_of_week == 1;
        $date->add( days => -1);
    }
    confess "I didn find a monday from ".$date;
}

sub _seconds($time) {
    $time .= ":00" if $time =~ /^\d+:\d+$/;
    confess "Error: time format wrong '$time'" if $time !~/^(\d+):(\d+):(\d+)?$/;
    confess "Error: time format wrong '$time'" if !defined $1 || !defined $2 || !defined $3;

    return $1 * 60*60 + $2*60 + $3;
}

sub entries($self) {
    my $sth = $self->_dbh->prepare("SELECT id FROM booking_entries WHERE id_booking=? ");
    $sth->execute($self->id);

    my @entries;

    my $id;
    $sth->bind_columns(\$id);
    while ($sth->fetch) {
        push @entries,(Ravada::Booking::Entry->new( id => $id));
    }
    return @entries;
}

sub bookings(%args) {
    my $date = ( delete $args{date} or _today() );
    $date = $date->ymd if ref($date) =~ /DateTime/;
    my $time = delete $args{time};
    #    my $time = ( delete $args{time} or   _now() );
    my $id_base = delete $args{id_base};

    confess "Error: Unknown fields ". Dumper(\%args) if keys %args;

    #create a query

    my $sql;
    my @args = ( $date );

    $sql = "SELECT id FROM booking_entries WHERE date_booking=?";
    if ($time) {
        $sql .= " AND time_start<=? AND time_end>? ";
        push @args,($time, $time);
    }
    my $sth = _dbh->prepare($sql);
    $sth->execute(@args);
    my $id;
    my @found;
    $sth->bind_columns(\$id);
    while ($sth->fetch ) {
        my $entry = Ravada::Booking::Entry->new(id => $id);
        push @found,($entry)
        if !defined $id_base || grep { $_ == $id_base } $entry->bases_id;
    }
    return @found;
}

sub _search_user_name($id_user) {
    my $sth = _dbh->prepare("SELECT name FROM users WHERE id=? ");
    $sth->execute($id_user);
    my ($name) = $sth->fetchrow();
    return $name;
}

sub user_allowed($user,$id_base) {
    my $user_name = $user;
    if ( ref($user) ) {
        $user_name = $user->name;
        return 1 if $user->is_admin;
    }
    confess "Error: undefined user " if !defined $user;
    $user_name = _search_user_name($user) if !ref($user) && $user =~ /^\d+$/;

    confess"Undefined user name " if !defined $user_name;

    my $today = _today();
    my $now = _now();

    # allowed by default if there are no current bookings right now
    my $allowed =  1;

    for my $entry (Ravada::Booking::bookings( date => $today, time => $now)) {
        # first we disallow because there is a booking
        $allowed = 0;
        next unless !scalar($entry->bases_id) || grep { $_ == $id_base } $entry->bases_id;
        # look no further if user is allowed
        return 1 if $entry->user_allowed($user_name);
    }
    if (!$allowed && !ref($user)) {
        my $user0 = Ravada::Auth::SQL->new(name => $user_name);
        return 1 if $user0->is_admin;
    }
    return $allowed;
}


#sub bookings_week($id_base, $date=_monday(), $hour_start=8, $hour_end=20) {
sub bookings_week(%args) {
    my $id_base = delete $args{id_base};
    my $date = ( delete $args{date} or _monday) ;
    $date = DateTime::Format::DateParse->parse_datetime($date) if !ref($date);
    my $user_name = delete $args{user_name};
    confess "Error: unknown field ".Dumper(\%args) if keys %args;
    my %booking;
    for my $dow ( 0 .. 6 ) {
        for my $entry ( Ravada::Booking::bookings( date => $date) ) {
            next if defined $id_base && ! grep { $_ == $id_base } $entry->bases_id;
            my ($hour) = $entry->_data('time_start') =~ /^(\d+)/;
            my ($hour_end) = $entry->_data('time_end') =~ /^(\d+)/;
            for (;;) {
                $hour = "0".$hour while length($hour)<2;
                my $key = "$dow.$hour";
                push @{$booking{$key}}, $entry->{_data} if !$user_name
                    || $entry->user_allowed($user_name);
                last if ++$hour>=$hour_end;
            }
        }
        $date->add(days => 1);
    }
    return \%booking;
}

sub bookings_range(%args) {
    my $id_base = delete $args{id_base};
    my $id_entry = delete $args{id};
    my $date_start = ( delete $args{date_start} or _today ) ;
    $date_start = DateTime::Format::DateParse->parse_datetime($date_start) if !ref($date_start);
    $date_start->set( hour => 0, minute => 0, second => 0);

    my $date_end = ( delete $args{date_end} or $date_start->clone) ;
    $date_end = DateTime::Format::DateParse->parse_datetime($date_end) if !ref($date_end);
    $date_end->set( hour => 0, minute => 0, second => 0);

    my $time_start = ( delete $args{time_start} or '00:00');
    my $time_end = ( delete $args{time_end} or '23:59');

    my $day_of_week = ( delete $args{day_of_week} or '');
    confess "Error: day of week must be between 0 and 7 , $day_of_week"
    if $day_of_week && $day_of_week !~ /^[0-7]+/;
    $day_of_week = '' if !$day_of_week || $day_of_week =~ /^0+$/;

    my %day_of_week = map { $_ => 1 } split //,$day_of_week;

    #todo check date_end > date_start
    confess "Error end must be after start ".$date_start." ".$date_end
    if DateTime->compare( $date_start, $date_end) > 0;

    my $show_user_allowed = delete $args{show_user_allowed};

    confess "Error: unknown field ".Dumper(\%args) if keys %args;

    #    warn "\n\nchecking $date_start - $date_end | $time_start - $time_end $day_of_week\n".Dumper(\%day_of_week);

    my @bookings ;
    for (# no init
        # check last
        ; DateTime->compare( $date_start, $date_end) <= 0
        # next
        ; $date_start->add( days => 1)) {

        if ($day_of_week) {
            next if !$day_of_week{$date_start->day_of_week};
        }
        for my $entry ( Ravada::Booking::bookings(date => $date_start ) ) {
            # prevent check conflict in same entry
            next if $id_entry && $entry->{_data}->{id} eq $id_entry;
            if (
                (_seconds($entry->{_data}->{time_start}) <= _seconds($time_start)
                && _seconds($entry->{_data}->{time_end}) > _seconds($time_start))
             ||
                (_seconds($entry->{_data}->{time_end}) >= _seconds($time_end)
                && _seconds($entry->{_data}->{time_start}) < _seconds($time_end))
            ||
                (_seconds($entry->{_data}->{time_start}) < _seconds($time_end)
                && _seconds($entry->{_data}->{time_end}) >= _seconds($time_end))
            ||
                (_seconds($entry->{_data}->{time_start}) >= _seconds($time_start)
                && _seconds($entry->{_data}->{time_start}) < _seconds($time_end))
            ) {

                $entry->{_data}->{user_allowed} = $entry->user_allowed($show_user_allowed)
                if $show_user_allowed;
                my $booking = Ravada::Booking->new( id => $entry->{_data}->{id_booking});
                $entry->{_data}->{background_color} = $booking->{_data}->{background_color};
                push @bookings,$entry->{_data}
            }

        }
    }
    return @bookings;
}

1;
