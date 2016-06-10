use warnings;
use strict;
use Test::Pod::Coverage tests=>3;

pod_coverage_ok( "Ravada", "Ravada is covered" );
pod_coverage_ok( "Ravada::Request", "Ravada is covered" );
pod_coverage_ok( "Ravada::VM::KVM", "Ravada is covered" );
