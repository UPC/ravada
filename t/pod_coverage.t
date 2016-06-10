use warnings;
use strict;
use Test::Pod::Coverage tests=>4;

pod_coverage_ok( "Ravada", "Ravada is covered" );
pod_coverage_ok( "Ravada::Request", "Ravada is covered" );
pod_coverage_ok( "Ravada::VM::KVM", "Ravada::VM::KVM is covered" );
pod_coverage_ok( "Ravada::Domain::KVM", "Ravada::Domain::KVM is covered" );
