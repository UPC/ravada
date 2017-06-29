use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $RVD_BACK = rvd_back($test->connector);
my $RVD_FRONT= rvd_front($test->connector);

my %ARG_CREATE_DOM = (
      kvm => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");

#########################################################################

sub create_pool {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name) or return;

    my $uuid = Ravada::VM::KVM::_new_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');

    my $capacity = 1 * 1024 * 1024;

    my $pool_name = new_pool_name();
    my $dir = "/var/tmp/$pool_name";
    mkdir $dir if ! -e $dir;

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
    my $pool;
    eval { $pool = $vm->vm->create_storage_pool($xml) };
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

    ok($ARG_CREATE_DOM{lc($vm_name)}) or do {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    };
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}})
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    for my $volume ( $domain->list_volumes ) {
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
        ok(!-e $file,"Expecting no volume $file exists, got : ".(-e $file or 0));
    }

}

sub test_base {
    my $domain = shift;
    eval { $domain->prepare_base($USER) };
    is($@,'',"Prepare base") or exit;

    my @files_base = $domain->list_files_base();
    is(scalar @files_base, 2);
    for my $file (@files_base) {
        ok(-e $file,"Expecting volume $file exists, got : ".(-e $file or 0));
    }

    my ($path0) = $files_base[0] =~ m{(.*)/};
    my ($path1) = $files_base[1] =~ m{(.*)/};

    isnt($path0,$path1);

    $domain->remove_base($USER);

    for my $file (@files_base) {
        ok(!-e $file,"Expecting volume $file doesn't exist, got : ".(-e $file or 0));
    }

}

sub test_volumes_in_two_pools {
    my $vm_name = shift;

    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $pool_name1 = create_pool($vm_name);
    $vm->default_storage_pool_name($pool_name1);
    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}})
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    my $pool_name2 = create_pool($vm_name);
    $vm->default_storage_pool_name($pool_name2);

    $domain->add_volume(name => 'volb' , size => 1024*1024 );

    my @volumes = $domain->list_volumes();
    is(scalar @volumes , 2);
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

#########################################################################

clean();

my $vm_name = 'kvm';
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
}

clean();

done_testing();
