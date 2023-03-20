use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper qw(Dumper);
use Mojo::JSON qw(encode_json decode_json);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

########################################################################

sub test_create($vm, $with_iso_file=1, $no_cd=0) {
    my $iso = _load_iso($vm, 'Debian%');
    $iso = _load_iso($vm, 'Empty Machine 32 bits') if $no_cd;

    my $name = new_domain_name();
    my @args = (
        id_owner => user_admin->id
        ,name => $name
        ,vm => $vm->type
        ,id_iso => $iso->{id}
    );
    push @args,(iso_file => "") if $with_iso_file;

    my $req = Ravada::Request->create_domain(@args);

    unless ($no_cd) {
        my $req_download = $req->_search_request('download');
        ok($req_download,"Expecting a download request") or die;
        $req_download->arg(test => 1);
    }

    wait_request(debug => 0);
    my $domain = rvd_front->search_domain($name);
    ok($domain);
    my $disks= $domain->info(user_admin)->{hardware}->{disk};
    my ($cdrom) = grep { $_->{file} =~ m{/.*iso$} } @$disks;
    if ($no_cd) {
        ok(!$cdrom,"Expecting no CDROM in ".Dumper($disks));
    } else {
        ok($cdrom,"Expecting a CDROM in ".Dumper($disks));
    }
}

sub _load_iso($vm, $name) {
#    my $name = 'debian%';
    my $sth = connector->dbh->prepare("SELECT * FROM iso_images "
    ." WHERE name like ?"
    );
    $sth->execute($name);
    my $iso = $sth->fetchrow_hashref;
    die "No $name found in iso_images ".Dumper($iso) if !$iso->{id};

    _remove_device($vm, $iso);
    return $iso;
}

sub _remove_device($vm, $iso ) {
    my $device = $iso->{device};
    return if !$device;
    #    unlink $device or die "$! $device" if $device;
    $iso->{device} =undef;

    my $sth = connector->dbh->prepare("UPDATE iso_images "
        ." SET device=NULL "
        ." WHERE id=?"
    );
    $sth->execute($iso->{id});
    $sth->finish;

}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {

   SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name eq 'KVM' && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing create from ISO in $vm_name");

        test_create($vm,1);
        test_create($vm);

        test_create($vm,0,1);
    }
}

end();

done_testing();

