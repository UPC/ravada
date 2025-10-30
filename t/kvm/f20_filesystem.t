use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use IPC::Run3;
use JSON::XS;
use Storable qw(dclone);
use Test::More;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $UID = 500;

########################################################################

sub test_fs_bare($vm) {
    my $domain = create_domain($vm);
    my $source = _new_source();
    my $req = Ravada::Request->add_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { source => {dir => $source }}
    );
    wait_request();

    test_fs_table($domain, undef );

    my $user = create_user();
    my $clone = _clone($domain, $user);

    my ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    my ($fs_source_clone, $fs_target_clone) = _get_fs_xml($clone);

    is($fs_source_clone, $fs_source_base);
    is($fs_target_clone, $fs_target_base);

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $hw_fs2 = $domain->info(user_admin)->{hardware}->{filesystem};
    ok($hw_fs2);
    is(scalar(@$hw_fs2),1)or die Dumper($hw_fs2);
    warn Dumper($hw_fs2);

    test_remove_fs($domain);

    my @id = ( $clone->id, $domain->id );

    $clone->remove(user_admin);
    $domain->remove(user_admin);

    my $sth = connector->dbh->prepare(
        "SELECT count(*) "
        ." FROM domain_filesystems "
        ." WHERE id_domain=?"
    );
    for my $id (@id) {
        $sth->execute($id);
        my ($count) = $sth->fetchrow;
        is($count,0);
    }
}

sub test_fs_added($vm) {
    my $domain = create_domain($vm);
    my $source = _new_source();
    my $req = Ravada::Request->add_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { source => {dir => $source }}
    );
    wait_request();

    my ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    ok($fs_source_base);

    my $sth = connector->dbh->prepare(
        "DELETE FROM domain_filesystems WHERE id_domain=?"
    );
    $sth->execute($domain->id);

    $req = Ravada::Request->refresh_machine(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();

    $sth = connector->dbh->prepare(
        "DELETE FROM domain_filesystems WHERE id_domain=?"
    );
    $sth->execute($domain->id);

    $req = Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();

    ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    ok($fs_source_base);

    $domain->shutdown_now(user_admin);

    return $domain;
}

sub test_fs_disabled_clones($base, $chroot) {

    my $hw_fs = $base->info(user_admin)->{hardware}->{filesystem};
    is($hw_fs->[0]->{enabled},1);

    my $new = dclone($hw_fs->[0]);
    unlock_hash(%$new);
    $new->{enabled}=0;
    $new->{chroot} = ( $chroot or 0);

    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'filesystem'
        ,id_domain => $base->id
        ,index => 0
        ,data => $new
    );
    wait_request(debug => 0);
    is($req2->status,'done');
    is($req2->error,'');
    wait_request(debug => 0);

    for my $domain ( $base, $base->clones()) {
        $domain = Ravada::Domain->open($domain->{id})
        if ref($domain) eq 'HASH';

        my $hw_fs2 = $domain->info(user_admin)->{hardware}->{filesystem};
        ok($hw_fs2);
        ok($hw_fs2->[0]) or die Dumper($hw_fs2);
        is($hw_fs2->[0]->{enabled},0) or die Dumper($hw_fs2->[0]);

        my ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
        is($fs_source_base,undef);
        is($fs_target_base,undef);

        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
        ) unless $domain->is_base;

    }

    wait_request();
    for my $domain ( $base->clones()) {
        my $clone = Ravada::Domain->open($domain->{id});
        my ($fs_source_base, $fs_target_base) = _get_fs_xml($clone);
        is($fs_source_base,undef);
        is($fs_target_base,undef);

        $clone->shutdown_now(user_admin);
    }

}

sub test_fs_enabled_clones($base, $chroot) {

    my $hw_fs = $base->info(user_admin)->{hardware}->{filesystem};
    is($hw_fs->[0]->{enabled},0);

    my $new = dclone($hw_fs->[0]);
    unlock_hash(%$new);
    $new->{enabled}=1;
    $new->{chroot} = ( $chroot or 0);

    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'filesystem'
        ,id_domain => $base->id
        ,index => 0
        ,data => $new
    );
    wait_request(debug => 0);
    is($req2->status,'done');
    is($req2->error,'');
    wait_request(debug => 0);

    for my $domain ( $base, $base->clones()) {
        $domain = Ravada::Domain->open($domain->{id})
        if ref($domain) eq 'HASH';
        my $hw_fs2 = $domain->info(user_admin)->{hardware}->{filesystem};
        ok($hw_fs2);
        ok($hw_fs2->[0]) or die Dumper($hw_fs2);
        is($hw_fs2->[0]->{enabled},1) or die Dumper($hw_fs2->[0]);

        my ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
        like($fs_source_base,qr/source dir=/);
        like($fs_target_base, qr/target dir=/);

        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
        ) unless $domain->is_base;
    }

    wait_request();
    for my $domain ( $base->clones()) {
        my $clone = Ravada::Domain->open($domain->{id});
        my ($fs_source_base, $fs_target_base) = _get_fs_xml($clone);
        like($fs_source_base,qr/source dir=/);
        like($fs_target_base, qr/target dir=/);

        $clone->shutdown_now(user_admin);
    }
}


