use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
init($test->connector);

$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

sub test_download {
    my ($vm, $id_iso) = @_;
    my $iso;
    eval { $iso = $vm->_search_iso($id_iso) };
    if ($@ =~ /No md5/) {
        warn "Probably this release file is obsolete.\n$@";
        return;
    }
    is($@,'');
    unlink($iso->{device}) or die "$! $iso->{device}"
        if $iso->{device} && -e $iso->{device};
    diag("Testing download $iso->{name}");
    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            , delay => 4
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');
    is($req1->error, '');

}

sub local_urls {
    my $sth = $test->dbh->prepare(
        "SELECT id,url FROM iso_images "
        ."WHERE url is NOT NULL"
    );
    my $sth_update = $test->dbh->prepare(
        "UPDATE iso_images set url=? WHERE id=?"
    );
    $sth->execute();
    while ( my ($id, $url) = $sth->fetchrow) {
        $url =~ s{\w+://(.*?)/(.*)}{http://localhost/iso/$2};
        $sth_update->execute($url, $id);
    }
    $sth->finish;
}

sub search_id_isos {
    my $vm = shift;
    my $sth=$test->dbh->prepare(
        "SELECT * FROM iso_images"# where name like 'Xubuntu%'"
    );
    $sth->execute;
    my @id_iso;
    while ( my $row = $sth->fetchrow_hashref ) {
        next if !$row->{url};
        eval {$vm->Ravada::VM::KVM::_fetch_filename($row);};
        if ($@ =~ /Can't connect to localhost/) {
            diag("Skipped tests, see http://ravada.readthedocs.io/en/latest/devel-docs/local_iso_server.html");
            return;
        }
        diag($@) if $@ && $@ !~ /No.*found/i;

        if (!$row->{filename}) {
            diag("skipped test $row->{name} $row->{url} $row->{file_re}");
            next;
        }

        push @id_iso,($row->{id});
    }
    return @id_iso;
}
##################################################################


for my $vm_name ('KVM') {
    my $rvd_back = rvd_back();
    local_urls();
    my $vm = $rvd_back->search_vm($vm_name);
    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        for my $id_iso (search_id_isos($vm)) {
            test_download($vm, $id_iso);
        }
    }
}
done_testing();
