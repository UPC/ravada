use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
init($test->connector);

######################################################################3

sub test_volatile_clone {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    ok($domain);

    is($domain->volatile_clones, 0);

    $domain->volatile_clones(1);
    is($domain->volatile_clones, 1);
    my $clone_name = new_domain_name();

    my $clone = $domain->clone(
        name => $clone_name
        ,user => user_admin
    );

    is($clone->is_active, 1);
    is($clone->is_volatile, 1);

    $clone->start(user_admin)   if !$clone->is_active;

    is($clone->is_active, 1) && do {

#        like($clone->display(user_admin),qr'\w+://');

        my $clonef = Ravada::Front::Domain->open($clone->id);
        ok($clonef);
        isa_ok($clonef, 'Ravada::Front::Domain');
        is($clonef->is_active, 1);

        $clonef = rvd_front->search_domain($clone_name);
        ok($clonef);
        isa_ok($clonef, 'Ravada::Front::Domain');
        is($clonef->is_active, 1,"[".$vm->type."] expecting active $clone_name") or exit;
        like($clonef->display(user_admin),qr'\w+://');

        my $list = rvd_front->list_domains();

        $clone->shutdown_now(user_admin);

        eval { $clone->is_active };
        is(''.$@,'');

        is($clone->is_removed, 1);

        my $clone2 = $vm->search_domain($clone_name);
        ok(!$clone2, "[".$vm->type."] volatile clone should be removed on shutdown");

        my $sth = $test->dbh->prepare("SELECT * FROM domains where name=?");
        $sth->execute($clone_name);
        my $row = $sth->fetchrow_hashref;
        is($row,undef);

    };

    $clone->remove(user_admin)  if !$clone->is_removed;
    $domain->remove(user_admin);
}

sub test_enforce_limits {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    ok($domain);

    $domain->volatile_clones(1);
    $domain->prepare_base(user_admin);
    $domain->is_public(1);

    my $user = create_user("limit$$",'bar');

    my $clone_name = new_domain_name();
    my $clone = $domain->clone(
        name => $clone_name
        ,user => $user
    );

    is($clone->is_active, 1);
    is($clone->is_volatile, 1);

    sleep 1;
    my $clone2 = $domain->clone(
        name => new_domain_name
        ,user => $user
    );
    is($clone2->is_active, 1);
    is($clone2->is_volatile, 1);

    eval { rvd_back->_enforce_limits_active( timeout => 1) };
    is(''.$@,'');
    for ( 1 .. 10 ){
        last if !$clone->is_active;
        sleep 1;
    }

    is($clone->is_active,0,"[".$vm->type."] expecting clone ".$clone->name." inactive")
        or exit;
    is($clone2->is_active,1 );

    my $clone0_2 = $vm->search_domain($clone_name);
    is($clone0_2, undef);
    $clone0_2 = rvd_back->search_domain($clone_name);
    is($clone0_2, undef);

    my $clone0_f;
    eval { $clone0_f = rvd_front->search_domain($clone_name) };
    is($clone0_f, undef);

    my $list_domains = rvd_front->list_domains();
    ($clone0_f) = grep { $_->{name} eq $clone_name } @$list_domains;
    is($clone0_f, undef);

    eval { $clone2->remove(user_admin) };
    is(''.$@,'');

    eval { $clone->remove(user_admin) if !$clone->is_removed() };
    is(''.$@,'');
    $domain->remove(user_admin);

    $user->remove();
}

sub test_internal_shutdown {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    $domain->is_volatile(1);
    $domain->start(user_admin);
    my $domain_name = $domain->name;

    shutdown_domain_internal($domain);

    rvd_back->_cmd_refresh_vms();
}

######################################################################3
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

        test_volatile_clone($vm);
        test_enforce_limits($vm);
        test_internal_shutdown($vm);
    }
}

clean();

done_testing();
