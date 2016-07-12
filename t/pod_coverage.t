use warnings;
use strict;

use Test::More;

eval {
    require Test::Pod::Coverage;
};

SKIP: {
    diag($@) if $@;
    skip(2,$@)  if $@;
    for my $type ( qw(VM Domain) ){
        for my $backend (qw(KVM LXC)) {
            Test::Pod::Coverage::pod_coverage_ok( "Ravada::$type::$backend"
                , "Ravada::$type::$backend is covered" );
        }
    }
}

done_testing();
