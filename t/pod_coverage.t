use warnings;
use strict;

use Test::More;

eval {
    require Test::Pod::Coverage;
};

SKIP: {
    diag($@) if $@;
    skip(2,$@)  if $@;
    for my $type ( qw(VM Domain ) ){
        Test::Pod::Coverage::pod_coverage_ok( "Ravada::$type"
                , "Ravada::$type is covered" );
        for my $backend (keys %Ravada::VALID_VM ) {
            Test::Pod::Coverage::pod_coverage_ok( "Ravada::$type::$backend"
                , "Ravada::$type::$backend is covered" );
        }
    }
    for my $pkg ( 'Ravada' , 'Ravada::Front' , 'Ravada::Request', 'Ravada::Auth' ) {
        Test::Pod::Coverage::pod_coverage_ok( $pkg
                , "$pkg is covered" );
    }

    for my $auth ('SQL', 'LDAP' ,'User') {
        my $pkg = "Ravada::Auth::$auth";
        Test::Pod::Coverage::pod_coverage_ok( $pkg
                , "$pkg is covered" );

    }
}

done_testing();
