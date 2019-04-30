use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

init();

######################################################################

sub test_rebase($vm) {
    my $base = create_domain($vm);

    my $clone1 = $base->clone( name => new_domain_name, user => user_admin);
    my $clone2 = $base->clone( name => new_domain_name, user => user_admin);

    is(scalar($base->clones),2);

    my @reqs = $base->rebase(user_admin, $clone1);
    for my $req (@reqs) {
        rvd_back->_process_requests_dont_fork();
        is($req->status, 'done' ) or exit;
        is($req->error, '') or exit;
    }

    $clone1 = Ravada::Domain->open($clone1->id);
    is($clone1->id_base, undef ) or exit;
    is($clone1->is_base, 1);

    $clone2 = Ravada::Domain->open($clone2->id);
    is($clone2->id_base, $clone1->id );

    is(scalar($base->clones),0);
    is(scalar($clone1->clones),1);

    $clone2->remove(user_admin);
    $clone1->remove(user_admin);
    $base->remove(user_admin);
}

######################################################################


clean();

for my $vm_name ( vm_names() ) {
    ok($vm_name);
    SKIP: {
          my $vm = rvd_back->search_vm($vm_name);
          my $msg = "SKIPPED: No virtual managers found";
          if ($vm && $vm_name =~ /kvm/i && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
          }

          skip($msg,10)   if !$vm;
          diag("Testing volatile clones for $vm_name");

          test_rebase($vm);
    }
}

clean();

done_testing();
