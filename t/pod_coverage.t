use strict;

use Test::More;

eval {
    require Test::Pod::Coverage;
};

SKIP: {
    diag($@) if $@;
    skip(2,$@)  if $@;
    # TODO: doc for Ravada::Domain::* qw(VM Domain)
    for my $type ( qw(VM) ){
        Test::Pod::Coverage::pod_coverage_ok( "Ravada::$type"
                , { also_private => [ qr/^[A-Z]+$/ ]}
                , "Ravada::$type is covered" );
        for my $backend (keys %Ravada::VALID_VM ) {
            my $module = "Ravada::".$type."::$backend";
            Test::Pod::Coverage::pod_coverage_ok(
                $module
                , { also_private => [ qr/^[A-Z]+$/ ]}
                , "$module is covered" );
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
