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
    $domain->restore_backup($backup,0);

    my @md5_restored = _vols_md5($domain);
    is_deeply(\@md5_restored, \@md5) or exit;

    is($domain->_data('id_owner'),$id_owner);

    my $domain2 = $vm->search_domain($domain->name);
    is($domain2->id, $domain->id);

    my $new_owner = Ravada::Auth::SQL->search_by_id($domain->_data('id_owner'));
    ok($new_owner);

    is($domain->list_backups(),1);

    $domain->remove_backup($backup);

    ok(!-e $backup->{file},"$backup->{file} should have been removed");
    is($domain->list_backups(),0);

    $domain->backup();
    ($backup) = $domain->list_backups();

    $domain->remove(user_admin);
    ok(!-e $backup->{file},"$backup->{file} should have been removed");
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

    unlink($file2) or die "$! $file2";
}

sub backup_clash_user($vm) {
    #TODO
}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        restore_from_file($vm);
        restore_from_file($vm,"remove");

        backup($vm);
        backup($vm,"remove_user");

        backup_clash_user($vm);
    }
}

end();

done_testing();

