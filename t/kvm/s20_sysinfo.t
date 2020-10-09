use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use XML::LibXML;

use feature qw(signatures);
no warnings "experimental::signatures";

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

our $XML = XML::LibXML->new();

###################################################################################3

sub test_sysinfo($domain, $domain_name=$domain->name) {

    my $doc = $XML->load_xml(string => $domain->domain->get_xml_description())
        or die "ERROR: $!\n";

    my $path_smbios = '/domain/os/smbios';
    my ($smbios) = $doc->findnodes($path_smbios);
    ok($smbios,"Expecting $path_smbios entry in XML");

    SKIP: {
        my $sys_virt_version = $Sys::Virt::VERSION;
        my $req_sys_virt_version = '4.6';
        $sys_virt_version =~ s/(\d+\.\d+).*/$1/;
        skip("Sys::Virt Version > than $req_sys_virt_version required"
                    .", found $sys_virt_version",3)
            if $sys_virt_version < $req_sys_virt_version;
        my $path_oemstrings='/domain/sysinfo/oemStrings';
        my ($oemstrings) = $doc->findnodes($path_oemstrings);
        ok($oemstrings,"Expecting $path_oemstrings entry in XML ") or return;

        my $hostname;
        for my $entry ($oemstrings->findnodes('entry')) {
            $hostname = $entry if $entry->textContent =~ /^hostname/;
        }
        ok($hostname,"Expecting a hostname entry in ".$oemstrings->toString) and do {
            my $hostname_text = $hostname->textContent();
            like($hostname_text, qr{^hostname: $domain_name$});
        };
    }
}

###################################################################################3

init();
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

    my $domain = create_domain($vm);
    test_sysinfo($domain);

    my $rename = new_domain_name;
    $domain->rename(name => $rename, user => user_admin);
    test_sysinfo($domain, $rename);

    $domain = Ravada::Domain->open($domain->id);
    test_sysinfo($domain, $rename);

    my $clone_name = new_domain_name;
    my $clone = $domain->clone(
         name => $clone_name
        ,user => user_admin
    );
    test_sysinfo($clone, $clone_name);

}

end();
done_testing();
