use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);


$Ravada::DEBUG=0;

sub test_download($vm, $id_iso, $test=0) {
    my $iso = $vm->_search_iso($id_iso);
    #    unlink($iso->{device}) or die "$! $iso->{device}"
    #    if $iso->{device} && -e $iso->{device};
    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            #            , delay => 4
            , test => $test
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');
    is($req1->error,'',$iso->{name});
    like($req1->output,qr/^http.*/);

}

sub search_id_isos {
    my $vm = shift;
    my $sth=connector->dbh->prepare(
        "SELECT * FROM iso_images"
        #        ." where name like 'Xubuntu %'"
        ." ORDER BY name,arch"
    );
    $sth->execute;
    my @id_iso;
    while ( my $row = $sth->fetchrow_hashref ) {
        next if !$row->{url};
        push @id_iso,($row->{id});
    }
    return @id_iso;
}

##################################################################

SKIP: {

init();

for my $vm_name ('KVM') {
    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if (0 && $vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        ################################################
        #
        # Request for Debian Streth ISO
        for my $id_iso (search_id_isos) {
            test_download($vm, $id_iso,1);
        }
    #test_download($vm, $id_iso,0);
}
end();
}
done_testing();
