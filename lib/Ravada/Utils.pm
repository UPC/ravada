package Ravada::Utils;

use warnings;
use strict;

=head1 NAME

Ravada::Utils - Misc util libraries for Ravada

=cut

=head2 now

Returns the current datetime

=cut

sub now {
     my @now = localtime(time);
    $now[5]+=1900;
    $now[4]++;
    for ( 0 .. 4 ) {
        $now[$_] = "0".$now[$_] if length($now[$_])<2;
    }

    return "$now[5]-$now[4]-$now[3] $now[2]:$now[1]:$now[0].0";
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

1;
