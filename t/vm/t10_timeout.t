use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

my $RVD_BACK = rvd_back();
my $USER;

$USER = create_user('foo','bar');

######################################################

sub test_run_timeout {
    my $vm_name = shift;
    my $domain = create_domain($vm_name, user_admin)
        or return;

    my $timeout = 5;

    $domain->run_timeout($timeout);


    is($domain->run_timeout(),$timeout);
    $domain->prepare_base(user_admin);

    $domain->is_public(1);
    ok($domain->is_public());
    ok($domain->is_base());

    my $domain_f = rvd_front->search_domain($domain->name);
    is($domain_f->run_timeout(),$timeout);
    is($domain_f->is_public(),1);

    my $clone = $domain->clone(user => $USER, name => new_domain_name());

    is($clone->run_timeout(),$timeout);

    $clone->start(user => $USER);
    my @requests = $clone->list_requests(1);
    my ($req) = grep { $_->command eq 'shutdown' } @requests;
    ok($req, "Expecting shutdown requested ".Dumper($req,[map { [$_->command, $_->at_time] } @requests])) and do {
        is($req->args('id_domain'), $clone->id);
        my $at = $req->at_time();
        ok($at > time(),"Expecting at in the future ".($at - time));
    };

    $clone->remove(user_admin);
    $domain->remove(user_admin);
}

sub test_run_timeout_propagate {
    my $vm_name = shift;

    my $domain = create_domain($vm_name, user_admin) or return;

    my $timeout = 5;

    $domain->run_timeout($timeout);
    $domain->prepare_base(user_admin);

    $domain->is_public(1);

    my $clone = $domain->clone(user => $USER, name => new_domain_name());

    is($clone->run_timeout(),$timeout);

    my $timeout2 = 7;
    $domain->run_timeout($timeout2);

    my $clone2 = rvd_front->search_domain($clone->name);
    is($clone2->run_timeout(),$timeout2);

    $clone->remove(user_admin);
    $domain->remove(user_admin);
}

######################################################
clean();

for my $vm_name ( vm_names() ) {

    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing timeout for $vm_name");

        test_run_timeout($vm_name);
        test_run_timeout_propagate($vm_name);
    }
}

end();
done_testing();
