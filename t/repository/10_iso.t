use strict;
use warnings;

use Test::More;

use Data::Dumper;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada::Repository::ISO');

init();

##################################################################

sub test_insert_locale {
    my $sth = connector->dbh->prepare("DELETE FROM iso_images WHERE name like 'Linkat %'");
    $sth->execute();

    my $row = $sth->fetchrow_hashref();
    is($row->{name}, undef);

    Ravada::Repository::ISO::insert_iso_locale('ca',1);

    $sth = connector->dbh->prepare("SELECT * FROM iso_images WHERE name like 'Linkat %'");
    $sth->execute();

    $row = $sth->fetchrow_hashref();
    like($row->{name},qr(Linkat),Dumper($row));

}

sub test_insert_request {
    my $sth = connector->dbh->prepare("DELETE FROM iso_images WHERE name like 'Linkat %'");
    $sth->execute();

    my $row = $sth->fetchrow_hashref();
    is($row->{name}, undef);

    my $req = Ravada::Request->post_login( user => user_admin->name, locale => ['en','ca'] );

    rvd_back->_process_all_requests_dont_fork();

    is($req->status, 'done');
    is($req->error, '');
    $sth = connector->dbh->prepare("SELECT * FROM iso_images WHERE name like 'Linkat %'");
    $sth->execute();

    $row = $sth->fetchrow_hashref();
    like($row->{name},qr(Linkat));

 }

sub test_download($iso_name) {
    my $id_iso = search_id_iso($iso_name);
    ok($id_iso) or return;

    my $vm = rvd_back->search_vm('KVM');

    my $iso = $vm->_search_iso($id_iso);
    if ($iso->{device} && -e $iso->{device}) {
        warn("$iso->{device} already downloaded");
    }
    my $device_cdrom = $vm->_iso_name($iso, undef, 1);
    ok($device_cdrom);

    my $md5 = $vm->_fetch_md5($iso);
    ok($md5);

}

####################################################################

test_insert_locale();
test_insert_request();

SKIP: {
    skip("SKIPPED: Test must run as root",8) if $<;
    test_download('linkat');
};

end();
done_testing();

