use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

###################################################################

sub test_extra_isos($vm) {
    my $isos = rvd_front->list_iso_images();
    for my $iso (@$isos) {
        next if !$iso->{extra_iso};
        my @url = $vm->_search_url_file($iso->{extra_iso});
        ok(scalar(@url));
        my $name = new_domain_name();
        my $req = Ravada::Request->create_domain(
            name => $name
            ,id_owner => user_admin->id
            ,vm => $vm->type
            ,id_iso => $iso->{id}
            ,iso_file => "/var/tmp/a.iso"
        );
        wait_request();
        my $domain = rvd_back->search_domain($name);
        ok($domain) or next;
        my $disks = $domain->info(user_admin)->{hardware}->{disk};
        my @cds = grep { $_->{file} =~ /\.iso$/ } @$disks;
        is(scalar(@cds),2);
        remove_domain($domain);
    }
}

###################################################################

init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_extra_isos($vm);
    }
}

end();

done_testing();

