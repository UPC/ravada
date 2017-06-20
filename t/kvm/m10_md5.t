use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

my $ISO_FILE = "mock$$.iso";

sub test_isos_vm {
    my $vm = shift;

    my $sth = $test->connector->dbh->prepare(
        "SELECT * FROM iso_images"
    );
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        my $iso;
        $iso = $vm->_search_iso($row->{id});

        ok($iso,"Expecting a ISO description");

        like($iso->{url},qr{.iso}) or exit;
        like($iso->{url},qr($row->{file_re})) or exit   if $row->{file_re};
#        diag($iso->{file_re}." -> ".$iso->{url})   if $row->{file_re};
    }
    $sth->finish;
}

sub _insert_iso_there {
    my $vm_name = shift;
    my $vm=rvd_back->search_vm($vm_name);

    open my $out,'>',$vm->dir_img."/$ISO_FILE" or die $!;
    print $out "nothing\n";
    close $out;

    my @found = $vm->search_volume_path_re(qr(mock\d+.iso));
    ok(@found,"Expecting mock\\d.iso found, got ".Dumper(\@found)) 
        or return;

    like($found[0], qr($ISO_FILE$)) or return;

    my $found = $vm->search_volume_path_re(qr(mock\d+.iso));
    like($found, qr($ISO_FILE))   or return;

    @found = $vm->search_volume_path($ISO_FILE);
    ok(@found,"Expecting $ISO_FILE found, got ".Dumper(\@found)) or return;

    $found = $vm->search_volume_path($ISO_FILE);
    like($found, qr($ISO_FILE))   or return;

    my $sth = $test->dbh->prepare(
        "INSERT INTO iso_images "
        ." (name,arch,url) "
        ." VALUES(?,?,?)"
    );
    my $name = 'mock';
    $sth->execute($name,'i386',"http://localhost/$ISO_FILE");
    $sth->finish;

    $sth = $test->dbh->prepare("SELECT id FROM iso_images "
        ." WHERE name=?"
    );
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    return $id;

}

sub _remove_iso {
    my $vm_name = shift;
    my $vm=rvd_back->search_vm($vm_name);
    for my $pool ($vm->vm->list_storage_pools) {
        $pool->refresh();
        for my $vol ( $pool->list_all_volumes()) {
            $vol->delete()  if $vol->get_path =~ /mock\d+\.iso$/;
        }
    }
}

sub test_isos_already_there {
    my $vm_name = shift;
    _remove_iso($vm_name);
    my $vm=rvd_back->search_vm($vm_name);

    my $id = _insert_iso_there($vm_name) or return;

    my $list_iso = rvd_front->list_iso_images($vm_name);
    my $iso_mock;
    for (@$list_iso) {
        $iso_mock = $_ if $_->{name} eq 'mock';
    }
    ok($iso_mock,"Expecting an ISO for the 'mock' template");
    ok($iso_mock->{device},"Expecting device in ISO ".Dumper($iso_mock));

    my $iso = $vm->_search_iso($id);
    ok($iso->{device},"Expecting device in ISO ".Dumper($iso)) or return;
    _remove_iso($vm_name);
}

sub test_isos_front {
    my $vm_name = shift;
    my  $isos = rvd_front->list_iso_images($vm_name);

    my $test_device = 0;
    my $dsl;
    for my $iso (@$isos) {
        ok($iso);
#        $dsl = $iso if $iso->{name} =~ /^dsl/i;
    }
# TODO
## I was trying to test the ISO downloading functions, but it
## painful to test and bothers the providers.
## Even setting a proxy was a little tricky, it won't cache
## the big ISO files unless configured. At the end of the day
## it was not a big deal to test it the old fashioned way.
#
#    if ($ENV{http_proxy} || _try_local_proxy()) {
#        diag("Downloading ISO image, it may take some minutes");
#        unlink $dsl->{device} or die "$! unlinking $dsl->{device}"
#            if $dsl->{device};
#        my $vm = rvd_back->search_vm($vm_name);
#
#        my $iso = $vm->_search_iso($dsl->{id});
#        my $device;
#        eval { $device = $vm->_iso_name($iso) };
#        is($@,'');
#        ok($device,"Expecting a device , got ".($device or ''));
#    } else {
#        diag("Install a http proxy and set environment variable http_proxy to it to test ISO downloads.");
#    }
}

