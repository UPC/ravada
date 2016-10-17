use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Network');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $rvd_back = rvd_back( $test->connector , 't/etc/ravada.conf');
my $vm = $rvd_back->search_vm('Void');
my $USER = create_user('foo','bar');

#my $ip = Ravada::Network->new({address => '127.0.0.1/32'})->address;

my $domain_name = new_domain_name();
my $domain = $vm->create_domain( name => $domain_name
            , id_iso => 1 , id_owner => $USER->id);

my $net = Ravada::Network->new(address => '127.0.0.1/32');
ok($net->allowed($domain->id));

my $net2 = Ravada::Network->new(address => '10.0.0.0/32');
ok(!$net2->allowed($domain->id), "Address unknown should not be allowed to anything");

done_testing();
