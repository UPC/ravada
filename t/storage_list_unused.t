use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Copy;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my @FILES;
########################################################################

sub _new_file($vm) {
    my $file;
    for ( ;; ) {
        $file = $vm->dir_img."/00_".new_domain_name()."-".Ravada::Utils::random_name().".txt";
        last if !$vm->file_exists($file);
    }
    $vm->write_file($file,'');
    return $file;
}

sub test_links($vm, $machine) {
    my $dir = $vm->dir_img();

    my ($vol) = $machine->list_volumes();
    my ($file) = $vol =~ m{.*/(.*)};
    my $dst = "/var/tmp/$file";
    unlink $dst or die "$! $dst" if -e $dst;
    push @FILES,($dst);

    copy($vol,$dst) or die "$! $vol -> $dst";
    unlink $vol or die "$! $vol";

    symlink($dst,$vol) or die "$dst -> $vol";

    my $link = $vm->_is_link($vol);
    ok($link) or exit;
    is($link, $dst) or exit;

    my $req2 = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 0
        ,limit => 1000
    );
    wait_request();
    my $out_json = $req2->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);
    my $found = _search_file($output, $vol);

    ok(!$found,"Expecting $vol not found") or die Dumper([$machine->list_volumes]);

}

sub test_links_dir($vm, $machine) {
    my $dir = $vm->dir_img();

    my ($vol) = $machine->list_volumes();
    my ($file) = $vol =~ m{.*/(.*)};
    my $dir_dst = "/var/tmp/".new_domain_name();
    mkdir $dir_dst if ! -e $dir_dst;

    push @FILES,($dir_dst);

    my $dir_link = "/var/tmp/".new_domain_name();
    my $file_link = "$dir_link/$file";
    push @FILES,($file_link);

    unlink($dir_link) or die "$! $dir_link"
    if -e $dir_link;

    symlink($dir_dst, $dir_link) or die "$! $dir_dst -> $dir_link";
    push @FILES,($dir_link);

    my $dst = "$dir_dst/$file";
    copy($vol,$dst) or die "$vol -> $dst";
    unlink $vol or die "$! $vol";


    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $machine->id
        ,hardware => 'disk'
        ,data => { file => $file_link }
        ,index => 0
    );
    wait_request();

    my $link = $vm->_is_link($file_link);
    ok($link) or exit;
    is($link, $dst) or exit;

    my $link_no = $vm->_is_link($dir_dst);
    ok(!$link_no) or exit;

    my $req2 = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 0
        ,limit => 1000
    );
    wait_request();
    my $out_json = $req2->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);
    for my $exp ($file_link, "$dir_dst/$file" ) {
        my $found = _search_file($output, $exp);

        ok(!$found,"Expecting $exp not found") or die Dumper([$machine->list_volumes]);
    }

}


sub test_list_unused_discover($vm, $machine) {
    $vm->refresh_storage();

    my @volumes = $machine->list_volumes;

    my $sth = connector->dbh->prepare(
        "DELETE FROM volumes WHERE id_domain=?"
    );
    $sth->execute($machine->id);

    my $req = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 0
        ,limit => 1000
    );
    wait_request();
    my $out_json = $req->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);

    for my $vol (@volumes) {
        my $found = _search_file($output, $vol);
        ok(!$found,"Expecting $vol not found");
    }

}

sub test_list_unused_discover2($vm) {

    my $base = create_domain($vm);
    $base->prepare_base(user_admin);

    my $base2 = $base->clone(name => new_domain_name
        ,user => user_admin
    );
    $base2->prepare_base(user_admin);

    my $machine = $base2->clone(name => new_domain_name
        ,user => user_admin
    );

    my @volumes;

    for my $d ($base, $base2, $machine) {
        push @volumes, ( $d->list_volumes, $d->list_files_base );
        my $sth = connector->dbh->prepare(
            "DELETE FROM volumes WHERE id_domain=?"
        );
        $sth->execute($d->id);
    }
    $vm->refresh_storage();

    my $req = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 0
        ,limit => 1000
    );
    wait_request();
    my $out_json = $req->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);

    for my $vol (@volumes) {
        my $found = _search_file($output, $vol);
        ok(!$found,"Expecting $vol not found");
    }

}


