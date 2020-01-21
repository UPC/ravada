use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(DumpFile);

use feature qw(signatures);
no warnings "experimental::signatures";

use lib 't/lib';
use Test::Ravada;

init();

####################################################################

sub test_domain_with_data($vm) {

    my $domain = create_domain($vm);
    $domain->add_volume(type => 'data');
    my $vol_swap1 = $domain->add_volume(type => 'swap');
    like ($vol_swap1 , qr{\.SWAP\.}) or exit;

    my $vol_swap2 = $domain->add_volume(swap => 1);
    like ($vol_swap2 , qr{\.SWAP\.}) or exit;

    my ($sys) = grep { !/.SWAP./ && !/.DATA./ } $domain->list_volumes();
    ok($sys);

    my ($swap1, $swap2) = grep { /.SWAP./ } $domain->list_volumes();
    ok($swap1);
    ok($swap2);
    isnt($swap1,$swap2);

    my ($data) = grep { /.DATA./ } $domain->list_volumes();
    ok($data);

    $domain->remove(user_admin);
}

sub _restore($domain) {
    $domain->restore(user_admin);
}

sub _restore_req($domain) {
    my $req = Ravada::Request->restore_domain(id_domain => $domain->id
        ,uid => user_admin->id
    );
    wait_request();
    is($req->status , 'done');
    is($req->error, '');
}

sub test_restore($vm , $restore) {
    my $domain = create_domain($vm);
    $domain->add_volume(type => 'data');
    $domain->add_volume(type => 'swap');

    my $clone = $domain->clone(name => new_domain_name, user => user_admin);
    my @files_base = $domain->list_files_base;

    my @volumes = $clone->list_volumes();
    my ($vol_data) = grep { /.DATA./ } @volumes;
    ok($vol_data,Dumper(\@volumes)) or exit;

    my %orig_md5sum;
    for my $vol ( @volumes ) {
        ($orig_md5sum{$vol}) = $vm->run_command("/usr/bin/md5sum",$vol);
    }

    my %new_md5sum;
    for my $vol ( @volumes ) {
        DumpFile($vol,{ a => $$ , capacity => $$ });

        ($new_md5sum{$vol}) = $vm->run_command("/usr/bin/md5sum",$vol);
        isnt($new_md5sum{$vol_data}, $orig_md5sum{$vol_data});
    }

    $restore->($clone);
    is_deeply([$clone->list_volumes], [@volumes]);

    for my $vol ( @volumes ) {
        my ($md5) = $vm->run_command("/usr/bin/md5sum",$vol);

        if ($vol =~ /\.DATA\./) {
            # keep changes on data volumes
            is($md5, $new_md5sum{$vol_data});
        } else {
            # restore changes on other volumes
            isnt($md5, $new_md5sum{$vol_data});
        }
    }

    $clone->remove(user_admin);
    $domain->remove(user_admin);

}

sub test_create_with_data($vm) {
    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_owner => user_admin->id
        ,swap => 0.1 * 1024 * 1024
        ,data => 0.1 * 1024 * 1024
        ,id_iso => search_id_iso('Alpine')
        ,vm => $vm->type
    );
    ok($req);
    wait_request();
    is($req->status, 'done' );
    is($req->error, '');

    my $domain = rvd_back->search_domain($name);
    ok($domain) or return;

    $domain->remove(user_admin);
}

#################################################################################3

clean();
for my $vm_name (vm_names()) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing $vm_name data volumes");
        test_domain_with_data($vm);
        test_restore($vm,\&_restore);
        test_restore($vm,\&_restore_req);

        test_create_with_data($vm);
    }
}

clean();

done_testing();

