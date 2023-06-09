use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Mojo::JSON qw(decode_json);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

#########################################################################

sub create_pool($vm_name, $dir="/var/tmp/".new_pool_name()) {

    my $vm = rvd_back->search_vm($vm_name) or return;

    my $capacity = 1 * 1024 * 1024;

    my $pool_name = new_pool_name();
    mkdir $dir if ! -e $dir;

    _create_pool($vm, $pool_name, $dir, $capacity);
    test_req_list_sp($vm);
    return $pool_name if !wantarray;
    return ($pool_name, $dir);
}

sub test_create_pool_fail($vm) {
    my $dir = "/var/tmp/$$/".new_pool_name();
    unlink $dir or die "$! $dir" if -e $dir;

    my $name = new_pool_name();

    my $req = Ravada::Request->create_storage_pool(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => $name
        ,directory => $dir
    );
    wait_request( check_error => 0);
    like($req->error,qr/./);

    my @list = $vm->list_storage_pools(1);
    my ($found) = grep { $_->{name} eq $name } @list;
    ok(!$found,"Expected storage pool $name not created");
}

sub _create_pool($vm,@args) {
    if ($vm->type eq 'KVM') {
        _create_pool_kvm($vm,@args);
    } elsif($vm->type eq 'Void') {
        _create_pool_void($vm,@args);
    }
}

sub _create_pool_void($vm,$pool_name, $dir, $capacity) {
    $vm->create_storage_pool($pool_name, $dir);
}

sub _create_pool_kvm($vm,$pool_name, $dir, $capacity) {
    my $pool;
    for ( ;; ) {
        my $uuid = $vm->_unique_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');
        my $xml =
                    "<pool type='dir'>
                    <name>$pool_name</name>
                    <uuid>$uuid</uuid>
                    <capacity unit='bytes'>$capacity</capacity>
                    <allocation unit='bytes'></allocation>
                    <available unit='bytes'>$capacity</available>
                    <source>
                    </source>
                    <target>
                    <path>$dir</path>
                    <permissions>
                    <mode>0711</mode>
                    <owner>0</owner>
                    <group>0</group>
                    </permissions>
                    </target>
                    </pool>"
                    ;
        eval { $pool = $vm->vm->create_storage_pool($xml) };
        last if !$@ || $@ !~ /libvirt error code: 9,/;
    };
    ok(!$@,"Expecting \$@='', got '".($@ or '')."'") or return;
    ok($pool,"Expecting a pool , got ".($pool or ''));
}


sub test_req_list_sp($vm) {
    my $req = Ravada::Request->list_storage_pools(id_vm => $vm->id , uid => user_admin->id);
    wait_request();
    is($req->status,'done');
    is($req->error,'');
    my $json_out = $req->output;
    my $pools = decode_json($json_out);
    for my $pool ( @$pools ) {
        like($pool,qr{^[a-z][a-z0-9]*}) or die Dumper($pools);
    }
    ok(scalar @$pools);
}

sub test_create_domain {
    my $vm_name = shift;
    my $pool_name = shift or confess "Missing pool_name";

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;
    my $old_sp = $vm->default_storage_pool_name($pool_name);
    is($vm->default_storage_pool_name($pool_name), $pool_name) or exit;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
		    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );
    for my $volume ( $domain->list_volumes(device => 'disk')) {
        like($volume,qr{^/var/tmp});
    }
    $vm->default_storage_pool_name($old_sp);

    return $domain;

}

sub test_remove_domain {
    my ($vm_name, $domain) = @_;

    my @volumes = $domain->list_volumes();
    ok(scalar@volumes,"Expecting some volumes, got :".scalar@volumes);

    for my $file (@volumes) {
        ok(-e $file,"Expecting volume $file exists, got : ".(-e $file or 0));
    }
    $domain->remove($USER);
    for my $file (@volumes) {
        if ($file =~ /iso$/) {
            ok(-e $file,"Expecting volume $file not removed , got : ".(-e $file or 0));
        } else {
            ok(!-e $file,"Expecting no volume $file exists, got : ".(-e $file or 0));
        }
    }

}

