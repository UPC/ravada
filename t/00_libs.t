use strict;
use warnings;

use Test::More;

use_ok('Ravada::Auth');
use_ok('Ravada::Auth::LDAP');
use_ok('Ravada::Auth::SQL');
use_ok('Ravada::Auth::Group');
use_ok('Ravada::VM');
use_ok('Ravada::Domain');
use_ok('Ravada::Front::Domain');

use_ok('Ravada::Repository::ISO');

my @vms = 'Void';


eval {
    require Sys::Virt;
    push @vms,('KVM');
};
diag($@)    if $@;

for my $vm_name (@vms) {
    use_ok("Ravada::VM::$vm_name");
    use_ok("Ravada::Domain::$vm_name");
}

open my $find,'-|',"find lib -type f -iname '*.pm'" or die $!;
while (<$find>) {
    chomp;
    next if /LXC/;
    s{^lib/}{};
    s{\.pm$}{};
    s{/}{::}g;
    require_ok($_);
}

done_testing();

1;
