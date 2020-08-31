use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Copy;
use IPC::Run3;
use Test::More;
use Mojo::UserAgent;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

if (! $ENV{TEST_DOWNLOAD}) {
    diag("Skipped: enable setting environment variable TEST_DOWNLOAD");
    done_testing();
    exit;
}

init();

$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

sub _backup_iso($iso, $clean) {
    my $backup_iso;
    if ($iso->{device} && -e $iso->{device} ) {
        $backup_iso = "$iso->{device}.old";
        copy($iso->{device},$backup_iso) or die "$! $iso->{device} -> $backup_iso";

        unlink $iso->{device} or die "$! $iso->{device}"
        if $clean;
    }
    if ($clean) {
        my $sth = connector->dbh->prepare(
            "UPDATE iso_images set device=NULL WHERE id=?"
        );
        $sth->execute($iso->{id});
    }
    return $backup_iso;
}

sub _restore_iso($iso, $backup_iso) {
    confess "Error: undefined backup_iso" if !defined $backup_iso;
    confess "Error: missing backup iso '$backup_iso'" if ! -e $backup_iso;

    copy($backup_iso, $iso->{device}) or die "$! $backup_iso -> $iso->{device}";
}

sub test_download {
    my ($vm, $id_iso, $clean) = @_;
    my $iso;
    eval { $iso = $vm->_search_iso($id_iso) };
    if ($@ =~ /No md5/) {
        warn "Probably this release file is obsolete.\n$@";
        return;
    }
    is($@,'') or return;

    my $backup_iso = _backup_iso($iso,$clean);# if ($clean && $iso->{device});

    confess "Missing name in ".Dumper($iso) if !$iso->{name};
    diag("Testing download $iso->{name}");
    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            , delay => 4
            , verbose => 0
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');
    is($req1->error, '') or do {
        _restore_iso($iso, $backup_iso) if $backup_iso;
        exit;
    };

    my $iso2;
    eval { $iso2 = $vm->_search_iso($id_iso) };
    is($@,'');
    ok($iso2, "Expecting a iso for id = $id_iso , got ".($iso2 or '<UNDEF>'));
    
    my $device;
    eval { $device = $vm->_iso_name($iso2, undef, 0) };
    is($@,'');

    ok($device,"Expecting a device name , got ".($device or '<UNDEF>'));

    is($iso2->{rename_file}, $iso2->{filename}) if $iso2->{rename_file};

    like($iso2->{device},qr'.',"Expecting something in device field ");

    return $iso2;
}

sub test_download_fail {
    my ($vm,$id_iso) = @_;
    my $iso;
    eval { $iso = $vm->_search_iso($id_iso) };
    is($@,'') or return;
    ok($iso->{url},"Expecting url ".Dumper($iso)) or return;
    unlink($iso->{device}) or die "$! $iso->{device}"
        if $iso->{device} && -e $iso->{device};
    $iso->{url} =~ s{(.*)\.(.*)}{$1-failforced.$2};

    my $device;
    eval { $device = $vm->_iso_name($iso, undef, 0) };
    like($@,qr/./);
    ok(!$device);
    ok(!-e $device, "Expecting $device missing") if $device;
}

sub local_urls {
    rvd_back->_set_url_isos('http://localhost/iso/');
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

sub httpd_localhost {
    my $ua  = Mojo::UserAgent->new;
    my $res;
    eval {  
       $res = $ua->get('http://localhost/iso/')->res;
    };
    diag(($res->code or '')." ".($res->message or '')." ".($@ or ''));
    return 1 if $res && $res->code && $res->code == 200;
    return if !$@;
    is($@,qr/Connection refused/);
    return 0;
}

sub add_locales {

    my @lang;
    opendir my $ls,"etc/repository/iso" or die $!;
    while (my $dir = readdir $ls) {
        push @lang,($dir) if $dir =~ /^\w+/;
    }
    closedir $ls;
    Ravada::Request->post_login( user => user_admin->id, locale => \@lang);
    rvd_back->_process_requests_dont_fork();
}

sub test_refresh_isos {
    my ($vm,$iso) = @_;
    # Now we remove the ISO file and try to refresh
    unlink $iso->{device};
    my $sth = connector->dbh->prepare(
        "UPDATE iso_images set device=NULL WHERE id=?"
    );
    $sth->execute($iso->{id});

    $vm->_refresh_isos();

    my $iso2 = $vm->_search_iso($iso->{id});
    like($iso2->{device},qr{.*/$iso->{rename_file}}) or exit;
}

##################################################################


for my $vm_name ('KVM') {
    my $rvd_back = rvd_back();
    add_locales();
    local_urls();
    my $vm = $rvd_back->search_vm($vm_name);
    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }
        if (!httpd_localhost()) {
            $vm = undef;
            $msg = "SKIPPED: No http on localhost with /iso";
        }
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        test_download_fail($vm, 1);

        for my $id_iso (search_id_isos($vm)) {
            test_download($vm, $id_iso, 1); #clean
            my $sth = connector->dbh
                ->prepare("UPDATE iso_images set md5=NULL, sha256=NULL WHERE id=?");
            $sth->execute($id_iso);
            $sth->finish;

            my $iso = test_download($vm, $id_iso);

            test_refresh_isos($vm, $iso) if $iso->{rename_file};
        }
    }
}
end();
done_testing();