sub test_list_unused($vm, $machine, $hidden_vols) {
    my $dir = $vm->dir_img();

    my $file = _new_file($vm);
    push @FILES,($file);

    my $new_dir = $dir."/".new_domain_name();
    push @FILES,($new_dir);

    if (! -e $new_dir) {
        mkdir $new_dir or die "$! $new_dir";
    }

    open my $out,">",$file or die "$! $file";
    print $out "hi\n";
    close $out;
    $vm->refresh_storage();

    my $req = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 0
        ,limit => 1000
    );
    wait_request();
    my $out_json = $req->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);
    my $found = _search_file($output, $file);

    ok($found,"Expecting $file found ") or die Dumper($output);

    my @used_vols = _used_volumes($machine);
    for my $vol (@used_vols, @$hidden_vols, $machine->list_volumes) {
        my $found = _search_file($output, $vol);
        ok(!$found,"Expecting $vol not found");
    }

    my ($found_dir) = _search_file($output, $new_dir);
    ok(!$found_dir,"Expecting not found $new_dir");

    _test_vm($vm, $machine, $output);
}

sub test_page($vm) {
    my $req = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 0
        ,limit => 10
    );
    wait_request();
    my $out_json = $req->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);

    my $req2 = Ravada::Request->list_unused_volumes(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,start => 10
        ,limit => 20
    );
    wait_request();
    my $out_json2 = $req2->output;
    $out_json2 = '[]' if !defined $out_json2;
    my $output2 = decode_json($out_json2);

    isnt($output2, $output);

}

sub _test_vm($vm, $domain, $output) {
    if ($vm->type eq 'Void') {
        my $config = $domain->_config_file();
        my ($found) = _search_file($output, $config);
        ok(!$found,"Expecting no $config found");

        my $lock = "$config.lock";

        ($found) = _search_file($output, $lock);
        ok(!$found,"Expecting no $lock found");
    }
}

sub _search_file($output, $file) {
    my $found;
    die "Missing list item" unless exists $output->{list};

    my $list = $output->{list};
    ($found) = grep( {$file eq $_->{file}} @$list);
    return $found;
}

sub _used_volumes($machine) {
    my $info = $machine->info(user_admin);
    my @used;
    for my $vol ( @{$info->{hardware}->{disk}} ) {
        push @used,($vol->{file}) if $vol->{file};
    }
    if ($machine->id_base) {
        my $base = Ravada::Front::Domain->open($machine->id_base);
        push @used,_used_volumes($base);
        push @used,$base->list_files_base();
    }
    return @used;
}

sub _clean_files($files=\@FILES) {
    my @dirs;
    for my $file (@$files) {
        if (-f $file || -l $file) {
            unlink $file or warn "$! $file";
        } elsif (-d $file) {
            push @dirs,($file);
        }

    }

    for my $file (@dirs) {
        my @files;
        my $pattern = base_domain_name();
        opendir my $ls,$file or die "$! $file";
        while (my $in = readdir $ls) {
            push @files,("$file/$in") if $in =~ /^$pattern/;
        }
        _clean_files(\@files);
        rmdir($file) or warn "$! $file";
    }

}

sub _create_clone($vm) {
    my $base0 = create_domain($vm);
    $base0->prepare_base(user_admin);

    my $base = $base0->clone(name => new_domain_name
        ,user => user_admin
    );
    $base->prepare_base(user_admin);

    my $clone = $base->clone(name => new_domain_name
        ,user => user_admin
    );
    return $clone;
}

