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
    is($req1->error,'',$iso->{name}) or exit;
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

sub test_fail_download($vm) {
    my $id_iso = search_id_iso('Alpine');
    my $sth = connector->dbh->prepare(
        "SELECT url,file_re FROM iso_images WHERE id=?"
    );
    $sth->execute($id_iso);
    my ($url, $file_re) = $sth->fetchrow;

    $sth = connector->dbh->prepare(
        "UPDATE iso_images SET url=?,file_re=? WHERE id=?"
    );
    $sth->execute('http://localhost/fail/','alpine.iso', $id_iso);

    my $req = Ravada::Request->create_domain(
        id_owner => user_admin->id()
        ,id_vm => $vm->id
        ,id_iso => $id_iso
        ,name => new_domain_name()
        ,disk => 1024 * 1024
    );
    wait_request( debug => 1, check_error => 0);
    diag($req->error);

    $sth->execute($url,$file_re, $id_iso);

    like($req->error,qr/No.* found on http.*/);
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
        diag($vm_name);

        test_fail_download($vm);

        test_debians();
        ################################################
        #
        # Request for Debian Streth ISO
        for my $iso (search_id_isos) {
            #            next unless $iso->{name} =~ /Ubuntu.*24/i
            #            || $iso->{name} =~ /Mint.*22/i
            #            || $iso->{name} =~ /Mate.* 2/i
            #            || $iso->{name} =~ /De.*an.*12/i;
            next unless $iso->{name} =~ /^Ubuntu 20.04/;
            diag($iso->{name});
            test_download($vm, $iso,1);
        }
}
end();
}
done_testing();
