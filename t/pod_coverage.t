use warnings;
use strict;

use Test::More;

eval {
    require Test::Pod::Coverage;
};

SKIP: {
    diag($@) if $@;
    skip(2,$@)  if $@;
pod_coverage_ok( "Ravada", "Ravada is covered" );
pod_coverage_ok( "Ravada::Request", "Ravada is covered" );
}

done_testing();
