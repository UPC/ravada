use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use DateTime;
use DateTime::Duration;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada::Front::Log');

########################################################################

sub test_log_inactive($vm) {
    my $dom = create_domain($vm);
    my $req = Ravada::Request->refresh_vms();
    wait_request($req);

    my $sth = connector->dbh->prepare("SELECT * FROM log_active_domains");
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        is($row->{active},0);
    }

    return $dom;
}

sub test_log_active($vm, $dom) {
    $dom->start(user_admin);
    sleep 1;
    my $req = Ravada::Request->refresh_vms();
    wait_request($req);

    my $sth = connector->dbh->prepare("SELECT * FROM log_active_domains"
    ." ORDER BY date_changed DESC");
    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    is($row->{active},1) or die Dumper($row);

}

sub _now() {
    for ( 1 .. 60 ) {
        my @now = localtime(time);
        last if $now[3] % 10 > 0;
        sleep 1;
    }
    my $date = DateTime->now()-DateTime::Duration->new(hours => 1);
    my $min = $date->minute % 10;
    $date -= DateTime::Duration->new(minutes => $min-1);
    return $date;
}

sub _yesterday() {
    my $date = DateTime->now()-DateTime::Duration->new(hours => 23);
    return $date;
}

sub test_today() {
    my $log = Ravada::Front::Log::list_active_recent();
}

sub test_add_missing($vm) {
    my $sth = connector->dbh->prepare("DELETE FROM log_active_domains");
    $sth->execute;

    $sth = connector->dbh->prepare("INSERT INTO log_active_domains "
        ."(active,date_changed)"
        ." VALUES (?,?) "
    );
    my $now = _now();
    for my $n ( 1,2,5 ) {
        $sth->execute(
            $n*3
            ,$now->ymd." ".$now->hms
        );
        $now += DateTime::Duration->new(minutes => 10);
    }
    $now = DateTime->now()-DateTime::Duration->new(seconds => 5);
    $sth->execute(2,$now->ymd." ".$now->hms);

    my $log = Ravada::Front::Log::list_active_recent(1);
    my $data = $log->{data};
    my $labels = $log->{labels};
    is(scalar(@$data),7) or die Dumper($log);
    is(scalar(@$labels),7) or exit;
    is($data->[0],3);
    is($data->[1],6);
    is($data->[2],15);
    is($data->[3],undef);
    is($data->[4],undef);
    is($data->[6],2);

    # last one just changed
    $now = DateTime->now()-DateTime::Duration->new(seconds => 3);
    $sth->execute(1,$now->ymd." ".$now->hms);

    my $log2 = Ravada::Front::Log::list_active_recent();
    is(scalar(@{$log2->{data}}),7) or die Dumper($log,$log2);
    is($log2->{data}->[6],1) or die Dumper($log->{data},$log2->{data});
}

sub test_1day() {
    my $sth = connector->dbh->prepare("INSERT INTO log_active_domains "
        ."(active,date_changed)"
        ." VALUES (?,?) "
    );
    my $d = _yesterday();
    my $now = DateTime->now();
    for my $h ( 0 .. 23 ) {
        for my $m ( 1,2,5 ) {
            $sth->execute(
                $h+$m
                ,$d->ymd." ".$d->hms
            );
            $d += DateTime::Duration->new(minutes => 10);
            last if $d >= $now;
        }
        $d += DateTime::Duration->new(hours => 1);
        last if $d >= $now;
    }

    my $log = Ravada::Front::Log::list_active_recent(24);
    is(scalar (@{$log->{labels}}),25);
    is(scalar (@{$log->{data}}),25);
    for (@{$log->{labels}}) {
        like($_,qr/\:00$/);
    }

}

sub test_1week() {
    my $sth = connector->dbh->prepare("INSERT INTO log_active_domains "
        ."(active,date_changed)"
        ." VALUES (?,?) "
    );
    my $d= DateTime->now()-DateTime::Duration->new(days => 7);
    my $now = DateTime->now();
    for my $h ( 0 .. 23 ) {
        for my $m ( 1,2,5 ) {
            $sth->execute(
                $h+$m
                ,$d->ymd." ".$d->hms
            );
            $d += DateTime::Duration->new(minutes => 10);
            last if $d >= $now;
        }
        $d += DateTime::Duration->new(hours => 1);
        last if $d >= $now;
    }

    my $log = Ravada::Front::Log::list_active_recent(24*7);
    is(scalar (@{$log->{labels}}),8 );
    is(scalar (@{$log->{data}}), 8);

    $log->{labels}->[0] = '2022-'.$log->{labels}->[0]
    if $log->{labels}->[0] !~ /^\d{4}/;

    for (@{$log->{labels}}) {
        like($_,qr/(\d{4}-)?\d+-\d+$/);
    }

}



########################################################################

init();
clean();

for my $vm_name ( 'Void' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $dom = test_log_inactive($vm);
        test_log_active($vm, $dom);

        test_add_missing($vm);
        test_1day();
        test_1week();
    }
}

end();

done_testing();
