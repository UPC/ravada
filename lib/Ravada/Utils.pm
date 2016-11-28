package Ravada::Utils;

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

1;
