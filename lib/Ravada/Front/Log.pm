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

sub list_active_recent($hours=1) {

    confess "Error: incorrect hours" if $hours !~ /^\d+$/;

    _init_connector();
    my $t = DateTime->now()- DateTime::Duration->new( hours => $hours);;
    my $minute = $t->minute;
    $minute = "00" if $hours>3;
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
    $date_start2 =~ s/(.*) .*/$1 00:00:00/ if $hours>=7*24;
    my %data = ( $date_start2 => undef);
    my $row;
    my $last_active;
    my $n = 0;
    while ($row=$sth->fetchrow_hashref) {
        $n++;
        $last_active = $row->{active};
        my ($curr_time) = $row->{date_changed};
        if ($hours<6) {
            $curr_time =~ s{(.*)\d:\d\d}{${1}0:00};
        } elsif($hours < 7 *24) {
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

    my $last_time = _fill_empty(\%data, $hours);

    $data{$last_time} = $last_active;

    return {
        labels => [ sort keys %data ]
        , data => [map { $data{$_} } sort keys %data]
    };
}

sub _fill_empty($data, $hours) {
    my @labels = sort keys %$data;
    my $t = DateTime::Format::DateParse->parse_datetime($labels[0]);
    my $duration = DateTime::Duration->new(minutes => 10);
    if ($hours <6 ) {
        $duration = DateTime::Duration->new(minutes => 10);
    } elsif ($hours < 7*24) {
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
        $key2 =~ s/(.*) .*/$1/ if $hours>=7*24;
        $key2 =~ s/\d\d\d\d-(.*)/$1/ if $yearn eq $year0;

        $data->{$key2} = delete $data->{$key};
        $last_day = $key2;
    }
    return $last_day;

}

1;
