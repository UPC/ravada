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

    test_auto_compact($domain);

    $domain->remove(user_admin);

}

sub test_auto_compact($domain) {
    rvd_back->setting("/backend/auto_compact",1);
    is(rvd_back->setting("/backend/auto_compact"),1);
    like(rvd_back->setting("/backend/auto_compact/time"),qr/:00/);
    $domain->start(user_admin);
    $domain->shutdown_now(user_admin);
    my @requests = $domain->list_requests(1);
    my @compact = grep {$_->command eq 'compact' } @requests;
    # it still must be enabled in the machine
    is(scalar @compact,0);

    $domain->_data('auto_compact' => 1);
    $domain->start(user_admin);
    $domain->shutdown_now(user_admin);
    @requests = $domain->list_requests(1);
    @compact = grep {$_->command eq 'compact' } @requests;
    is(scalar @compact,1);

    rvd_back->setting("/backend/auto_compact",0);
}

sub test_settings() {
    my $settings = rvd_front->settings_global();
    for my $item (keys %$settings) {
        next if $item eq 'id';
        ok(ref($settings->{$item}),$item) or exit;
        ok(exists $settings->{$item}->{id}
            || exists $settings->{$item}->{_id}
            ,Dumper([$item,$settings->{$item}]))
                or exit;
    }
    ok(rvd_front->settings_global()->{backend}->{time_zone}->{value})
        or exit;

    $settings->{backend}->{auto_compact}->{time}->{value}="22:00";


    my $reload = 0;
    rvd_front->update_settings_global($settings, user_admin,\$reload);

    my $settings2 = rvd_front->_get_settings();
    is($settings2->{backend}->{auto_compact}->{time}->{value},"22:00");
}

sub test_compact_clone($vm) {

    my $base1 = create_domain($vm);
    $base1->prepare_base(user_admin);

    my $base2=$base1->clone(name => new_domain_name,user=>user_admin);
    $base2->prepare_base(user_admin);

    my $clone =$base2->clone(name => new_domain_name,user=>user_admin);

    is($clone->auto_compact,undef);

    $base1->auto_compact(1);

    is($base2->auto_compact(),1);
    is($clone->auto_compact(),1);

    $base2->auto_compact(0);
    is($clone->auto_compact(),0) or exit;

    $clone->auto_compact(1);
    is($clone->auto_compact(),1) or exit;

}

#######################################################

clean();

test_settings();
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    diag($msg);
    SKIP:{
        skip($msg,113);
    }
    done_testing();
    exit;
}

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
        test_compact_clone($vm);
        test_compact($vm);
    }
}

end();
done_testing();