sub test_fs_disabled($domain) {

    my $hw_fs = $domain->info(user_admin)->{hardware}->{filesystem};
    is($hw_fs->[0]->{enabled},1);
    my $new = dclone($hw_fs->[0]);
    unlock_hash(%$new);
    $new->{enabled}=0;

    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'filesystem'
        ,id_domain => $domain->id
        ,index => 0
        ,data => $new
    );
    wait_request();
    is($req2->status,'done');
    is($req2->error,'');

    my $hw_fs2 = $domain->info(user_admin)->{hardware}->{filesystem};
    ok($hw_fs2);
    ok($hw_fs2->[0]) or die Dumper($hw_fs2);
    is($hw_fs2->[0]->{enabled},0) or die Dumper($hw_fs2->[0]);

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    $hw_fs2 = $domain->info(user_admin)->{hardware}->{filesystem};
    ok($hw_fs2);
    is(scalar(@$hw_fs2),1)or die Dumper($hw_fs2);

    ok($hw_fs2->[0]) or die Dumper($hw_fs2);
    is($hw_fs2->[0]->{enabled},0) or die Dumper($hw_fs2->[0]);
    is($hw_fs2->[0]->{_can_edit},1) or die Dumper($hw_fs2->[0]);
    is($hw_fs2->[0]->{_can_remove},1) or die Dumper($hw_fs2->[0]);

    my ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    is($fs_source_base,undef);
    is($fs_target_base,undef);

    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();
    ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    is($fs_source_base,undef);
    is($fs_target_base,undef);

    $domain->shutdown_now(user_admin);

}

sub test_fs_enabled($domain) {

    my $hw_fs = $domain->info(user_admin)->{hardware}->{filesystem};
    is($hw_fs->[0]->{enabled},0) or die "Expecting disabled";
    my $new = dclone($hw_fs->[0]);
    unlock_hash(%$new);
    $new->{enabled}=1;

    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'filesystem'
        ,id_domain => $domain->id
        ,index => 0
        ,data => $new
    );
    wait_request();
    is($req2->status,'done');
    is($req2->error,'');

    my $hw_fs2 = $domain->info(user_admin)->{hardware}->{filesystem};
    ok($hw_fs2);
    ok($hw_fs2->[0]) or die Dumper($hw_fs2);
    is($hw_fs2->[0]->{enabled},1) or die Dumper($hw_fs2->[0]);

    my ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    ok($fs_source_base);
    ok($fs_target_base);

    Ravada::Request->start_domain(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();
    ($fs_source_base, $fs_target_base) = _get_fs_xml($domain);
    ok($fs_source_base);
    ok($fs_target_base);

    $domain->shutdown_now(user_admin);

}
sub test_remove_fs($domain) {
    my $req = Ravada::Request->remove_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,index => 0
    );
    wait_request();

    my ($fs_source, $fs_target) = _get_fs_xml($domain);
    ok(!$fs_source);
    ok(!$fs_target);

    my $fs = $domain->info(user_admin)->{hardware}->{filesystem};
    is(scalar(@$fs),0) or die Dumper($fs);

    my $sth = connector->dbh->prepare(
        "SELECT * FROM domain_filesystems "
        ." WHERE id_domain=?"
    );
    $sth->execute($domain->id);
    my $found = $sth->fetchrow_hashref;
    is(scalar(keys %$found),0) or die Dumper($found);
}

sub _get_fs_xml($domain) {
    my $xml = XML::LibXML->load_xml(string => $domain->xml_description);

    my ($fs) = $xml->findnodes("/domain/devices/filesystem");
    return(undef,undef) if !$fs;

    my ($fs_source) = $fs->findnodes("source");
    my ($fs_target) = $fs->findnodes("target");

    return (''.$fs_source, ''.$fs_target);
}

sub test_fs_change($vm) {
    my $domain = create_domain($vm);
    my $source = _new_source();
    my $req = Ravada::Request->add_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { source => { dir => $source }}
    );
    wait_request();

    my $source2 = _new_source();
    my $target2 = $source2;
    $target2 =~ s{^/}{};
    $target2 =~ tr{/}{_};
    my $hw_fs = $domain->info(user_admin)->{hardware}->{filesystem};
    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,hardware => 'filesystem'
        ,id_domain => $domain->id
        ,index => 0
        ,data => { source => { dir => $source2}
                , _id => $hw_fs->[0]->{_id}
        }
    );
    wait_request();
    is($req2->status,'done');
    is($req2->error,'');

    my $xml = XML::LibXML->load_xml(string => $domain->xml_description);
    my ($fs) = $xml->findnodes("/domain/devices/filesystem");
    ok($fs);
    my ($fs_source, $fs_target);
    if ($fs) {
        ($fs_source) = $fs->findnodes("source");
        ($fs_target) = $fs->findnodes("target");
        is($fs_source->getAttribute('dir'), $source2 );
        is($fs_target->getAttribute('dir'), $target2 );
    }
}


