use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my @FILES;
########################################################################

sub test_list_unused($vm, $machine, $hidden_vols) {
    my $dir = $vm->dir_img();
    my $file;
    for ( ;; ) {
        $file = $dir."/".new_domain_name()."-".Ravada::Utils::random_name().".txt";
        last if !$vm->file_exists($file);
    }
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
    );
    wait_request();
    my $out_json = $req->output;
    $out_json = '[]' if !defined $out_json;
    my $output = decode_json($out_json);
    my $found = _search_file($output, $file);

    ok($found,"Expecting $file found ") or exit;

    my @used_vols = _used_volumes($machine);
    for my $vol (@used_vols, @$hidden_vols) {
        my $found = _search_file($output, $vol);
        ok(!$found,"Expecting $vol not found");
    }

    my ($found_dir) = _search_file($output, $new_dir);
    ok(!$found_dir,"Expecting not found $new_dir");

    _test_vm($vm, $machine, $output);
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
    for my $id_vm ( sort keys %$output ) {
        my $list = $output->{$id_vm};
        ($found) = grep(/^$file$/,@$list);
        return $found if $found;
    }
    return;
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

sub _clean_files() {
    for my $file (@FILES) {
        if (-d $file) {
            rmdir $file or warn "$! $file";
        } else {
            unlink $file or warn "$! $file";
        }
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
        test_list_unused($vm, $clone, \@hidden_bs);
    }
}

_clean_files();
end();

done_testing();
