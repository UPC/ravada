use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @VMS = ('KVM','Void');

my $TEST_LONG = ($ENV{TEST_LONG} or 0);

#############################################################

clean();

for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM");

    my $vm;

    eval { $vm = rvd_back->search_vm($vm_name) };

   SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        init($vm_name);

        my $domain = create_domain($vm_name);
        my $t0 = time;
        my $clone0;

        my $n_clones = 102;
        for my $count ( 1 .. $n_clones ) {
            my $name = new_domain_name();
            my $clone;
            eval {
                $clone = $domain->clone(
                             name => $name
                            ,user => user_admin
                );
            };
            is(''.$@,'') or next;
            ok($clone,"Expecting a clone from ".$domain->name)  or next;

            if ($TEST_LONG) {
                eval { $clone->start(user_admin) };
                is(''.$@,'');
                is($clone->is_active,1);
            }

            if ($clone0 ) {
                eval { $clone0->shutdown_now(user_admin) if $clone0->is_active() };
                is(''.$@,'');
                is($clone0->is_active,0);

                if (time - $t0 > 5 ) {
                    $t0 = time;
                    diag("[$vm_name] testing clone $count of $n_clones ".$clone0->name)
                        if $ENV{TEST_VERBOSE};
                }
            }
            $clone0 = $clone;
            if ($TEST_LONG && $clone->can_hybernate) {
                eval { $clone->hybernate(user_admin) };
                is(''.$@,'');
                is($clone->is_paused,1);

                eval { $clone->start(user_admin) };
                is(''.$@,'');
                is($clone->is_active,1);
            }
        }
   }
}

end();
done_testing();