sub _try_local_proxy {
    eval { require IO::Socket::PortState;};

    if ($@) {
        return if $@ =~ /bla/;
        diag($@);
        return;
    }

    my %port = ( tcp => { 3128 => {}});
    IO::Socket::PortState::check_ports('localhost',2, \%port);

    return if !$port{tcp}->{3128}->{open};

    $ENV{http_proxy}='http://localhost:3128';
    return 1;
}

=head2 test_isos_localhost

A local apache server with the directory /iso

=cut

sub test_isos_localhost {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $ua = new LWP::UserAgent;
    my $req = HTTP::Request->new(GET => 'http://localhost/iso');
    my $res = $ua->request($req);
    SKIP: {
        skip("No local apache with isos detected",10) if !$res->is_success; 
        my $iso_list  = rvd_front->list_iso_images;
        for my $iso (@$iso_list) {
            for my $tag ( qw(md5_url sha256_url url) ) {
                next if !$iso->{$tag};
                $iso->{$tag} =~ s{(\w+://.*?)/(.*)}{http://localhost/iso/$2};

                my ($url,$file) = ($iso->{$tag});
                ($url,$file) = $iso->{$tag} =~ m{(\w+://.*)/(.*)} if $iso->{$tag} =~ /\*/;
                if ($file) {
                    my $url2 = extract_file($url,$file);
                    warn "WARNING: I can't extract $file from $url" if !$url2;
                    $iso->{$tag} = $url2 if $url2;
                }
                $iso->{$tag} =~ s{(\w+://.*?)/(.*)}{http://localhost/iso/$2}
                    if !$iso->{$tag} =~ /localhost/;
                $res = $ua->request(HTTP::Request->new(GET => $iso->{$tag}))
                    if $iso->{$tag};
                if (!$iso->{$tag}|| !$res->is_success) {
#                    diag("Missing $iso->{$tag}");
                    $iso->{failed}++;
                    next;
                }
            }
            next if $iso->{failed};
            like($iso->{device}, qr(^[a-z0-9./_-]*$)i, "Expecting filename or empty, got : '"
                                                    .($iso->{device} or '')."'")
                    or next;

            unlink $iso->{device} or die "$! $iso->{device}"    if $iso->{device};

            my $iso2 = $vm->_search_iso($iso->{id});
            for my $tag ( qw(md5_url sha256_url url) ) {
                next if !$iso2->{$tag};
                $iso2->{$tag} =~ s{(\w+://.*?)/(.*)}{http://localhost/iso/$2};
            }
            my $device;
            eval { $device = $vm->_iso_name($iso2) };
            is($@,'');
            ok($device,"Expecting a device , got ".($device or ''));
        }
    }
}

sub extract_file {
    my ($url, $file) = @_;

    my $ua = new LWP::UserAgent;
    my $res = $ua->request(HTTP::Request->new(GET => $url));
    return if !$res->is_success;

    for my $line (split /\n/,$res->content ) {
        my ($found) = $line =~ qr/<a href="($file)"/;
        return "$url/$found" if $found;
    }
    return;
}

sub test_isos_custom {
    my $vm_name = shift;

    my $id_iso = 995;
    my $sth = $test->dbh->prepare(
        "INSERT INTO iso_images "
        ." (id,device,name)"
        ." VALUES(?,?,?)"
    );
    $sth->execute($id_iso,"/var/lib/blah.iso","blah");
    $sth->finish;

    my $vm = rvd_back->search_vm($vm_name);
    my $iso = $vm->_search_iso($id_iso);
    ok($iso,"Expecting an ISO ref , got ".ref($iso));
    is($iso->{filename},"blah.iso");
}

#######################################################
#

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;


#    $Ravada::VM::KVM::WGET = "";
    test_isos_vm($vm);
    test_isos_front($vm_name);
    test_isos_already_there($vm_name);

    test_isos_localhost($vm_name);

    test_isos_custom($vm_name);
}

clean();

done_testing();

