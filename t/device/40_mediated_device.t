use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use Ravada::HostDevice::Templates;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

####################################################################

sub _prepare_dir_mdev() {

    my $dir = "/run/user/".new_domain_name();

    mkdir $dir or die "$! $dir"
    if ! -e $dir;

    my $uuid="3913694f-ca45-a946-efbf-94124e5c09";

    for (1 .. 2 ) {
        open my $out, ">","$dir/$uuid$_$_ " or die $!;
        print $out;
        close $out;
    }
    return $dir;
}

sub test_mdev($vm) {

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($mdev) = grep { $_->{name} eq "GPU Mediated Device" } @$templates;
    ok($mdev,"Expecting PCI template in ".$vm->name) or return;

    my $dir = _prepare_dir_mdev();

    my $id = $vm->add_host_device(template => $mdev->{name});
    my $hd = Ravada::HostDevice->search_by_id($id);

    $hd->_data('list_command' => "ls $dir");

    my $domain = create_domain_v2(
        vm => $vm
        ,options => { machine => 'q35' }
        ,iso_name => '%bull%64%'
    );
    $domain->add_host_device($id);

    my $xml = $domain->xml_description();
    my @spice = grep /spice/,split/\n/,$xml;
    warn Dumper(\@spice);
}

####################################################################

clean();

for my $vm_name ( 'KVM' ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        test_mdev($vm);

    }
}

end();
done_testing();

