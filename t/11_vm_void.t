use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::VM');

init('t/etc/ravada_vm_void.conf');

ok(rvd_back);

ok(rvd_back->search_vm('Void'));

my $vm = rvd_back->vm();
ok(scalar @$vm,"Expecting some VMs, got none");
ok(grep({$_->type eq 'Void' } @{$vm}),
        "Expecting a VM type Void, got ".Dumper($vm));

my $vm_front = rvd_front->list_vm_types();
ok(scalar @$vm_front,"Expecting some VMs in front, got none");
ok(grep({$_ eq 'Void' } @{$vm_front}),
        "Expecting a VM type Void in front, got ".Dumper($vm_front));

end();
done_testing();
