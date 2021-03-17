use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

#################################################################

sub _check_libvirt_tls {
    return check_libvirt_tls();
}

sub test_tls {
    my $vm_name = shift;
    my $domain = create_domain($vm_name);

    my $vm = $domain->_vm;
    like($vm->tls_host_subject,qr'.') or return;

    $domain->start(user_admin);

    my $display;
    eval {
        $display = $domain->display(user_admin);
    };
    is($@,'') or return;

    my $display_file = $domain->display_file_tls(user_admin);
    my @lines = split /\n/,$display_file;
    my %field;
    for (@lines) {
        my ($key, $value) = split /=/;
        next if !$key || !$value;
        $field{$key} = $value;
    }
    for my $key ( 'ca', 'tls-port','tls-ciphers','host-subject') {
        ok($field{$key},"Expecting $key ") or die Dumper(\%field);
    }

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $file_f = $domain_f->display_file_tls(user_admin);
    is($file_f, $display_file);

    $domain->remove(user_admin);
}

#################################################################

clean();

my $vm_name = 'KVM';
my $vm;
$vm = rvd_back->search_vm($vm_name) if !$>;


SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }
    if ($vm) {
        if (! _check_libvirt_tls() ) {
            $msg = "No TLS found";
            $vm = undef;
        }
    }

    diag($msg)      if !$vm;
    skip($msg,10)   if !$vm;

    test_tls($vm_name);
}

end();
done_testing();
