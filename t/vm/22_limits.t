use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $USER;

################################################################

sub test_domain_limit_admin {
    my $vm_name = shift;

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }

    my $domain = create_domain($vm_name, user_admin );
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now(user_admin)    if $domain->is_active;

    is(rvd_back->list_domains(user => user_admin , active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start( user_admin );
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => user_admin , active => 1),1);

    my $domain2 = create_domain($vm_name, user_admin );
    $domain2->shutdown_now( user_admin )   if $domain2->is_active;
    is(rvd_back->list_domains(user => user_admin , active => 1),1);

    $domain2->start( user_admin );
    my $req = Ravada::Request->enforce_limits(timeout => 1);
    rvd_back->_process_all_requests_dont_fork();
    sleep 1;
    rvd_back->_process_all_requests_dont_fork();
    my @list = rvd_back->list_domains(user => user_admin, active => 1);
    is(scalar @list,2) or die Dumper([map { $_->name } @list]);

    $domain2->remove(user_admin);
    $domain->remove(user_admin);
}


sub test_domain_limit_noadmin {
    my $vm_name = shift;
    my $user = $USER;
    user_admin->grant($user,'create_machine');
    is($user->is_admin,0);

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $domain = create_domain($vm_name, $user);
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now($USER)    if $domain->is_active;

    is(rvd_back->list_domains(user => $user, active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start( $user);
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->shutdown_now( $user )   if $domain2->is_active;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    Ravada::Request->start_domain( uid => $user->id,
        id_domain => $domain2->id);
    wait_request();
    my $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    ok($req);
    wait_request(debug => 0);
    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1) or die Dumper([map { $_->name } @list]);
    is($list[0]->name, $domain2->name) if $list[0];

    $domain->remove(user_admin);
    $domain2->remove(user_admin);
}

sub test_domain_limit_allowed {
    my $vm_name = shift;
    my $user = $USER;
    user_admin->grant($user,'create_machine');
    user_admin->grant($user,'start_many');
    is($user->is_admin,0);

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $domain = create_domain($vm_name, $user);
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now($USER)    if $domain->is_active;

    is(rvd_back->list_domains(user => $user, active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start( $user);
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->shutdown_now( $user )   if $domain2->is_active;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    $domain2->start( $user );
    my $req = Ravada::Request->enforce_limits(timeout => 1);
    rvd_back->_process_all_requests_dont_fork();
    sleep 1;
    rvd_back->_process_all_requests_dont_fork();
    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,2) or die Dumper([ map { $_->name } @list]);

    user_admin->revoke($user,'start_many');
    is($user->can_start_many,0) or exit;

    $req = Ravada::Request->enforce_limits(timeout => 1,_force => 1);
    wait_request(debug => 0);
    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1,"[$vm_name] expecting 1 active domain")
        or die Dumper([ map { $_->name } @list]);

    $domain->remove(user_admin);
    $domain2->remove(user_admin);
}


sub test_domain_limit_already_requested {
    my $vm_name = shift;

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $user = create_user("limit$$","bar");
    user_admin->grant($user, 'create_machine');
    my $domain = create_domain($vm_name, $user);
    ok($domain,"Expecting a new domain created") or return;
    $domain->shutdown_now($user)    if $domain->is_active;

    is(rvd_back->list_domains(user => $USER, active => 1),0
        ,Dumper(rvd_back->list_domains())) or return;

    $domain->start( $user );
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->shutdown_now($USER)   if $domain2->is_active;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    $domain2->start( $user );
    my @list_requests = grep { $_->command ne 'set_time'} $domain->list_requests;
    is(scalar @list_requests,0,"Expecting 0 requests ".Dumper(\@list_requests));

    is(rvd_back->list_domains(user => $user, active => 1),2);
    my $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    wait_request(debug => 0);

    is($req->status,'done');
    is($req->error, '');

    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1) or die Dumper([ map { $_->name } @list]);
    is($list[0]->name, $domain2->name) if $list[0];

    $domain2->remove($user);
    $domain->remove($user);

    $user->remove();
}

sub test_limit_change($vm, $limit) {
    my $user = create_user(new_domain_name(),$$);

    my $base1 = create_domain($vm);
    $base1->prepare_base(user_admin);
    $base1->is_public(1);

    my $base2 = create_domain($vm);
    $base2->prepare_base(user_admin);
    $base2->is_public(1);

    my $clone1=$base1->clone(name => new_domain_name(), user => $user);
    my $clone2=$base2->clone(name => new_domain_name(), user => $user);

#    user_admin->grant($user, 'start_limit', 1);
    $clone1->start(user_admin);
    $clone2->start(user_admin);

    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,2) or die Dumper([map { $_->name } @list]);

    my $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    wait_request( debug => 0);
    is($req->status,'done');
    is($req->error,'');

    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1) or die Dumper([map { $_->name } @list]);

    my $base3 = create_domain($vm);
    $base3->prepare_base(user_admin);
    $base3->is_public(1);

    my $clone3=$base3->clone(name => new_domain_name(), user => $user);
    $clone1->start(user_admin);
    $clone2->start(user_admin);
    $clone3->start(user_admin);

    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,3) or die Dumper([map { $_->name } @list]);

    $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    wait_request( debug => 0);
    is($req->status,'done');
    is($req->error,'');

    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1) or warn Dumper([map { $_->name } @list]);

    user_admin->grant($user, 'start_limit', 2);
    is($user->can_start_limit,2) or exit;
    $clone1->start(user_admin);
    $clone2->start(user_admin);
    $clone3->start(user_admin);
    delete_request('set_time');

    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,3) or warn Dumper([map { $_->name } @list]);
    wait_request( debug => 0);

    @list = rvd_back->list_domains(user => $user, active => 1);

    $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    delete_request('set_time');
    wait_request( debug => 0);
    is($req->status,'done');
    is($req->error,'');

    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,2) or die Dumper([map { $_->name } @list]);

    remove_domain($base1, $base2, $base3);
}

################################################################

clean();
init();

for my $vm_name ( vm_names() ) {

    diag("Testing limits on $vm_name VM");

    my $vm;

    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ".($@ or '');
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        $USER = create_user("foo_${vm_name}_".new_domain_name(),"bar");

        test_limit_change($vm, 1);
        test_limit_change($vm, 2);

        test_domain_limit_admin($vm_name);
        test_domain_limit_noadmin($vm_name);
        test_domain_limit_allowed($vm_name);

        test_domain_limit_already_requested($vm_name);

    };

}


end();
done_testing();
