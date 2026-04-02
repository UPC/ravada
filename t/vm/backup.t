use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Copy qw(copy);
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

########################################################################

sub _change_domain($domain) {
    for my $vol ( $domain->list_volumes ) {
        open my $out,">>",$vol or die "$! $vol";
        print $out "a" x 20;
        close $out;
    }
}

sub _vols_md5($domain) {
    my @md5;
    for my $vol (sort $domain->list_volumes ) {
        my $ctx = Digest::MD5->new();

        open my $in,'<',$vol or confess "$! $vol";
        $ctx->addfile($in);

        my $digest = $ctx->hexdigest;
        push @md5,({$vol => $digest});
    }
    return @md5;
}

sub _remove_iso($domain) {

    my @vols = $domain->list_volumes();

    for my $n ( 0 .. scalar(@vols)-1) {
        next if $vols[$n] !~ /\.iso$/;
        Ravada::Request->remove_hardware(
             uid => user_admin->id
            ,name => 'disk'
            ,index => $n
            ,id_domain => $domain->id
        );
    }
    wait_request(debug => 0);
}

sub backup_different_id_vm($vm) {
    my $user = create_user();
    user_admin->make_admin($user->id);
    my $domain = create_domain_v2(vm => $vm, swap => 1, data => 1
        ,user => $user
    );
    _remove_iso($domain);

    $domain->backup();
    my ($backup) = $domain->list_backups();

    $domain->remove(user_admin);

    my $vm_type = $vm->type;
    my $id_vm_old = $vm->id;
    $vm->remove();

    my $vm2 = rvd_back->search_vm($vm_type);

    my $file = $backup->{file};

    rvd_back->restore_backup($file,0);

    my $sth = connector->dbh->prepare("UPDATE domains set id_vm=? "
        ." WHERE id_vm=?"
    );
    $sth->execute($vm2->id, $id_vm_old);
}