sub test_base {
    my $domain = shift;
    eval { $domain->prepare_base( user_admin ) };
    is(''.$@,'',"Prepare base") or exit;

    my @files_base = $domain->list_files_base();
    is(scalar @files_base, 2);
    for my $file (@files_base) {
        ok(-e $file,"Expecting volume $file exists, got : ".(-e $file or 0));
    }

    my ($path0) = $files_base[0] =~ m{(.*)/};
    my ($path1) = $files_base[1] =~ m{(.*)/};

    is($path0,$path1);

    $domain->remove_base( user_admin );

    for my $file (@files_base) {
        ok(!-e $file,"Expecting volume $file doesn't exist, got : ".(-e $file or 0));
    }

}

sub test_volumes_in_two_pools {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my ($pool_name1) = create_pool($vm_name);
    $vm->default_storage_pool_name($pool_name1);
    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    my $pool_name2 = create_pool($vm_name);
    $vm->default_storage_pool_name($pool_name2);
    is($vm->default_storage_pool_name(), $pool_name2);
    like($vm->dir_img, qr{^/var/tmp}) or exit;

    $domain->add_volume(name => $name.'_volb' , size => 1024*1024 );

    my @volumes = $domain->list_volumes( device => 'disk' );
    is(scalar @volumes , 2,$domain->type." "
        .Dumper([$domain->list_volumes_info(device => 'disk')]
                ,\@volumes
        )) or exit;
    for my $file (@volumes) {
        ok(-e $file,"Expecting volume $file exists, got : ".(-e $file or 0));
        like($file,qr(^/var/tmp));
    }

    my ($path0) = $volumes[0] =~ m{(.*)/};
    my ($path1) = $volumes[1] =~ m{(.*)/};

    isnt($path0,$path1);

    test_base($domain);

    for my $file (@volumes) {
        ok(-e $file,"Expecting volume $file exists, got : ".(-e $file or 0));
    }
    $domain->remove($USER);
    for my $file (@volumes) {
        ok(!-e $file,"Expecting volume $file doesn't exist, got : ".(-e $file or 0));
    }
}

sub test_default_pool {
    my $vm_name = shift;
    my $pool_name = shift or confess "Missing pool_name";
    {
        my $vm = rvd_back->search_vm($vm_name);
        $vm->default_storage_pool_name($pool_name)
            if $vm->default_storage_pool_name() ne $pool_name;
    }
    my $vm = rvd_back->search_vm($vm_name);
    is($vm->default_storage_pool_name, $pool_name);
}

sub test_base_pool {
    my $vm = shift;
    my $pool_name = shift;

    my %pool = (
        default => $vm->_storage_path('default')
        ,$pool_name => $vm->_storage_path($pool_name)
    );
    for my $name1 (keys %pool ) {
        my $dir_pool1 = $pool{$name1};
        $vm->default_storage_pool_name($name1);
        my $domain = create_domain($vm->type);
        $domain->add_volume_swap( size => 1000000 );
        ok($domain);

        for my $volume ($domain->list_volumes(device => 'disk') ) {
            my ($path ) = $volume =~ m{(.*)/.*};
            like($path, qr{$dir_pool1}, $volume) or exit;
        }
        for my $name2 ( $pool_name, 'default' ) {
            my $dir_pool2 = $pool{$name2};
            $vm->base_storage_pool($name2);
            is($vm->base_storage_pool(),$name2);
            $domain->prepare_base(user_admin);

            ok(scalar ($domain->list_files_base));
            for my $volume ($domain->list_files_base) {
                my ($path ) = $volume =~ m{(.*)/.*};
                like($path, qr{$dir_pool2}) or exit;
            }

            my $clone = $domain->clone(
                name => new_domain_name()
                ,user => user_admin
            );
            ok(scalar ($clone->list_volumes));
            for my $volume ($clone->list_volumes) {
                die "Empty volume ".Dumper([$clone->list_volumes],[$clone->list_volumes_info])
                    if !$volume;
                my ($path ) = $volume =~ m{(.*)/.*};
                confess "I can't find path from $volume" if !$path;
                like($path, qr{$dir_pool1});
            }

            $clone->remove(user_admin);
            $domain->remove_base(user_admin);
            is($domain->is_base,0);
        }
        $domain->remove(user_admin);
    }

}

