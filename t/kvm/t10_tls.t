use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

my $FILE_CONFIG_QEMU = "/etc/libvirt/qemu.conf";

#################################################################

sub _check_libvirt_tls {
    my %search = map { $_ => 0 }
    ('spice_tls = 1',
    'spice_tls_x509_cert_dir = '
    );
    open my $in,'<',$FILE_CONFIG_QEMU or die "$! $FILE_CONFIG_QEMU";
    while(my $line = <$in>) {
        chomp $line;
        $line =~ s/#.*//;
        next if !length($line);
        for my $pattern (keys %search) {
            delete $search{$pattern} if $line =~ /^$pattern/
        }
        last if !keys %search;
    }
    return if !keys %search;
    return "Missing in $FILE_CONFIG_QEMU: ".join(" , ",keys %search)
        ."\n".'https://ravada.readthedocs.io/en/latest/docs/spice_tls.html';
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
    ok(grep(/^ca=-+BEGIN/, @lines),"Expecting ca on ".Dumper(\@lines));
    ok(grep(/^tls-port=.+/, @lines),"Expecting tls-port on ".Dumper(\@lines));
    ok(grep(/^tls-ciphers=.+/, @lines),"Expecting tls-ciphers on ".Dumper(\@lines));
    ok(grep(/^host-subject=.+/, @lines),"Expecting host-subject on ".Dumper(\@lines));

=pod

    open my $out,'>',"/var/tmp/".$domain->name.".xml" or die $!;
    print $out join("\n", @lines)."\n";
    close $out;
    exit;

=cut

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $file_f = $domain_f->display_file_tls(user_admin);
    is($file_f, $display_file);

    $domain->remove(user_admin);
}

#################################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);


SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }
    if ($vm) {
        $msg = _check_libvirt_tls();
        $vm = undef if $msg;
    }

    diag($msg)      if !$vm;
    skip($msg,10)   if !$vm;

    test_tls($vm_name);
}

end();
done_testing();