sub backup_auto_start($vm) {
    my $domain = create_domain_v2(vm => $vm, swap => 1, data => 1
    );
    _remove_iso($domain);

    my $req = Ravada::Request->domain_autostart(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request();

    is($domain->autostart,1);

    $domain->backup();
    my ($backup) = $domain->list_backups();

    my $name = $domain->name;
    my $id = $domain->id;
    $domain->remove(user_admin);

    rvd_back->restore_backup($backup->{file},0);

    my $domain_f = Ravada::Front::Domain->open($id);
    is($domain_f->_data('autostart'),1);

    my $domain2 = rvd_back->search_domain($name);
    ok($domain2);
    is($domain2->autostart,1);
    is($domain2->_data('autostart'),1);
    if ($vm->type eq 'KVM') {
        is($domain2->domain->get_autostart(),1);
    }
    is($domain2->_internal_autostart(),1);

    $domain2->remove(user_admin);

}

sub backup($vm,$remove_user=undef) {
    my $user = create_user();
    user_admin->make_admin($user->id);
    my $domain = create_domain_v2(vm => $vm, swap => 1, data => 1
        ,user => $user
    );
    _remove_iso($domain);

    is($domain->list_backups(),0);

    my @md5 = _vols_md5($domain);

    $domain->backup();
    is($domain->list_backups(),1);

    _change_domain($domain);

    my $id_owner = $domain->_data('id_owner');
    if ($remove_user) {
        $user->remove();
    } else {
        $domain->_data(id_owner => 999);
    }

    my ($backup) = $domain->list_backups();
    $domain->restore_backup($backup);

    my @md5_restored = _vols_md5($domain);
    is_deeply(\@md5_restored, \@md5) or exit;

    is($domain->_data('id_owner'),$id_owner);

    my $domain2 = $vm->search_domain($domain->name);
    is($domain2->id, $domain->id);

    my $new_owner = Ravada::Auth::SQL->search_by_id($domain->_data('id_owner'));
    ok($new_owner);

    is($domain->list_backups(),1);

    $domain->remove_backup($backup, 0);
    ok(-e $backup->{file},"$backup->{file} should not have been removed");

    $domain->remove_backup($backup, 1);
    ok(!-e $backup->{file},"$backup->{file} should have been removed");
    is($domain->list_backups(),0);

    $domain->backup();
    ($backup) = $domain->list_backups();

    $domain->remove(user_admin);
    ok(-e $backup->{file},"$backup->{file} should not have been removed");

    unlink($backup->{file}) or die "$! $backup->{file}";
}

sub restore_from_file($vm, $remove=undef) {
    my $domain = create_domain_v2(vm => $vm, swap => 1, data => 1);
    _remove_iso($domain);

    is($domain->list_backups(),0);

    my @vols = sort $domain->list_volumes();
    my @md5 = _vols_md5($domain);

    $domain->backup();

    my ($backup) = $domain->list_backups();

    my $file = $backup->{file};
    my $file2 = $file.".copy.tgz";
    copy($file,$file2);
    ok(-e $file2);

    my $name = $domain->name;

    $domain->remove(user_admin) if $remove;

    rvd_back->restore_backup($file2,0);

    for my $vol (@md5) {
        my ($file) = keys %$vol;
        ok(-e $file,"Expecting $file") or exit;
    }

    my $domain2 = rvd_back->search_domain($name);
    ok($domain,"Expecting domain '$name'");

    if ($domain2) {
        my @vols2 = sort $domain->list_volumes();
        is_deeply(\@vols2,\@vols) or exit;
        is_deeply([_vols_md5($domain)],\@md5);

        is($domain2->id,$domain->id, $vm->type) or exit;
        $domain->remove(user_admin);
    }

    unlink($backup->{file});
    unlink($file2) or die "$! $file2";
}

sub backup_clone($vm) {
    my $base = create_domain_v2(vm => $vm, swap => 1, data => 1);
    _remove_iso($base);
    my $clone = $base->clone(name => new_domain_name()
        ,user => user_admin
    );

    my @vols = sort $clone->list_volumes();
    my @md5 = _vols_md5($clone);

    $clone->backup();

    my ($backup) = $clone->list_backups;

    my $file = $backup->{file};
    my $file2 = $file.".copy.tgz";
    copy($file,$file2);

    my $name = $clone->name;

    $clone->remove(user_admin);

    my $clone_restored;
    $clone_restored = rvd_back->restore_backup($file2,0);
    ok($clone_restored,"Expected clone restored");

    is($clone_restored->id,$clone->id);
    is($clone_restored->id_base, $base->id);

    $clone_restored->remove(user_admin) if $clone_restored;

    unlink($backup->{file});
    unlink($file2);
}

sub backup_clone_fail($vm) {
    my $base = create_domain_v2(vm => $vm, swap => 1, data => 1);
    _remove_iso($base);
    my $clone = $base->clone(name => new_domain_name()
        ,user => user_admin
    );

    my @vols = sort $clone->list_volumes();
    my @md5 = _vols_md5($clone);

    $clone->backup();

    my ($backup) = $clone->list_backups;

    my $file = $backup->{file};
    my $file2 = $file.".copy.tgz";
    copy($file,$file2);

    my $name = $clone->name;

    $clone->remove(user_admin);
    $base->remove(user_admin);

    my $clone_restored;
    eval {
        $clone_restored = rvd_back->restore_backup($file2,0);
    };
    ok(!$clone_restored,"Expected fail when trying to restore a clone without the base");
    like($@,qr/base .*not found/);
    diag($@);
    $clone_restored->remove(user_admin) if $clone_restored;

    unlink($backup->{file});
    unlink($file2);
}

sub backup_clone_and_base($vm) {
    my $base = create_domain_v2(vm => $vm, swap => 1, data => 1);
    _remove_iso($base);
    my $clone = $base->clone(name => new_domain_name()
        ,user => user_admin
    );

    my @vols_base = $base->list_files_base(1);
    my @md5 = _vols_md5($clone);

    $base->backup();
    $clone->backup();

    my ($backup_base) = $base->list_backups;
    my ($backup_clone) = $clone->list_backups;

    my $clone_name = $clone->name;
    my $base_name = $base->name;
    my $clone_id = $clone->id;
    my $base_id = $base->id;

    $clone->remove(user_admin);
    $base->remove(user_admin);

    rvd_back->restore_backup($backup_base->{file});
    rvd_back->restore_backup($backup_clone->{file});

    my $base_restored = rvd_back->search_domain($base_name);
    ok($base_restored);
    is($base_restored->id, $base_id);
    is_deeply([$base_restored->list_files_base(1)], \@vols_base)
        or die Dumper([$base_restored->list_files_base()], \@vols_base);

    is($base_restored->base_in_vm($vm->id),1);

    my $clone_restored = rvd_back->search_domain($clone_name);
    ok($clone_restored);
    is($clone_restored->id, $clone_id);
    is($clone_restored->_data('id_base'), $base_id);

    Ravada::Request->start_domain( uid => user_admin->id
        ,id_domain => $clone_restored->id
    );
    wait_request();

    $clone_restored->remove(user_admin) if $clone_restored;
    $base_restored->remove(user_admin)  if $base_restored;
    unlink($backup_base->{file});
    unlink($backup_clone->{file});

}
sub backup_clone_base_different($vm) {
    my $base = create_domain_v2(vm => $vm, swap => 1, data => 1);
    _remove_iso($base);
    my $clone = $base->clone(name => new_domain_name()
        ,user => user_admin
    );

    my @vols = sort $clone->list_volumes();
    my @md5 = _vols_md5($clone);

    $clone->backup();

    my ($backup) = $clone->list_backups;

    my $file = $backup->{file};
    my $file2 = $file.".copy.tgz";
    copy($file,$file2);

    my $clone_name = $clone->name;
    my $base_name = $base->name;

    $clone->remove(user_admin);
    $base->remove(user_admin);

    my $base2 = create_domain_v2(vm => $vm, swap => 1, data => 1
        ,name => $base_name
    );
    my $clone_restored;
    eval {
        $clone_restored = rvd_back->restore_backup($file2,0);
    };
    ok(!$clone_restored,"Expected fail when trying to restore a clone with wrong base");
    like($@,qr/base .*not found/);
    $clone_restored->remove(user_admin) if $clone_restored;

    unlink($backup->{file});
    unlink($file2);
}

sub backup_clash_user($vm) {
    #TODO
}

sub test_req_backup($vm) {
    my $domain = create_domain($vm);
    my $user = create_user();

    my $req = Ravada::Request->backup(
        uid => $user->id
        ,id_domain => $domain->id
    );
    wait_request(check_error => 0);
    like($req->error,qr/not authorized/i);

    $domain->start(user_admin);

    $req = Ravada::Request->backup(
        uid => user_admin->id
        ,id_domain => $domain->id
    );
    wait_request(check_error => 0);
    like($req->error,qr/is active/i);

    my $req_shutdown = Ravada::Request->shutdown_domain(
        uid => user_admin->id
        ,id_domain=> $domain->id
    );
    wait_request();

    $req->redo();

    wait_request();
    is($req->error,'');
    like($req->output,qr /\//);

    remove_domain($domain);

    my $file = $req->output;
    chomp $file;
    return $file;
}

sub test_req_restore($vm, $file) {
    my $req = Ravada::Request->restore_backup(
        uid => user_admin->id
        ,file => $file
    );
    wait_request();
}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        my $file = test_req_backup($vm);
        test_req_restore($vm, $file);

        backup_auto_start($vm);

        backup_clone_and_base($vm);
        backup_clone_base_different($vm);

        backup_clone($vm);
        backup_clone_fail($vm);

        restore_from_file($vm);
        restore_from_file($vm,"remove");

        backup($vm);
        backup($vm,"remove_user");

        backup_clash_user($vm);

        backup_different_id_vm($vm);

    }
}

end();

done_testing();

