use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3 qw(run3);
use POSIX qw(WNOHANG);
use Test::More;
use YAML qw(Load LoadFile DumpFile Dump);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my $MOD_NBD= 0;
my $DEV_NBD = "/dev/nbd10";
my $MNT_RVD= "/mnt/test_rvd";
my $QEMU_NBD = `which qemu-nbd`;
chomp $QEMU_NBD;

my $VOL_SIZE = 1024 * 256;

ok($QEMU_NBD,"Expecting qemu-nbd command") or do {
    done_testing;
    exit;
};

init();

######################################################################
sub test_rebase_3times($vm, $swap, $data, $with_cd) {

    my $base1 = create_domain($vm);
    $base1->add_volume(type => 'swap', size=>$VOL_SIZE) if $swap;
    $base1->add_volume(type => 'data', size=>$VOL_SIZE) if $data;

    mangle_volume($vm, "base1",$base1->list_volumes);
    $base1->prepare_base(user => user_admin, with_cd => $with_cd);

    my $base2 = $base1->clone( name => new_domain_name, user => user_admin);
    mangle_volume($vm, "base2",$base2->list_volumes);

    my $clone = $base1->clone( name => new_domain_name, user => user_admin);
    for my $file ( $clone->list_volumes ) {
        test_volume_contents($vm, "base1", $file);
    }
    $base2->spinoff();
    $base2->prepare_base(user => user_admin, with_cd => $with_cd);

    $clone->rebase(user_admin, $base2);
    is($clone->id_base, $base2->id);
    for my $file ( $clone->list_volumes() ) {
        my ($type) =$file =~ /\.([A-Z]+)\./;
        test_volume_contents($vm,"base1",$file);
        if ($type && $type eq 'DATA') {
            test_volume_contents($vm,"base2",$file,0);
        } else {
            test_volume_contents($vm,"base2",$file);
        }
    }

    mangle_volume($vm, "clone", $clone->list_volumes);
    $clone->rebase(user_admin, $base1);
    is($clone->id_base, $base1->id);
    for my $file ( $clone->list_volumes() ) {
        my ($type) =$file =~ /\.([A-Z]+)\./;
        test_volume_contents($vm,"base1",$file);
        test_volume_contents($vm,"base2",$file,0);
        if ($type && $type eq 'DATA') {
            test_volume_contents($vm,"clone",$file,1);
        } else {
            test_volume_contents($vm,"clone",$file,0);
        }
    }

    my $base3 = $base2->clone(name => new_domain_name, user => user_admin);
    mangle_volume($vm, "base3", $base3->list_volumes);
    $base3->prepare_base(user => user_admin, with_cd => $with_cd);

    $clone->rebase(user_admin, $base3);
    is($clone->id_base, $base3->id);
    for my $file ( $clone->list_volumes() ) {
        my ($type) =$file =~ /\.([A-Z]+)\./;
        test_volume_contents($vm,"base1",$file);
        if ($type && $type eq 'DATA') {
            test_volume_contents($vm,"base2",$file,0);
            test_volume_contents($vm,"base3",$file,0);
            test_volume_contents($vm,"clone",$file,1);
        } else {
            test_volume_contents($vm,"base2",$file,1);
            test_volume_contents($vm,"base3",$file,1);
            test_volume_contents($vm,"clone",$file,0);
        }
    }

    unload_nbd();
    $clone->remove(user_admin);
    $base1->remove(user_admin);
    $base3->remove(user_admin);
    $base2->remove(user_admin);
}

