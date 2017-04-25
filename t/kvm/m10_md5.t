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
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

sub test_isos_vm {
    my $vm = shift;

    diag("testing isos");
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


    test_isos_vm($vm);
    test_isos_front($vm_name);

}

clean();

done_testing();

