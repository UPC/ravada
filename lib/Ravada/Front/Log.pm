package Ravada::Front::Log;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use DateTime;
use DateTime::Duration;


use Ravada::Utils;

no warnings "experimental::signatures";
use feature qw(signatures);

my $CONNECTOR;

our $LOCAL_TZ = DateTime::TimeZone->new(name => 'local');

sub _init_connector {
    $CONNECTOR = \$Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR   if !$$CONNECTOR;
}

sub list_active_recent($unit='hours',$time=1, $id_base=undef) {

    _init_connector();
    my $t = DateTime->from_epoch( epoch => time() , time_zone => $LOCAL_TZ);
    $t -= DateTime::Duration->new( $unit => $time);
    my $minute = $t->minute;
    $minute = "00" if $unit eq 'hours' && $time>3 || $unit ne 'hours';
    $minute = "0$minute" if length($minute)<2;
    $minute =~ s/(.)./${1}0/;
    my $hour = $t->hour;
    $hour = "0$hour" if length($hour)<2;

    my $date_start =  $t->ymd." $hour:$minute:00";

    my $sql = "SELECT * FROM log_active_domains ";

    my @args;
    my $sql_where = '';
    if ($date_start) {
        push @args,($date_start);
        $sql_where .= " date_changed >=? ";
    }
    $sql_where = " WHERE $sql_where " if $sql_where;

    my $sth = $$CONNECTOR->dbh->prepare(
        "$sql $sql_where "
        ." ORDER BY date_changed");
    $sth->execute(@args);

    my ($prev_time, $prev_active);
    my $date_start2 = $date_start;

    $date_start2 =~ s/(.*) .*/$1 00:00:00/
    if ( $unit eq 'days' && $time>3) || ($unit ne 'hours' && $unit ne 'days');

    my %data = ( $date_start2 => undef);
    my $row;
    my $last_active;
    my $n = 0;
    my %bases;
    while ($row=$sth->fetchrow_hashref) {
        $bases{$row->{id_base}}++ if $row->{id_base};

        next if !$id_base && defined $row->{id_base};
        next if $id_base && !$row->{id_base};
        next if $id_base && $row->{id_base} != $id_base;

        $n++;
        $last_active = $row->{active};
        my ($curr_time) = $row->{date_changed};
        if ($unit eq 'hours' && $time<6) {
            $curr_time =~ s{(.*)\d:\d\d}{${1}0:00};
        } elsif(($unit eq 'hours' && $time < 7 *24) || ($unit eq 'days' && $time < 7) || ( $unit eq 'weeks' && $time <3 ) ) {
            $curr_time =~ s{(.*):\d\d:\d\d}{${1}:00:00};
        } else {
            $curr_time =~ s{(.*) .*}{${1} 00:00:00};
        }
        if ($prev_time) {
            if ($curr_time eq $prev_time) {
                next if $prev_active > $row->{active};
                $prev_active = $row->{active};
            } else {
                $data{$prev_time} = $prev_active;
                $prev_time = $curr_time;
                $prev_active = $row->{active};
            }
        } else {
            $prev_time = $curr_time;
            $prev_active = $row->{active};
        }
    }
    if ($prev_time) {
        $data{$prev_time} = $last_active;
    }

    my $last_time = _fill_empty(\%data, $unit, $time);

    $data{$last_time} = $last_active;

    $sth = $$CONNECTOR->dbh->prepare(
        "SELECT name FROM domains where id=?"
    );
    my @bases = ({ id => 0 , name => 'All'});
    for my $id (keys %bases) {
        $sth->execute($id);
        my ($name) = $sth->fetchrow;
        push @bases,{ id => $id , name => $name };
    }
    return {
        labels => [ sort keys %data ]
        , data => [map { $data{$_} or 0 } sort keys %data]
        , bases =>\@bases 
    };
}

sub _fill_empty($data, $unit, $time) {
    my @labels = sort keys %$data;
    my $t = DateTime::Format::DateParse->parse_datetime($labels[0]);
    my $duration = DateTime::Duration->new(minutes => 10);
    if ($unit eq 'hours' && $time<6 ) {
        $duration = DateTime::Duration->new(minutes => 10);
    } elsif (($unit eq 'hours' && $time< 7*24)
        || ( $unit eq 'days' && $time <7)
        || ( $unit eq 'weeks' && $time < 3)){
        $duration = DateTime::Duration->new(hours => 1);
    } else {
        $duration = DateTime::Duration->new(days=> 1);
    }

    my $count=0;
    for (;;) {
        $t += $duration;

        my $hour = $t->hour;
        $hour = "0$hour" if length $hour <2;

        my $min= $t->minute;
        $min = "0$min" if length $min<2;

        my $key = $t->ymd." $hour:$min:00";
        last if $key gt $labels[-1];
        next if exists $data->{$key};
        $data->{$key} = undef;
    }

    my ($day0) = $labels[0] =~ m{(.*) };
    my ($dayn) = $labels[-1] =~ m{(.*) };

    my ($year0) = $labels[0] =~ m{(\d\d\d\d)-};
    my ($yearn) = $labels[-1] =~ m{(\d\d\d\d)-};

    my $last_day;
    for my $key (sort keys %$data) {
        my ($key2) = $key =~ /(.*):\d\d/;

        $key2 =~ s/.*? (.*)/$1/ if $dayn eq $day0;
        $key2 =~ s/(.*) .*/$1/ if ( $unit eq 'hours' && $time >=7*24 ) || ($unit eq 'days' && $time > 7) || ($unit eq 'weeks' && $time > 1)
        || $unit eq 'months' || $unit eq 'years';
        $key2 =~ s/\d\d\d\d-(.*)/$1/ if $yearn eq $year0;

        $data->{$key2} = delete $data->{$key};
        $last_day = $key2;
    }
    return $last_day;

}

1;
