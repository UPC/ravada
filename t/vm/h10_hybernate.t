use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $RVD_BACK = rvd_back($test->connector);
my %ARG_CREATE_DOM = (
      kvm => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");

sub test_hybernate {
    my $vm_name = shift;

    my $domain = create_domain($vm_name, $USER) or next;

    next if !$domain->can_hybernate();

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

    my $clone = $domain->clone(name => new_domain_name(), user => $USER);

    eval {$clone->start($USER)  if !$clone->is_active };
    is($clone->is_active,1) or return;

    eval { $clone->hybernate($USER) };
    ok(!$@,"Expecting no error hybernating, got : ".($@ or ''));
    is($clone->is_active,0,"$vm_name hybernate");

    eval {$clone->start($USER) };
    ok(!$@,"Expecting no error restarting, got : ".($@ or ''));
    is($clone->is_active,1);

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

for my $vm_name ( @{rvd_front->list_vm_types}) {

    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        my $domain = test_hybernate($vm_name);
        test_hybernate_clone($vm_name, $domain);
        test_hybernate_clone_swap($vm_name, $domain);

        test_remove_hybernated($vm_name,$domain);
    }
}

clean();

done_testing();

