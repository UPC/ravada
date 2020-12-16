use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

init();
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

#######################################################
sub test_spice {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $domain_name = new_domain_name();
    my $domain = $vm->create_domain( name => $domain_name
                , disk => 1024 * 1024
                , id_iso => search_id_iso('Alpine') , id_owner => $USER->id);

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

if ($>)  {
    diag("SKIPPED: Test must run as root");
    done_testing();
    exit;
}

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

end();
done_testing();