sub _clone($base, $user) {
    my $name = new_domain_name();
    $base->prepare_base(user_admin) if !$base->is_base();
    $base->is_public(1);

    my $req = Ravada::Request->clone(
        name => $name
        ,uid => $user->id
        ,id_domain => $base->id
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error, '');
    return rvd_back->search_domain($name);

}

sub _new_source {
    my $dir = "/var/tmp/".new_domain_name();
    mkdir $dir if !-e $dir;
    return $dir;
}

sub test_fs_table($id_domain, @data) {

    my $sth = connector->dbh->prepare(
        "SELECT * FROM domain_filesystems "
        ." WHERE id_domain=? "
    );
    $sth->execute($id_domain);
    my $n = 0;
    for my $data (@data) {
        my $row = $sth->fetchrow_hashref();
        if (!defined $data ) {
            ok(!$row) or confess Dumper([\@data,$row]);
            return;
        }
        delete $row->{id};

        my %data2 = %$data;
        $data2{id_domain} = $id_domain;
        $data2{source} = $data2{source}->{dir};

        is_deeply($row, \%data2,"Expecting same data in entry ".$n++)
            or die Dumper([$id_domain, $row, \%data2]);
    }
}

sub _fs_data {
    my $data = { chroot => 1
            ,enabled => 1
            ,subdir_uid => $UID++
            ,source => {dir => _new_source()}
    };
    lock_hash(%$data);
    return $data;
}

sub test_fs_chrooted($vm) {
    my $user = create_user();
    my $domain = create_domain($vm);
    my $data = _fs_data();

    my $req = Ravada::Request->add_hardware(
        name => 'filesystem'
        ,uid => user_admin->id
        ,id_domain => $domain->id
        ,data => $data
    );
    wait_request(debug => 0);
    is($req->error, '');
    is($req->status, 'done');
    test_fs_table($domain->id, $data);

    my $clone = _clone($domain, $user);

    my $xml = XML::LibXML->load_xml(string => $clone->xml_description);

    my ($fs) = $xml->findnodes("/domain/devices/filesystem");

    my ($fs_source) = $fs->findnodes("source");
    my ($fs_target) = $fs->findnodes("target");

    ok($fs_source) or die $fs->toString();

    my $fs_source_dir=$fs_source->getAttribute('dir');
    my $fs_target_dir=$fs_target->getAttribute('dir');

    like($fs_source_dir,qr{^/var/tmp/tst_kvm_f20_filesystem_\d+/tst_kvm_f20_filesystem_\d+$});
    like($fs_target_dir,qr/^var_tmp_tst_kvm_f20_filesystem_\d+$/);

    $clone->remove(user_admin);
    $domain->remove(user_admin);

}

sub test_fs_chrooted_n($vm, $n=2) {
    my $user = create_user();
    my $domain = create_domain($vm);
    my @data = map { _fs_data() } (1 .. $n);

    for my $data ( @data ) {
        Ravada::Request->add_hardware(
            name => 'filesystem'
            ,uid => user_admin->id
            ,id_domain => $domain->id
            ,data => $data
        );
    }
    wait_request(debug => 0);

    test_fs_table($domain->id, @data);

    my $clone = _clone($domain, $user);

    my $xml = XML::LibXML->load_xml(string => $clone->xml_description);

    my @fs = $xml->findnodes("/domain/devices/filesystem");
    is(scalar(@fs),scalar(@data)) or return;

    for my $n ( 0 .. scalar (@data)-1 ) {
        my $fs = $fs[$n];
        my $data = $data[$n];

        my ($fs_source) = $fs->findnodes("source");
        my ($fs_target) = $fs->findnodes("target");

        ok($fs_source) or die $fs->toString();

        my $fs_source_dir=$fs_source->getAttribute('dir');
        my $fs_target_dir=$fs_target->getAttribute('dir');

        my $data_source = $data->{source}->{dir};
        my $data_target = $data_source;
        $data_target =~ s{^/}{};
        $data_target =~ tr{/}{_};

        like($fs_source_dir,qr{$data_source/tst_kvm_f20_filesystem_\d+$});
        my @stat = stat($fs_source_dir);
        ok(@stat, "Expecting $fs_source_dir created") and do {
            is($stat[4], $data[$n]->{subdir_uid});
        };
        like($fs_target_dir,qr/$data_target$/);

        test_fs_table($clone,undef);
    }

    $clone->remove(user_admin);
    $domain->remove(user_admin);


}


########################################################################

init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_fs_bare($vm);

        my $domain = test_fs_added($vm);
        test_fs_disabled($domain);
        test_fs_enabled($domain);

        $domain->prepare_base(user_admin);
        $domain->clone(name => new_domain_name,user => user_admin);
        for my $chroot (0,1) {
            test_fs_disabled_clones($domain, $chroot);
            test_fs_enabled_clones($domain, $chroot);
        }

        remove_domain($domain);

        test_fs_change($vm);
        test_fs_chrooted($vm);
        test_fs_chrooted_n($vm,3);
    }
}

end();

done_testing();

