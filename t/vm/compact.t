use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

sub test_compact($vm) {
    my $domain = create_domain($vm);
    $domain->add_volume(type => 'TMP' , format => 'qcow2', size => 1024 * 10);
    is($domain->_data('is_compacted'),1) or exit;
    $domain->start(user_admin);
    $domain->_refresh_db();
    is($domain->_data('is_compacted'),0) or exit;

    eval { $domain->compact() };
    like($@,qr/is active/);

    is($domain->_data('is_compacted'),0);

    $domain->shutdown_now(user_admin);
    is($domain->_data('is_compacted'),0);

    $domain->compact();
    is($domain->_data('is_compacted'),1);

    $domain->_data('is_compacted' => 0);
    my $req = Ravada::Request->compact(
        id_domain => $domain->id
        ,uid => user_admin->id
    );

    wait_request( check_error => 0);
    is($req->status,'done');
    like($req->error, qr'compacted'i);

    delete $domain->{_data};
    is($domain->_data('is_compacted'),1);

    for my $vol ($domain->list_volumes) {
        next if $vol =~ /iso$/;
        my ($dir, $file) = $vol =~ m{(.*)/(.*)};
        my ($out, $err) = $vm->run_command("ls",$dir);
        die $err if $err;
        my @found = grep { /^$file/ } $out =~ m{^(.*backup)}mg;
        is(scalar(@found),2) or die Dumper($vol,\@found);
    }

    $domain->start(user_admin);
    $domain->hibernate(user_admin);

    eval { $domain->compact() };
    like($@,qr/t be compacted because it is/);

    is($domain->_data('has_backups'),2);

    $domain->purge();
    is($domain->_data('has_backups'),0);
    for my $vol ($domain->list_volumes) {
        next if $vol =~ /iso$/;
        my ($dir, $file) = $vol =~ m{(.*)/(.*)};
        my ($out, $err) = $vm->run_command("ls",$dir);
        die $err if $err;
        my @found = grep { /^$file/ } $out =~ m{^(.*backup)}mg;
        is(scalar(@found),0) or die Dumper($vol,\@found);
    }

    $domain->remove(user_admin);

}

#######################################################
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP:{
        skip($msg,113);
    }
    done_testing();
    exit;
}

clean();

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

        diag("test compact on $vm_name");
        test_compact($vm);
    }
}

end();
done_testing();
