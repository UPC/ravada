use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;


use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init();

#########################################################

sub test_dont_download {
    my $vm = shift;

    my ($me) = $0 =~ m{.*/(.*)};
    my $device = "/tmp/$me.iso";
    open my $out,'>',$device or die $!;
    print $out $$;
    close $out;

    my $sth = connector->dbh->prepare(
        "INSERT INTO iso_images (name,xml,xml_volume,device) "
        ." VALUES('test".$vm->type."','jessie-i386.xml','dsl-volume.xml','$device')"
    );
    $sth->execute;
    my $name = new_domain_name();
    eval {
        $vm->create_domain(
                 name => $name
                  ,vm => $vm
                ,disk => 1024 * 1024
              ,id_iso => search_id_iso('test')
            ,id_owner => user_admin->id
        );
    };
    is($@, '');

    my $domain = $vm->search_domain($name);
    ok($domain);

    $domain->remove(user_admin) if $domain;

    unlink $device;
}

#########################################################

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

        test_dont_download($vm);
    }

}

clean();

done_testing();