sub _hide_backing_store($machine) {
    return if $machine->type ne 'KVM';
    my @used_volumes = _used_volumes($machine);
    my $doc = XML::LibXML->load_xml(string => $machine->xml_description());
    for my $vol ($doc->findnodes("/domain/devices/disk")) {
        my ($bs) = $vol->findnodes("backingStore");
        next if !$bs;
        $vol->removeChild($bs);
    }
    return @used_volumes;
}

sub _create_clone_hide_bs($clone) {
    my $base = Ravada::Domain->open($clone->id_base);
    my $clone2 = $base->clone(name => new_domain_name
        ,user => user_admin
    );
    _hide_backing_store($clone2);

    return $clone2;
}

sub test_remove($vm, $clone) {
    my $file = _new_file($vm);
    ok(-e $file) or exit;
    my $user = create_user(new_domain_name(),"bar");
    my $req_fail = Ravada::Request->remove_files(
        uid => $user->id
        ,id_vm => $vm->id
        ,files => $file
    );

    wait_request(check_error => 0);
    like($req_fail->error,qr/not authorized/);

    my ($file_clone) = $clone->list_volumes();

    my $req_fail2 = Ravada::Request->remove_files(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,files => $file_clone
    );

    wait_request(check_error => 0);
    like($req_fail2->error,qr/in use by/);
    ok( -e $file_clone, "Expecting file $file_clone not removed");

    my $req = Ravada::Request->remove_files(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,files => $file
    );

    wait_request();
    ok(!-e $file);
}

sub test_remove_many($vm) {
    my $file1 = _new_file($vm);
    my $file2 = _new_file($vm);
    my $user = create_user(new_domain_name(),"bar");
    $vm->refresh_storage_pools();
    my $req= Ravada::Request->remove_files(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,files => [$file1, $file2]
    );
    wait_request();
    ok(!-e $file1);
    ok(!-e $file2);
}

sub test_more($vm) {
    my $out_old = '';
    my $more;

    my $start = 0;
    for ( 1 .. 100 ) {
        my $req = Ravada::Request->list_unused_volumes(
            uid => user_admin->id
            ,start => $start
            ,id_vm => $vm->id
        );
        wait_request();
        my $out_json = $req->output;
        $out_json = '{}' if !defined $out_json;
        my $output = decode_json($out_json);

        my $list = $output->{list};
        $more = $output->{more};
        last if !$more;
        $start+=10;
    }
    ok(!$more);
}

sub test_linked_sp($vm) {
    my $dir = $vm->dir_img();
    my $new_name=new_domain_name();

    my $new_dir = "/var/tmp/".$new_name;
    unlink $new_dir or die "$! $new_dir" if -e $new_dir;

    symlink($dir,$new_dir) or die "$dir -> $new_dir";

    $vm->create_storage_pool($new_name, $new_dir)
    if !grep { $_ eq $new_name} $vm->list_storage_pools;

    if ($vm->type eq 'KVM') {
        my $pool = $vm->vm->get_storage_pool_by_name($new_name);
        $pool->create() if !$pool->is_active;
        $pool->refresh();
        my @vols = $pool->list_volumes;
        warn Dumper(scalar(@vols));
    }

    my $req = Ravada::Request->list_unused_volumes(
            uid => user_admin->id
            ,id_vm => $vm->id
            ,limit => 0
    );
    wait_request();
    my $out_json = $req->output;
    $out_json = '{}' if !defined $out_json;
    my $output = decode_json($out_json);

    my $list = $output->{list};
    my @found = grep ($_->{file} =~ /^$new_dir/, @$list);
    is( scalar(@found),0);
    exit;
}

########################################################################

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

        my $clone = _create_clone($vm);
        my @hidden_bs = _create_clone_hide_bs($clone);

        test_linked_sp($vm);

        test_list_unused_discover($vm, $clone);
        test_list_unused_discover2($vm);

        test_list_unused($vm, $clone, \@hidden_bs);


        test_links_dir($vm, $clone);
        test_links($vm, $clone);

        test_page($vm);

        test_remove($vm, $clone);
        test_remove_many($vm);

        test_more($vm);
    }
}

_clean_files();
end();

done_testing();