sub test_clone_pool {
    my $vm = shift;
    my $pool_name = shift;

    $vm->base_storage_pool('');
    my %pool = (
        default => $vm->_storage_path('default')
        ,$pool_name => $vm->_storage_path($pool_name)
    );
    for my $name1 (keys %pool ) {
        my $dir_pool1 = $pool{$name1};
        $vm->default_storage_pool_name($name1);
        my $domain = create_domain($vm->type);
        $domain->add_volume_swap( size => 1000000 );
        ok($domain);

        for my $volume ($domain->list_volumes(device => 'disk') ) {
            my ($path ) = $volume =~ m{(.*)/.*};
            like($path, qr{$dir_pool1}, $volume);
        }
        for my $name2 ( $pool_name, 'default' ) {
            my $dir_pool2 = $pool{$name2};
            $vm->clone_storage_pool($name2);
            is($vm->clone_storage_pool(),$name2);
            $domain->prepare_base(user_admin);

            ok(scalar ($domain->list_files_base));
            for my $volume ($domain->list_files_base) {
                my ($path ) = $volume =~ m{(.*)/.*};
                like($path, qr{$dir_pool1});
            }

            my $clone = $domain->clone(
                name => new_domain_name()
                ,user => user_admin
            );
            ok(scalar ($clone->list_volumes));
            for my $volume ($clone->list_volumes) {
                my ($path ) = $volume =~ m{(.*)/.*};
                like($path, qr{$dir_pool2});
            }

            $clone->remove(user_admin);
            $domain->remove_base(user_admin);
            is($domain->is_base,0);
        }
        $domain->remove(user_admin);
    }
}

sub test_base_clone_pool {
    my $vm = shift;
    my $pool_name1 = shift;
    my $pool_name2 = shift;

    $vm->base_storage_pool('');
    my %pool = (
        default => $vm->_storage_path('default')
        ,$pool_name1 => $vm->_storage_path($pool_name1)
        ,$pool_name2 => $vm->_storage_path($pool_name2)
    );
    # default pool
    for my $name (keys %pool ) {
        my $dir_pool = $pool{$name};
        $vm->default_storage_pool_name($name);
        my $domain = create_domain($vm->type);
        $domain->add_volume_swap( size => 1000000 );
        ok($domain);

        for my $volume ($domain->list_volumes(device => 'disk') ) {
            my ($path ) = $volume =~ m{(.*)/.*};
            like($path, qr{$dir_pool});
        }

        test_base_pool_2($vm, \%pool, $domain);

        $domain->remove(user_admin);
    }
}

sub test_base_pool_2($vm, $pool, $domain) {
    for my $name ( keys %$pool) {
        my $dir_pool = $pool->{$name};

        $vm->base_storage_pool($name);
        is($vm->base_storage_pool(),$name);

        $domain->prepare_base(user_admin);

        ok(scalar ($domain->list_files_base));
        for my $volume ($domain->list_files_base) {
            my ($path ) = $volume =~ m{(.*)/.*};
            like($path, qr{$dir_pool});
        }

        test_clone_pool_2($vm, $pool, $domain);
        $domain->remove_base(user_admin);
        is($domain->is_base,0);
    }
}

sub test_clone_pool_2($vm, $pool, $base) {
    for my $name ( keys %$pool) {
        my $dir_pool = $pool->{$name};

        $vm->clone_storage_pool($name);
        is($vm->clone_storage_pool($name), $name);

        my $clone = $base->clone(
            name => new_domain_name()
            ,user => user_admin
        );
        ok(scalar ($clone->list_volumes));
        for my $volume ($clone->list_volumes) {
            my ($path ) = $volume =~ m{(.*)/.*};
            like($path, qr{$dir_pool});
        }
        $clone->remove(user_admin);
    }
}

sub test_default_pool_base {
    my $vm = shift;
    my $pool_name = shift;

    my %pool = (
        default => $vm->_storage_path('default')
        ,$pool_name => $vm->_storage_path($pool_name)
    );
    $vm->base_storage_pool('');
    for my $name1 (keys %pool ) {
        my $dir_pool = $pool{$name1};
        $vm->default_storage_pool_name($name1);
        my $domain = create_domain($vm->type);
        ok($domain);

        for my $volume ($domain->list_volumes(device => 'disk') ) {
            my ($path ) = $volume =~ m{(.*)/.*};
            like($path, qr{$dir_pool});
        }
        for my $name2 ( $pool_name, 'default' ) {
            my $dir_pool2 = $pool{$name2};
            $vm->default_storage_pool_name($name2);
            $domain->prepare_base(user_admin);

            ok(scalar ($domain->list_files_base));
            for my $volume ($domain->list_files_base) {
                my ($path ) = $volume =~ m{(.*)/.*};
                like($path, qr{$dir_pool2}) or die Dumper($vm->{_data});
            }

            $domain->remove_base(user_admin);
            is($domain->is_base,0);
        }
        $domain->remove(user_admin);
    }
}


