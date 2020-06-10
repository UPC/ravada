package Ravada::Booking;

use Carp qw(carp croak);
use Data::Dumper;

use Moose;

use Ravada::Booking::Entry;

no warnings "experimental::signatures";
use feature qw(signatures);

our $CONNECTOR = \$Ravada::CONNECTOR;

sub BUILD($self, $args) {
    return $self->_open($args->{id}) if $args->{id};

    my $time_start = delete $args->{time_start} or confess "Error: missing time start";
    my $time_end = delete $args->{time_end} or confess "Error: missing time end";
    my $day_of_week = delete $args->{day_of_week} or confess "Error: missing day_of_week";

    my %entry;
    my @fields_entry = qw ( id_base ldap_groups users time_start time_end );
    for (@fields_entry) {
        $entry{$_} = delete $args->{$_};
    }

    $self->_insert_db($args);

    $entry{id_booking} = $self->id;
    $entry{time_start} = $time_start;
    $entry{time_end} = $time_end;
    $entry{title} = $args->{title};
    $entry{description} = $args->{description};

    my $date_start = _datetime(delete $args->{date_start});
    my $date_end = _datetime(delete $args->{date_end});

    my $date = $date_start;
    my %dow = map { $_ => 1 } split //,$day_of_week;
    for (;;) {
        if ( exists $dow{$date->day_of_week} ) {
            my $entry = Ravada::Booking::Entry->new(%entry, date_booking => $date->ymd);
        }
        $date->add( days => 1 );
        last if DateTime->compare($date, $date_end) >0;
    }

    return $self;
}

sub _datetime($dt) {
    return if ref($dt);
    my ($y,$m,$d) = split /-/,$dt;
    return DateTime->new( year => $y, month => $m, day => $d);
}

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

sub _insert_db($self, $field) {

    _fix_date_field('date_start',$field);
    _fix_date_field('date_end',$field);
    my $query = "INSERT INTO bookings "
            ."(" . join(",",sort keys %$field )." )"
            ." VALUES (". join(",", map { '?' } keys %$field )." ) "
    ;
    my $sth = $self->_dbh->prepare($query);
    eval { $sth->execute( map { $field->{$_} } sort keys %$field ) };
    if ($@) {
        #warn "$query\n".Dumper(\%field);
        confess $@;
    }
    $sth->finish;

    $sth = $self->_dbh->prepare("SELECT * FROM bookings WHERE title=? ");
    $sth->execute($field->{title});
    $self->{_data} = $sth->fetchrow_hashref;

}

sub _fix_date_field($name, $field) {
    return if !ref($field->{$name});
    my $dt = $field->{$name};
    $field->{$name} = $dt->year."-".$dt->month."-".$dt->day;
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
    return if !keys %$row;
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
    my $sth = $self->_dbh->prepare("DELETE FROM bookings WHERE id=? ");
    $sth->execute($self->id);
    delete $self->{_data};
}

sub _today() { return  DateTime->now->ymd }
sub _now() { return DateTime->now->hms }
sub _monday($date = DateTime->now) {
    for (0..6) {
        return $date if $date->day_of_week == 1;
        $date->add( days => -1);
    }
    confess "I didn find a monday from ".$date;
}

sub _date($dt) {
    return $dt->ymd;
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
    my $time = delete $args{time};
    #    my $time = ( delete $args{time} or   _now() );
    my $id_base = delete $args{id_base};

    confess "Error: Unknown fields ". Dumper(\%args) if keys %args;

    #create a query

    my $sql;
    my @args = ( $date );

    $sql = "SELECT id FROM booking_entries WHERE date_booking=?";
    if ($time) {
        $sql .= " AND time_start<=? AND time_end>=? ";
        push @args,($time, $time);
    }
    if ($id_base ) {
        $sql .= "AND id_base=? ";
        push @args,($id_base);
    }
    my $sth = _dbh->prepare($sql);
    $sth->execute(@args);
    my $id;
    my @found;
    $sth->bind_columns(\$id);
    while ($sth->fetch ) {
        push @found,Ravada::Booking::Entry->new(id => $id);
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
    $user_name = $user->name if ref($user);
    $user_name = _search_user_name($user) if !ref($user) && $user =~ /^\d+$/;

    confess"Undefined user name " if !defined $user_name;

    my $today = _today();
    my $now = _now();
    my $allowed =  1;
    for my $entry (Ravada::Booking::bookings( date => $today, time => $now)) {
        $allowed = 0;
        next if $entry->_data('id_base') != $id_base;
        for my $group_name ($entry->groups) {
            my $group = Ravada::Auth::LDAP->_search_posix_group($group_name);
            my @member = $group->get_value('memberUid');
            my ($found) = grep /^$user_name$/,@member;
            return 1 if $found;
        }
        for my $allowed_user_name ( $entry->users ) {
            return 1 if $user_name eq $allowed_user_name;
        }
    }
    return $allowed;
}

#sub bookings_week($id_base, $date=_monday(), $hour_start=8, $hour_end=20) {
sub bookings_week(%args) {
    # TODO: withou id_base
    my $id_base = delete $args{id_base};
    my $date = ( delete $args{date} or _monday) ;

    my %booking;
    for my $dow ( 0 .. 6 ) {
        for my $entry ( Ravada::Booking::bookings( date => _date($date)
                ,id_base => $id_base
            ) ) {
            my ($hour) = $entry->_data('time_start') =~ /^(\d+)/;
            my ($hour_end) = $entry->_data('time_end') =~ /^(\d+)/;
            for (;;) {
                $hour = "0".$hour while length($hour)<2;
                my $key = "$dow.$hour";
                $booking{$key} = $entry->{_data};
                last if ++$hour>$hour_end;
            }
        }
        $date->add(days => 1);
    }
    return \%booking;
}

1;
