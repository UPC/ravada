use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
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

sub create_pool {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name) or return;


    my $capacity = 1 * 1024 * 1024;

    my $pool_name = new_pool_name();
    my $dir = "/var/tmp/$pool_name";

    mkdir $dir if ! -e $dir;

    my $pool;
    for ( ;; ) {
        my $uuid = Ravada::VM::KVM::_new_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');
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

    return $pool_name;
}

sub test_create_domain {
    my $vm_name = shift;
    my $pool_name = shift or confess "Missing pool_name";

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;
    $vm->default_storage_pool_name($pool_name);
    is($vm->default_storage_pool_name($pool_name), $pool_name) or exit;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
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
    is($@,'',"Prepare base") or exit;

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

    my $pool_name1 = create_pool($vm_name);
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
        default => '/var/lib/libvirt'
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
        default => '/var/lib/libvirt'
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
        default => '/var/lib/libvirt'
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
        default => '/var/lib/libvirt'
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

#
#########################################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    my $pool_name = create_pool($vm_name);

    my $domain = test_create_domain($vm_name, $pool_name);
    test_remove_domain($vm_name, $domain);
    test_default_pool($vm_name,$pool_name);

    test_volumes_in_two_pools($vm_name);

    test_base_pool($vm, $pool_name);
    test_clone_pool($vm, $pool_name);

    test_default_pool_base($vm, $pool_name);

    my $pool_name2 = create_pool($vm_name);
    test_base_clone_pool($vm, $pool_name, $pool_name2);
    $domain->remove(user_admin);

}

clean();

done_testing();