sub _create_pool_linked($vm, $dir=undef) {
    my $capacity = 1 * 1024 * 1024;

    my $pool_name = new_pool_name();
    $dir = "/var/tmp/$pool_name" if !$dir;
    my $dir_link = "$dir.link";

    mkdir $dir if ! -e $dir;
    unlink $dir_link or die "$! $dir_link" if -e $dir_link;

    symlink($dir, $dir_link) or die "$! linking $dir -> $dir_link";

    my $pool;
    for ( ;; ) {
        my $uuid = $vm->_unique_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');
        my $xml =
                    "<pool type='dir'>
                    <name>$pool_name</name>
                    <uuid>$uuid</uuid>
                    <capacity unit='bytes'>$capacity</capacity>
                    <allocation unit='bytes'></allocation>
                    <available unit='bytes'>$capacity</available>
                    <source>
                    </source>
                    <target>
                    <path>$dir_link</path>
                    <permissions>
                    <mode>0711</mode>
                    <owner>0</owner>
                    <group>0</group>
                    </permissions>
                    </target>
                    </pool>"
                    ;
        eval { $pool = $vm->vm->create_storage_pool($xml) };
        last if !$@ || $@ !~ /libvirt error code: 9,/;
    };
    ok(!$@,"Expecting \$@='', got '".($@ or '')."'") or return;
    ok($pool,"Expecting a pool , got ".($pool or ''));

    return ($pool_name, $dir, $dir_link);
}

sub _create_pool_linked_reverse($vm) {
    return if $vm->type ne 'KVM';

    my $capacity = 1 * 1024 * 1024;

    my $pool_name = new_pool_name();
    my $dir = "/var/tmp/$pool_name";
    my $dir_link = "$dir.link";

    mkdir $dir if ! -e $dir;
    unlink $dir_link or die "$! $dir_link" if -e $dir_link;

    symlink($dir, $dir_link) or die "$! linking $dir -> $dir_link";

    my $pool;
    for ( ;; ) {
        my $uuid = $vm->_unique_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');
        my $xml =
                    "<pool type='dir'>
                    <name>$pool_name</name>
                    <uuid>$uuid</uuid>
                    <capacity unit='bytes'>$capacity</capacity>
                    <allocation unit='bytes'></allocation>
                    <available unit='bytes'>$capacity</available>
                    <source>
                    </source>
                    <target>
                    <path>$dir</path>
                    <permissions>
                    <mode>0711</mode>
                    <owner>0</owner>
                    <group>0</group>
                    </permissions>
                    </target>
                    </pool>"
                    ;
        eval { $pool = $vm->vm->create_storage_pool($xml) };
        last if !$@ || $@ !~ /libvirt error code: 9,/;
    };
    ok(!$@,"Expecting \$@='', got '".($@ or '')."'") or return;
    ok($pool,"Expecting a pool , got ".($pool or ''));

    return ($pool_name, $dir, $dir_link);
}


sub test_pool_linked($vm) {
    return if $vm->type ne 'KVM';
    my ($pool_name, $dir, $dir_link) = _create_pool_linked($vm);

    $vm->default_storage_pool_name($pool_name);

    my $domain1 = create_domain($vm);
    $domain1->prepare_base(user_admin);
    my $clone1 = $domain1->clone(
        name => new_domain_name
        ,user => user_admin
    );

    $clone1->remove(user_admin);
    $domain1->remove(user_admin);
}

sub test_pool_linked_reverse($vm) {
    return if $vm->type ne 'KVM';
    my ($pool_name, $dir, $dir_link) = _create_pool_linked_reverse($vm);

    $vm->default_storage_pool_name($pool_name);

    my $domain1 = create_domain($vm);
    $domain1->prepare_base(user_admin);
    my $clone1 = $domain1->clone(
        name => new_domain_name
        ,user => user_admin
    );

    $clone1->remove(user_admin);
    $domain1->remove(user_admin);
}


