use warnings;
use strict;

use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::VM');

init();

ok(rvd_back);
isa_ok(rvd_back,'Ravada');

my @names = vm_names();
ok(scalar @names,"Expecting some vm names");
for my $vm_name (sort @names) {
    my $vm;
    eval {
        $vm = Ravada::VM->_open_type(type => $vm_name)
    };
    is($@,'');
}


end();
done_testing();
