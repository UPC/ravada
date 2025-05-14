use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $RVD_BACK = rvd_back();
my @VMS = vm_names();
my $USER = create_user("foo","bar",1);

sub test_hybernate {
    my $vm_name = shift;

    my $domain = create_domain($vm_name, $USER) or next;

    return $domain if !$domain->can_hybernate();

    $domain->start($USER)   if !$domain->is_active;

    eval { $domain->hybernate($USER) };
    ok(!$@,"Expecting no error hybernating, got : ".($@ or ''));

    is($domain->is_active,0);

    $domain->start($USER);
    is($domain->is_active,1);

    return $domain;

}

sub test_hybernate_clone {
    my ($vm_name, $domain) = @_;

    $domain->is_public(1);
    $domain->shutdown_now(user_admin) if $domain->is_active;

    my $clone = $domain->clone(name => new_domain_name(), user => $USER);

    eval {$clone->start($USER)  if !$clone->is_active };
    is($@,'');
    is($clone->is_active,1) or return;

    eval { $clone->hybernate($USER) };
    ok(!$@,"Expecting no error hybernating, got : ".($@ or ''));
    is($clone->is_active,0,"$vm_name hybernate");

    eval {$clone->start($USER) };
    ok(!$@,"Expecting no error restarting, got : ".($@ or ''));
    is($clone->is_active,1);

    $clone->shutdown_now($USER) if $clone->is_active;
    $clone->remove($USER);
}

sub test_hybernate_clone_swap {
    my ($vm_name, $domain) = @_;

    $domain->add_volume_swap( size => 1024*512);
    test_hybernate_clone($vm_name,$domain);
}

sub test_remove_hybernated {
    my ($vm_name, $domain) = @_;

    my $clone = $domain->clone(name => new_domain_name(), user => $USER);
    $clone->start($USER)   if !$clone->is_active;

    eval { $clone->hybernate($USER) };
    ok(!$@,"Expecting no error hybernating, got : ".($@ or ''));

    is($clone->is_active,0);

    eval{ $clone->remove($USER) };
    ok(!$@,"Expecting no error removing , got : ".($@ or ''));

}

################################################################

clean();

for my $vm_name ( vm_names() ) {

    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        my $domain = test_hybernate($vm_name);

        if ( $domain->can_hybernate() ) {
            test_hybernate_clone($vm_name, $domain);
            test_hybernate_clone_swap($vm_name, $domain);

            test_remove_hybernated($vm_name,$domain);
        } else {
            diag("Skipped because $vm_name domains can't hibernate");
        }
        $domain->remove(user_admin());
    }
}

end();
done_testing();