sub test_pool_linked2($vm) {
    return if $vm->type ne 'KVM';
    my ($pool_name, $dir, $dir_link) = _create_pool_linked($vm);

    $vm->default_storage_pool_name($pool_name);

    my $domain1 = create_domain($vm);
    my $new_vol = "$dir/new_volume.qcow2";
    my $new_vol_linked = "$dir_link/new_volume.link.qcow2";
    $vm->run_command('qemu-img','create','-f','qcow2',$new_vol,'128M');
    ok( -e $new_vol);
    $vm->run_command('qemu-img','create','-f','qcow2',$new_vol_linked,'128M');
    ok( -e $new_vol_linked);
    $domain1->add_volume(file => $new_vol);
    $domain1->add_volume(file => $new_vol_linked);

    for my $vol ( $domain1->list_volumes_info ) {
        my $capacity;
        eval { $capacity = $vol->capacity };
        is($@, '', $vol->file);
        ok($capacity, $vol->file);
    }

    $domain1->prepare_base(user_admin);
    my $clone1 = $domain1->clone(
        name => new_domain_name
        ,user => user_admin
    );

    $clone1->remove(user_admin);
    $domain1->remove(user_admin);
}

sub test_pool_linked2_reverse($vm) {
    return if $vm->type ne 'KVM';

    my ($pool_name, $dir, $dir_link) = _create_pool_linked_reverse($vm);

    $vm->default_storage_pool_name($pool_name);

    my $domain1 = create_domain($vm);
    my $new_vol = "$dir/new_volume.qcow2";
    my $new_vol_linked = "$dir_link/new_volume.link.qcow2";
    $vm->run_command('qemu-img','create','-f','qcow2',$new_vol,'128M');
    ok( -e $new_vol);
    $vm->run_command('qemu-img','create','-f','qcow2',$new_vol_linked,'128M');
    ok( -e $new_vol_linked);
    $domain1->add_volume(file => $new_vol);
    $domain1->add_volume(file => $new_vol_linked);

    for my $vol ( $domain1->list_volumes_info ) {
        my $capacity;
        eval { $capacity = $vol->capacity };
        is($@, '', $vol->file);
        ok($capacity, $vol->file);
    }

    $domain1->prepare_base(user_admin);
    my $clone1 = $domain1->clone(
        name => new_domain_name
        ,user => user_admin
    );

    $clone1->remove(user_admin);
    $domain1->remove(user_admin);
}

sub test_pool_info($vm) {
    my $req = Ravada::Request->list_storage_pools(
        uid => user_admin->id
        ,data => 1
        ,id_vm => $vm->id

    );
    wait_request();
    my $out = $req->output;
    my $pools = decode_json($out);

    my $pool = $pools->[0];
    isa_ok($pool,'HASH');
    ok(exists $pool->{path},"expecting pool path") or die Dumper($pool);
}

sub create_machine($vm, $pool_name, $dir) {

    is($vm->default_storage_pool_name('default'), 'default');
    my $name = new_domain_name();
    my $req = Ravada::Request->create_domain(
        name => $name
        ,id_owner => user_admin->id
        ,storage => $pool_name
        ,vm => $vm->type
        ,id_iso => search_id_iso('%Alpine%64')
        ,swap => 10 * 1024
        ,data => 10 * 1024
    );
    wait_request();
    is($req->error,'');
    my $domain = $vm->search_domain($name);
    for my $vol ($domain->list_volumes) {
        next if $vol =~ /iso$/;
        like($vol,qr{$dir}) or exit;
        ok(-e $vol,"Expecting $vol") or exit;
    }
}        

sub _search_file($output, $file) {
    my $found;
    die "Missing list item" unless exists $output->{list};

    my $list = $output->{list};
    ($found) = grep( {$file eq $_->{file}} @$list);
    return $found;
}

sub test_pool_dupe($vm) {
    return if $vm->type ne 'KVM';

    my ($pool_name, $dir, $dir_link) = _create_pool_linked($vm);

    my $pool2 = create_pool($vm->type,$dir);

    my @domains;
    for my $pool ( $pool_name, $pool2) {
        $vm->default_storage_pool_name($pool);
        my $domain=create_domain($vm);
        push @domains,($domain);
    }
    $vm->refresh_storage();
    _check_linked($domains[0]);
    _check_linked_in_dir($dir_link,$domains[1]);

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

    for my $dir ($dir, $dir_link) {
        my @found = grep( {$_->{file} =~ m{^$dir/} } @{$output->{list}});
        ok(!@found,"Expecting $dir not found") or die Dumper(\@found);
    }
    $vm->default_storage_pool_name('default');
}

