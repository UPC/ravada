use strict;
use warnings;

use Test::More;

use Data::Dumper;
use YAML qw(LoadFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

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

    my $vm = Ravada::VM->open( type => 'KVM');

    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            #            , delay => 4
            , test => 1
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');
    is($req1->error,'');
    like($req1->output,qr/^http.*/);
}

sub check_entries_added($vm, $dir) {

    my $sth = connector->dbh->prepare("SELECT id FROM iso_images "
        ." WHERE name=?");

    opendir my $ls,$dir or die "$! $dir";
    while (my $yml = readdir $ls) {
        next if $yml !~ /\.yml$/;

        my $path = "$dir/$yml";
        my $data = LoadFile($path);

        my $name = $data->{name};
        $sth->execute($name);

        my ($id_iso) = $sth->fetchrow;
        ok($id_iso,"Expecting $name in iso_images");

        test_download_iso($vm, $id_iso) if $id_iso;

    }
}

sub test_download_iso($vm, $id_iso) {
    my $iso = $vm->_search_iso($id_iso);
    #    unlink($iso->{device}) or die "$! $iso->{device}"
    #    if $iso->{device} && -e $iso->{device};
    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            #            , delay => 4
            , test => 1
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');
    is($req1->error,'',$iso->{name});
    like($req1->output,qr/^http.*/);

}
sub test_post_login() {
    my $sth = connector->dbh->prepare("DELETE FROM iso_images WHERE name like 'Linkat %'");
    $sth->execute();

    my $vm = Ravada::VM->open( type => 'KVM');


    opendir my $dir, "etc/repository/iso" or die $!;
    while (my $lang = readdir $dir) {
        next if $lang =~ /^\./;
        my $req = Ravada::Request->post_login(
            user =>user_admin->name
            ,locale => $lang
        );
        wait_request( debug => 0);
        check_entries_added($vm, "etc/repository/iso/$lang");
    }
}

####################################################################

test_insert_locale();
test_insert_request();

SKIP: {
    skip("SKIPPED: Test must run as root",8) if $<;
    test_post_login();

    test_download('linkat');

};

end();
done_testing();