sub test_rebase_with_vols($vm, $swap0, $data0, $with_cd0, $swap1, $data1, $with_cd1) {
    #diag("\nsw da cd");
    #diag("$swap0, $data0, $with_cd0\n$swap1, $data1, $with_cd1");

    my $same_outline = 0;
    $same_outline = ( $swap0 == $swap1 ) && ($data0 == $data1) && ($with_cd0 == $with_cd1);

    my $base = create_domain($vm);
    $base->add_volume(type => 'swap', size=>$VOL_SIZE)    if $swap0;
    $base->add_volume(type => 'data', size=>$VOL_SIZE)    if $data0;
    $base->prepare_base(user => user_admin, with_cd => $with_cd0);

    my $clone1 = $base->clone( name => new_domain_name, user => user_admin);

    my @volumes_before = $clone1->list_volumes();
    mangle_volume($vm,"clone",@volumes_before);

    my %backing_file = map { $_->file => ($_->backing_file or undef) }
        grep { $_->file } $clone1->list_volumes_info;

    my $base2 = create_domain($vm);
    $base2->add_volume(type => 'swap', size=>$VOL_SIZE)    if $swap1;
    $base2->add_volume(type => 'data', size=>$VOL_SIZE)    if $data1;
    $base2->prepare_base(user => user_admin, with_cd => $with_cd1);

    my @reqs;
    eval { @reqs = $clone1->rebase(user_admin, $base2) };
    if (!$same_outline) {
        like($@,qr/outline different/i) or exit;
        _remove_domains($base, $base2);
        return;
    } else {
        is($@, '') or exit;
    }
    my @volumes_after = $clone1->list_volumes();
    ok(scalar @volumes_after >= scalar @volumes_before,Dumper(\@volumes_after,\@volumes_before))
        or exit;

    test_match_vols(\@volumes_before, \@volumes_after);

    for my $vol ($clone1->list_volumes_info) {
        my $file = $vol->file or next;
        my ($type) =$file =~ /\.([A-Z]+)\./;
        if ($type && $type eq 'DATA') {
            test_volume_contents($vm,"clone",$file);
        } else {
            test_volume_contents($vm,"clone",$file,0);
        }

        my $bf2 = $base2->name;
        if ( $file !~ /\.iso$/ ) {
            like ($vol->backing_file, qr($bf2), $vol->file) or exit;
            isnt($vol->backing_file, $backing_file{$vol->file}) if $backing_file{$file};
        } else {
            is($vol->backing_file, $backing_file{$vol->file}) if $backing_file{$file};
        }
        # we may check inside eventually but it is costly
    }
    _remove_domains($base, $base2);
}

sub _remove_domains(@bases) {
    unload_nbd();
    for my $base (@bases) {
        for my $clone ($base->clones) {
            my $d_clone = Ravada::Domain->open($clone->{id});
            $d_clone->remove(user_admin);
        }
        $base->remove(user_admin);
    }
}

sub _key_for($a) {
    my($key) = $a =~ /\.([A-Z]+)\.\w+$/;
    $key = 'SYS' if !defined $key;
    return $key;
}
sub test_match_vols($vols_before, $vols_after) {
    return if scalar(@$vols_before) != scalar (@$vols_after);
    my %vols_before = map { _key_for($_) => $_ } @$vols_before;
    my %vols_after  = map { _key_for($_) => $_ } @$vols_after;

    for my $key (keys %vols_before, keys %vols_after) {
        is($vols_before{$key}, $vols_after{$key}, $key) or die Dumper($vols_before, $vols_after);
    }
}

sub test_rebase($vm, $swap, $data, $with_cd) {
    #diag("sw: $swap , da: $data , cd: $with_cd");
    my $base = create_domain($vm);

    $base->add_volume(type => 'swap', size=>$VOL_SIZE)    if $swap;
    $base->add_volume(type => 'data', size=>$VOL_SIZE)    if $data;
    $base->prepare_base(user => user_admin, with_cd => $with_cd);

    my $clone1 = $base->clone( name => new_domain_name, user => user_admin);
    my $clone2 = $base->clone( name => new_domain_name, user => user_admin);

    wait_request();
    is(scalar($base->clones),2);

    $clone1->prepare_base(user => user_admin, with_cd => $with_cd) if $with_cd;
    is($clone1->id_base, $base->id) or exit;

    my @reqs = $base->rebase(user_admin, $clone1);
    for my $req (@reqs) {
        rvd_back->_process_requests_dont_fork();
        is($req->status, 'done' ) or exit;
        is($req->error, '', $req->command." ".$clone2->name) or exit;
    }

    $clone1 = Ravada::Domain->open($clone1->id);
    is($clone1->id_base, $base->id) or exit;
    is($clone1->is_base, 1);

    $clone2 = Ravada::Domain->open($clone2->id);
    is($clone2->id_base, $clone1->id );

    is(scalar($base->clones),1);
    is(scalar($clone1->clones),1);

    unload_nbd();
    $clone2->remove(user_admin);
    $clone1->remove(user_admin);
    $base->remove(user_admin);
}