sub _move_volumes_kvm($domain, $dir) {
    my $doc = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);
    my $found = 0;
    for my $vol ( $doc->findnodes("/domain/devices/disk/source")) {
        $found++;
        my $file = $vol->getAttribute('file');
        my ($orig_dir,$filename) = $file =~ m{(.*)/(.*)};
        die "Error: orig dir is the same as dst in $file"
        if $orig_dir eq $dir;
        $vol->setAttribute('file' => "$dir/$filename");
    }
    die "Error: no volumes found in ".$domain->name if !$found;
    $domain->reload_config($doc);
}

sub _move_volumes($domain, $dir) {
    if ($domain->type eq 'KVM') {
        _move_volumes_kvm($domain,$dir);
    } elsif ( $domain->type eq 'Void') {
        diag("TODO ".$domain->type);
    }
}

sub test_pool_dupe_linked_1($vm) {
    return if $vm->type ne 'KVM';

    my $dir0 = "/".new_pool_name();
    my ($pool_name, $dir, $dir_link) = _create_pool_linked($vm, $dir0);

    my $pool2 = create_pool($vm->type,$dir);

    $vm->default_storage_pool_name($pool2);
    my $domain=create_domain($vm);

    _move_volumes($domain,$dir_link);

    $vm->refresh_storage();

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

    for my $dir ($dir, $dir_link) {
        my @found = grep( {$_->{file} =~ m{^$dir/} } @{$output->{list}});
        ok(!@found,"Expecting $dir not found") or die Dumper(\@found);
    }
    $vm->default_storage_pool_name('default');
}

sub test_pool_dupe_linked($vm) {
    return if $vm->type ne 'KVM';

    my ($pool_name, $dir, $dir_link) = _create_pool_linked($vm);

    my $pool2 = create_pool($vm->type,$dir);

    my @domains;
    for my $pool ( $pool_name, $pool2) {
        $vm->default_storage_pool_name($pool);
        my $domain=create_domain($vm);
        push @domains,($domain);
    }
    _move_volumes($domains[0],$dir);
    _move_volumes($domains[1],$dir_link);

    $vm->refresh_storage();

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

    for my $dir ($dir, $dir_link) {
        my @found = grep( {$_->{file} =~ m{^$dir/} } @{$output->{list}});
        ok(!@found,"Expecting $dir not found") or die Dumper(\@found);
    }
    $vm->default_storage_pool_name('default');
}

sub _check_linked_in_dir($dir, $domain) {
    my $vm = $domain->_vm;
    for my $vol ( $domain->list_volumes ) {
        next if $vol =~ /iso$/;
        my ($name) = $vol =~ m{.*/(.*)};
        my $file = "$dir/$name";
        my $link = $vm->_is_link($file);
        ok($link,"Expecting $file is link") or exit;
    }
}

sub _check_linked($domain) {
    my $vm = $domain->_vm;
    for my $vol ( $domain->list_volumes ) {
        next if $vol =~ /iso$/;
        my $link = $vm->_follow_link($vol);
        ok($link,"Expecting link of $vol") or exit;
    }
}

#########################################################################

clean();

for my $vm_name ( vm_names() ) {

my $vm;
eval { $vm = rvd_back->search_vm($vm_name) } if !$< || $vm_name eq 'Void';

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;


    test_create_pool_fail($vm);

    test_pool_dupe_linked_1($vm);
    test_pool_dupe_linked($vm);
    test_pool_dupe($vm);


    test_pool_linked($vm);
    test_pool_linked2($vm);
    test_pool_linked_reverse($vm);
    test_pool_linked2_reverse($vm);

    my ($pool_name, $pool_dir) = create_pool($vm_name);

    test_pool_info($vm);

    create_machine($vm, $pool_name, $pool_dir);

    my $domain = test_create_domain($vm_name, $pool_name);
    test_remove_domain($vm_name, $domain);
    test_default_pool($vm_name,$pool_name);

    test_volumes_in_two_pools($vm_name);

    test_base_pool($vm, $pool_name);
    test_clone_pool($vm, $pool_name);

    test_default_pool_base($vm, $pool_name);

    my ($pool_name2) = create_pool($vm_name);
    test_base_clone_pool($vm, $pool_name, $pool_name2);
    $domain->remove(user_admin);

}

}

end();

done_testing();
