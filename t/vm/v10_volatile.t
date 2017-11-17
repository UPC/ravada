#!/usr/bin/perl
# test volatile anonymous domains kiosk mode

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
init($test->connector);

my $IP = "10.0.0.1";
my $NETWORK = $IP;
$NETWORK =~ s{(.*\.).*}{$1.0/24};

################################################################################

sub create_network {

    my $sth = $test->dbh->prepare(
        "INSERT INTO networks (name, address) "
        ." VALUES (?,?)"
    );
    $sth->execute('foo',$NETWORK);
    $sth->finish;
}

sub delete_network {
    my $sth = $test->dbh->prepare(
        "DELETE FROM networks WHERE address=?"
    );
    $sth->execute($NETWORK);
    $sth->finish;
}

sub id_network {
    my $address = shift;

    my $sth = $test->dbh->prepare(
        "SELECT id FROM networks WHERE address=?"
    );
    $sth->execute($address);
    my ($id) = $sth->fetchrow;

    return $id;
}

sub allow_anonymous {
    my $base = shift;

    my $id_network = id_network($NETWORK);
    my $sth = $test->dbh->prepare(
        "INSERT INTO domains_network "
        ." (id_domain, id_network, anonymous )"
        ." VALUES (?,?,?) "
    );
    $sth->execute($base->id, $id_network, 1);
    $sth->finish;
}

sub test_volatile {
    my ($vm_name, $base) = @_;

    my $name = new_domain_name();

    my $user_name = "user_".new_domain_name();
    my $user = Ravada::Auth::SQL::add_user(name => $user_name, is_temporary => 1);

    my $clone = $base->clone(
          user => $user
        , name => $name
    );
    is($clone->is_active,1,"[$vm_name] Expecting clone active");
    $clone->start($user)                if !$clone->is_active;

    like($clone->spice_password,qr{..+});

    is($clone->is_volatile,1,"[$vm_name] Expecting is_volatile");

    my $clone2 = rvd_back->search_domain($name);
    is($clone2->is_volatile,1,"[$vm_name] Expecting is_volatile");

    my $vm = rvd_back->search_vm($vm_name);
    my $clone3 = $vm->search_domain($name);
    is($clone3->is_volatile,1,"[$vm_name] Expecting is_volatile");

    eval { $clone->shutdown_now(user_admin)    if $clone->is_active};
    is(''.$@,'',"[$vm_name] Expecting no error after shutdown");

    my $domain2 = $vm->search_domain($name);
    ok(!$domain2,"[$vm_name] Expecting domain $name removed after shutdown") or exit;

    my $domain_f = rvd_front->search_domain($name);
    ok(!$domain_f,"[$vm_name] Expecting domain removed after shutdown");

    my $domain_b = rvd_back->search_domain($name);
    ok(!$domain_b,"[$vm_name] Expecting domain removed after shutdown");

    my $domains_f = rvd_front->list_domains();
    ok(!grep({ $_->{name} eq $name } @$domains_f),"[$vm_name] Expecting $name not listed");
}

# KVM volatiles get auto-removed
sub test_volatile_auto_kvm {
    my ($vm_name, $base) = @_;

    my $name = new_domain_name();

    my $user_name = "user_".new_domain_name();
    my $user = Ravada::Auth::SQL::add_user(name => $user_name, is_temporary => 1);

    my $clone = $base->clone(
          user => $user
        , name => $name
    );
    is($clone->is_active,1,"[$vm_name] Expecting clone active");
    $clone->start($user)                if !$clone->is_active;

    is($clone->is_volatile,1,"[$vm_name] Expecting is_volatile");
    is(''.$@,'',"[$vm_name] Expecting no error after shutdown");

    $clone->domain->destroy();

    my $vm = rvd_back->search_vm($vm_name);
    my $domain2 = $vm->search_domain($name);
    ok(!$domain2,"[$vm_name] Expecting domain $name removed after shutdown") or exit;

    my $domain_f = rvd_front->search_domain($name);
    ok(!$domain_f,"[$vm_name] Expecting domain removed after shutdown");

    my $domain_b = rvd_back->search_domain($name);
    ok(!$domain_b,"[$vm_name] Expecting domain removed after shutdown");

    my $domains_f = rvd_front->list_domains();
    ok(!grep({ $_->{name} eq $name } @$domains_f),"[$vm_name] Expecting $name not listed");
}

################################################################################

clean();


for my $vm_name ('Void', 'KVM') {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing volatile for $vm_name");

        create_network();

        my $base= create_domain($vm_name);
        $base->prepare_base(user_admin());
        $base->is_public(1);
        allow_anonymous($base);

        test_volatile($vm_name, $base);
        test_volatile_auto_kvm($vm_name, $base) if $vm_name eq'KVM';

        delete_network();
    }

}

clean();

done_testing();