sub test_prepare_remove($vm) {
    my $domain = create_domain($vm);
    $domain->add_volume(type => 'swap', size=>$VOL_SIZE);
    $domain->add_volume(type => 'data', size=>$VOL_SIZE);

    mangle_volume($vm, "zipizape", grep { !/\.iso$/ }  $domain->list_volumes);

    $domain->prepare_base(user_admin);
    $domain->remove_base(user_admin);

    for my $file ( $domain->list_volumes ) {
        next if $file =~ /\.iso$/;
        test_volume_contents($vm, "zipizape", $file);
    }
    unload_nbd();
    $domain->remove(user_admin);

}

sub test_rebase_clone($vm) {
    my $base0 = create_domain($vm);
    $base0->add_volume( format => 'qcow2' );

    Ravada::Request->prepare_base(
        id_domain => $base0->id
        ,uid => Ravada::Utils->user_daemon->id
    );
    wait_request();

    my $base1 = $base0->clone(name => new_domain_name()
        ,user => user_admin
    );
    my $clone = $base0->clone(name => new_domain_name()
        ,user => user_admin
    );
    Ravada::Request->prepare_base(
        id_domain => $base1->id
        ,uid => Ravada::Utils->user_daemon->id
    );
    wait_request();

    Ravada::Request->rebase(
        uid => user_admin->id
        ,id_domain => $clone->id
        ,id_base => $base1->id
    );
    wait_request(debug => 0);

    my $req = Ravada::Request->spinoff(
        uid => user_admin->id
        ,id_domain => $base1->id
    );

    wait_request( check_error => 0 );
    like($req->error,qr/has .* clones/);

    my $re2 = Ravada::Request->remove_base(
        uid => user_admin->id
        ,id_domain => $base0->id
    );
    wait_request(check_error => 0);

    like($req->error,qr/has .* clones/);

    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $clone->id
    );
    wait_request();

    remove_domain($base0);
}

######################################################################

clean();
$ENV{LANG}='C';

for my $vm_name (vm_names() ) {
    ok($vm_name);
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing rebase for $vm_name");

        test_rebase_clone($vm);

        test_prepare_remove($vm);

        if (!$ENV{TEST_LONG} ) {
            test_rebase_3times($vm, 1, 1, 1);
            test_rebase_with_vols($vm,0,0,0,0,0,0);
            test_rebase_with_vols($vm,1,1,1,0,0,1);
            test_rebase_with_vols($vm,1,1,1,1,1,1);
        }
        for my $swap0 ( 0 , 1 ) {
            for my $data0 ( 0 , 1 ) {
                for my $with_cd0 ( 0 , 1 ) {
                    test_rebase($vm, $swap0, $data0, $with_cd0);
                    if ($ENV{TEST_LONG}) {
                        test_rebase_3times($vm, $swap0, $data0, $with_cd0);
                    }
                    for my $swap1 ( 0 , 1 ) {
                        for my $with_cd1 ( 0 , 1 ) {
                            for my $data1 ( 0 , 1 ) {
                                if ($ENV{TEST_LONG}) {
                                test_rebase_with_vols($vm, $swap0, $data0, $with_cd0
                                    , $swap1, $data1, $with_cd1);
                                }

                            }
                        }
                    }
                }
            }
        }
    }
}

end();
done_testing();
