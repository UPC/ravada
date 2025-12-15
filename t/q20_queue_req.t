use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();
clean();

####################################################################
sub test_queue_fail($vm) {
    $Ravada::VM::QUEUE_AT_TIME=1;

    my $domain = create_domain($vm);
    $domain->add_volume( format => 'qcow2', size => 1*1024*1024);
    $domain->add_volume( format => 'raw', size => 1*1024*1024);
    if ($vm->type eq 'Void') {
        $domain->add_volume( format => 'qcow2');
    }
    my $req = Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    rvd_back->_process_requests_dont_fork(1);
    is($req->error,'');
    is($req->status(),'done');

    # is not base yet
    is($domain->is_base,0) or exit;

    for my $vol ( $domain->list_volumes ) {
        if( $vol =~ /\.(img|raw|qcow2)$/ ) {
            unlink $vol or die "$! $vol";
        }
    }
    my @req = $domain->list_requests();
    wait_request(debug => 0, check_error => 0);

    # failed so no is not base now neither
    is($domain->is_base,0);
    for my $req2 (@req) {
        is($req2->status,'done');
        like($req2->error,qr'.',$req2->id." ".$req2->command." id_domain=".$req2->defined_arg('id_domain'))
            or exit;
    }

    remove_domain($domain);

    $Ravada::VM::QUEUE_AT_TIME=0;
}

sub test_queue($vm) {
    my $domain = create_domain($vm);
    $domain->add_volume( format => 'qcow2', size => 1*1024*1024);
    $domain->add_volume( format => 'raw', size => 1*1024*1024);
    if ($vm->type eq 'Void') {
        $domain->add_volume( format => 'qcow2', size => 1*1024*1024);
    }

    my $n_vols = scalar( grep {$_ =~ /img|qcow2|raw/ } $domain->list_volumes);
    my $req = Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    rvd_back->_process_requests_dont_fork();
    is($req->error,'');
    is($req->status(),'done');

    # is not base yet
    is($domain->is_base,0);

    my @req = $domain->list_requests();
    is(scalar(@req),$n_vols+1) or do {
        for my $req ( @req) {
            diag($req->id." ".$req->command);
        }
        exit;
    };

    for my $req (@req) {
        next unless ($req->command eq 'wait_job');
        my $file = $req->args('file').".sh";
        ok($vm->file_exists($file),"expecting ".$file);
    }
    wait_request(debug => 0);

    for my $req (@req) {
        if ($req->command eq 'wait_job' || $req->command eq 'post_prepare_base') {
            ok($req->after_request,$req->id." ".$req->command);
        }
        my $args = $req->args;
        if ($req->command eq 'wait_job') {
            for my $ext ( qw( out err sh ) ) {
                my $file = $args->{file}.".$ext";
                ok(!$vm->file_exists($file),"expecting removed ".$file);
            }
        }
        is($req->status,'done');
        is($req->error,'');
    }

    is (scalar($domain->list_files_base),scalar($domain->list_volumes)-1);
    for my $file ( $domain->list_files_base) {
        ok(defined $file," Expected defined file base") or next;
        ok($vm->file_exists($file),$file);
    }
    for my $vol ($domain->list_volumes_info) {
        ok($vol->backing_file,"Expecting vol with base ".$vol->file)
        unless $vol->file =~ /\.iso$/;
        ok($vm->file_exists($vol->file));
    }

    is($domain->is_base,1);

    remove_domain($domain);
}

sub test_queue_remote($vm) {
    my $node = remote_node($vm->type)  or return;
    start_node($node);
    clean_remote_node($node);
}

####################################################################

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

        diag("test $vm_name");

        # TODO
        # test_queue_remote($vm) if !$<;
        test_queue_fail($vm);
        test_queue($vm);
    }
}

end();
done_testing();
