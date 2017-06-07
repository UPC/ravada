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
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

#######################################################
sub test_spice {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , id_iso => 1 , id_owner => $USER->id);

    $domain->start($USER);

    my $display_file = $domain->display_file($USER);

    my $display = $domain->display($USER);
    my ($ip_d,$port_d) = $display =~ m{spice://(.*):(.*)};
    my ($ip_f) = $display_file =~ m{host=(.*)}mx;
    my ($port_f) = $display_file =~ m{port=(.*)}mx;
    is($ip_d, $ip_f);
    is($port_d, $port_f);
}


#######################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);


SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    test_spice($vm_name);
}

clean();
done_testing();
