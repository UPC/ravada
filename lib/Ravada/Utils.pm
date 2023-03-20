package Ravada::Utils;

use warnings;
use strict;

use Carp qw(confess);
no warnings "experimental::signatures";
use feature qw(signatures);

no warnings "experimental::signatures";
use feature qw(signatures);

=head1 NAME

Ravada::Utils - Misc util libraries for Ravada

=cut

our $USER_DAEMON;
our $USER_DAEMON_NAME = 'daemon';

=head2 now

Returns the current datetime. Optionally you can pass seconds
to substract to the current time.

=cut

sub now($seconds=0) {
    my @now = localtime(time - $seconds);
    $now[5]+=1900;
    $now[4]++;
    for ( 0 .. 4 ) {
        $now[$_] = "0".$now[$_] if length($now[$_])<2;
    }

    return "$now[5]-$now[4]-$now[3] $now[2]:$now[1]:$now[0].0";
}

sub date_now($seconds=0) {
    my $date = now($seconds);
    $date =~ s/\.\d+$//;
    return $date;
}

=head2 random_name

Returns a random name.

Argument length

    my name = Ravada::Utils::random_name($length); # length default 8

=cut


sub random_name {
    my $length = (shift or 4);
    my $ret = '';
    my $max = ord('z') - ord('a');
    for ( 1 .. $length ) {
        my $n = int rand($max + 1);
        $ret .= chr(ord('a') + $n);
    }
    return $ret;

}

sub user_daemon {
    return $USER_DAEMON if $USER_DAEMON;

    $USER_DAEMON = Ravada::Auth::SQL->new(name => $USER_DAEMON_NAME);
    if (!$USER_DAEMON->id) {
        $USER_DAEMON = Ravada::Auth::SQL::add_user(
            name => $USER_DAEMON_NAME,
            is_admin => 1
        );
        $USER_DAEMON = Ravada::Auth::SQL->new(name => $USER_DAEMON_NAME);
    }
    $USER_DAEMON->_reload_grants();
    return $USER_DAEMON;
}

sub size_to_number {
    my $size = shift;
    confess "Undefined size" if !defined $size;

    my ($n, $unit) = $size =~ /(\d+\.?\d*)([kmg])/i;
    return $size if !defined $n || !$unit;
    $unit = lc($unit);

    my %mult = ( k => 1024 , m => 1024*1024, g => 1024*1024*1024 );
    confess "Error: unknown unit $unit" if !exists $mult{$unit};

    return $n * $mult{$unit};
}

sub number_to_size {
    my $size = shift;

    confess "Undefined size" if !defined $size;
    confess "Not a number '$size'" if $size !~ /^\d+$/ && $size !~ /^\d+\.\d+$/;

    my $div = 1024;
    my $previous_unit = '';
    my $previous_ret = $size;
    for my $unit ( 'K','M','G' ) {
        my $ret = $size / $div;
        my ($n,$d) = $ret =~ m/(\d+)\.?(\d*)/;
        return $previous_ret.$previous_unit if length($d)>3;
        return $ret.$unit if $n<1024;
        $div *= 1024;
        $previous_unit = $unit;
        $previous_ret = $ret;
    }
}

sub last_insert_id($dbh) {
    my $driver = $dbh->{Driver}->{Name};

    if ( $driver =~ /sqlite/i ) {
        return _last_insert_id_sqlite($dbh);
    } elsif ( $driver =~ /mysql|mariadb/i ) {
        return _last_insert_id_mysql($dbh);
    } else {
        confess "I don't know how to get last_insert_id for $driver";
    }
}

sub _last_insert_id_mysql($dbh) {
    my $sth = $dbh->prepare("SELECT last_insert_id()");
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return $id;

}

sub _last_insert_id_sqlite($dbh) {
    my $sth = $dbh->prepare("SELECT last_insert_rowid()");
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return $id;
}

sub max_id($dbh, $table) {
    my $sth = $dbh->prepare("SELECT max(id) FROM $table");
    $sth->execute();
    my ($max) = $sth->fetchrow;
    return ($max or 0);
}

sub check_sql_valid_params(@params) {
    for my $param (@params) {
        die "Error: invalid param '$param'" unless $param =~ /^[a-z][a-z_]+$/i;
    }
}

sub search_user_name($dbh, $id_user) {
    my $sth = $dbh->prepare("SELECT name FROM users WHERE id=? ");
    $sth->execute($id_user);
    my ($name) = $sth->fetchrow();
    return $name;
}

sub search_user_id($dbh, $user) {
    confess if !defined $user;
    return $user if $user =~ /^\d+$/;

    my $sth = $dbh->prepare("SELECT id FROM users WHERE name=? ");
    $sth->execute($user);
    my ($id) = $sth->fetchrow;
    return $id;
}

1;
