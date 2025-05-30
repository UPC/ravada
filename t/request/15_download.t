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

sub test_download($vm, $iso0, $test=0) {
    diag("Testing $iso0->{name}");
    my $iso;
    eval { $iso = $vm->_search_iso($iso0->{id}) };
    is($@,'',$iso0->{name});
    ok($iso) or return;
    #diag(Dumper([$iso->{url}, $iso->{file_re}]));
    my $req1 = Ravada::Request->download(
             id_iso => $iso->{id}
            , id_vm => $vm->id
            #            , delay => 4
            , test => $test
            , uid => user_admin->id
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
        push @id_iso,($row);
    }
    return @id_iso;
}

sub test_debians() {
    my $sth=connector->dbh->prepare(
        "SELECT * FROM iso_images"
        ." where name like '%Debian%'"
    );
    $sth->execute;
    my $found = 0;
    while ( my $row = $sth->fetchrow_hashref ) {
        $found++;
        like($row->{url},qr/\*|\+/);
    }
    ok($found,"Expecting some debian entries found");
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

        test_debians();
        ################################################
        #
        # Request for Debian Streth ISO
        for my $iso (search_id_isos) {
            #            next unless $iso->{name} =~ /Ubuntu.*24/i
            #            || $iso->{name} =~ /Mint.*22/i
            #            || $iso->{name} =~ /Mate.* 2/i
            #            || $iso->{name} =~ /De.*an.*12/i;
            #next unless $iso->{name} =~ /Dev.*an.*12/i;
            test_download($vm, $iso,1);
        }
}
end();
}
done_testing();
