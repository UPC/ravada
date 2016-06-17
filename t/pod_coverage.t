use warnings;
use strict;
use Test::Pod::Coverage tests=>6;

pod_coverage_ok( "Ravada", "Ravada is covered" );
pod_coverage_ok( "Ravada::Request", "Ravada is covered" );

for my $type ( qw(VM Domain) ){
    for my $backend (qw(KVM LXC)) {
        pod_coverage_ok( "Ravada::$type::$backend", "Ravada::$type::$backend is covered" );
    }
}

