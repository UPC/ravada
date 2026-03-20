use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use feature qw(signatures);
no warnings "experimental::signatures";

use_ok('Ravada');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init();

#########################################################

sub test_windows($vm) {
    my $isos = rvd_front->list_iso_images();
    my $dev = "/var/tmp/a.iso";
    for my $iso (@$isos) {
        next unless $iso->{name} =~ /windows/i || !$iso->{url};
        is($iso->{has_cd},1) unless $iso->{name} =~ /^Empty/;
        is($iso->{url}, undef);
        my $name = new_domain_name();
        my @args =(
            id_owner => user_admin->id
            ,name => $name
            ,id_iso => $iso->{id}
            ,vm => $vm->type
            ,disk => 10*1024
            ,swap => 10*1024
            ,data => 10*1024
            ,options => { 'uefi' => 1 , machine => 'pc-q35-4.2' }
        );
        my $req = Ravada::Request->create_domain(@args);
        ok($req->status,'done');
        like($req->error,qr/ISO.*required/) unless $iso->{name} =~ /Empty/;
        wait_request(debug => 0);

        $name = new_domain_name();
        push @args, ( iso_file => $dev) if $iso->{has_cd};

        my $req2 = Ravada::Request->create_domain(@args,name => $name );
        ok($req2->status,'requested');
        wait_request( debug => 0);
        ok($req2->status,'done');
        is($req2->error, '');
        my $domain = rvd_back->search_domain($name);
        ok($domain, "Expected domain $name created") or exit;

        test_cd_removed($domain);

        test_extra_iso($domain) if $iso->{extra_iso};

    }
}

sub test_extra_iso($domain) {
    my $disks = $domain->info(user_admin)->{hardware}->{disk};
    my @cds = grep { defined $_->{file} && $_->{file} =~ /\.iso$/i } @$disks;
    is(scalar(@cds),2);

}

sub test_cd_removed($domain) {
    my $req = Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();
    my $name = new_domain_name();
    Ravada::Request->clone(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,name => $name
    );
    wait_request();
    my $clone = rvd_back->search_domain($name);
    my $disks = $clone->info(user_admin)->{hardware}->{disk};
    my @cds = grep { defined $_->{file} && $_->{file} =~ /\.iso$/i } @$disks;
    is(scalar(@cds),0);
}

#########################################################

clean();


for my $vm_name ( vm_names() ) {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        test_windows($vm);
    }

}

end();
done_testing();
