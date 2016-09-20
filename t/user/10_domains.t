use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::VM::Void');
use_ok('Ravada::Auth::SQL');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $ravada = rvd_back($test->connector , 't/etc/ravada.conf');

my $name = 'foo';
Ravada::Auth::SQL::add_user($name, 'bar',);

my $user = Ravada::Auth::SQL->new(name => $name, password => 'bar');
ok(! $user->is_admin,"User $name should not be admin");

my $vm = Ravada::VM::Void->new();
ok($vm,"I can't create void VM");

my $domain_name = new_domain_name();
my $domain = $vm->create_domain(name => $domain_name, id_owner => $user->id);

ok($domain,"No domain $domain_name created");

ok($domain->name eq $domain_name, "Expecting domain name $domain_name , got "
        .($domain->name or '<UNDEF>'));
ok($domain->id_owner
    && $domain->id_owner eq $user->id,"Expecting owner=".$user->id." , got ".$domain->id_owner);

done_testing();

