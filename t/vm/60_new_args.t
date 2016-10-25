use warnings;
use strict;

use Data::Dumper;
use JSON::XS;
use YAML qw(LoadFile);
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

my %TEST_DISK = (
    Void => \&test_disk_void
    ,KVM => \&test_disk_kvm
);

rvd_back($test->connector, $FILE_CONFIG);

my $USER = create_user("foo","bar");

#######################################################################

sub test_create_domain {
    my $vm_name = shift;

    my ($mem, $disk) = @_;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    if (!$ARG_CREATE_DOM{$vm_name}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , memory => $mem
                    , disk => $disk
                    , @{$ARG_CREATE_DOM{$vm_name}})
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );


    return $domain;
}

sub test_memory {
    my ($vm_name, $domain, $memory) = @_;

    $domain->start($USER);

    my $info2 = $domain->get_info();
    my $memory2 = $info2->{memory};
            ok($memory2 == $memory,"[$vm_name] Expecting memory: '$memory' "
                                        ." , got $memory2 ");
}

sub test_disk {
    my ($vm_name, $domain, $size_exp) = @_;

    my ($disk) = $domain->list_volumes();

    my $du = `du -bs $disk`;
    chomp $du;
    my ($size) = $du =~ m{(\d+)};

    ok($size,"Expecting size for volume $disk") or return;

    my $sub_test_disk = $TEST_DISK{$vm_name};
    ok($sub_test_disk,"Expecting a test for disks of type $vm_name") or return;

    $sub_test_disk->($vm_name, $disk, $size_exp);

}

sub test_disk_void {
    my ($vm_name, $disk, $size_exp) = @_;
    my $data = LoadFile($disk);
    my $size;
    for my $dev_name (keys %{$data->{device}}) {
        my $dev = $data->{device}->{$dev_name};
        $size = $dev->{size} if $dev->{path} eq $disk;
        last if $size;
    }
    ok($size,"Expected size in ->{device}->{$disk}->{size}") or return;
    ok($size == $size_exp, "Expecting size '$size_exp' , got '$size'");
}

sub test_disk_kvm {
    my ($vm_name, $disk, $size_exp) = @_;

    open my $volinfo,'-|',"virsh vol-dumpxml $disk" or die $!;
    my ($xml) = join('',<$volinfo>);
    close $volinfo;

    my $doc = XML::LibXML->load_xml(string => $xml);
    
    my ($size) = $doc->findnodes('/volume/capacity/text()')->[0]->getData();
    ok($size == $size_exp, "Expecting size '$size_exp' , got '$size'");


}

#######################################################################

remove_old_domains();
remove_old_disks();
$Data::Dumper::Sortkeys = 1;

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

    my $ravada;
    eval { $ravada = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $ravada->search_vm($vm_name) } if $ravada;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        my ($memory , $disk ) = (111*1024 , 3*1024*1024);
        my $domain = test_create_domain($vm_name, $memory, $disk);

        test_memory($vm_name, $domain, $memory);
        
        test_disk($vm_name, $domain, $disk);
    };
}

remove_old_domains();
remove_old_disks();

done_testing();

