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

my $USER;

init($test->connector, $FILE_CONFIG);

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


sub test_create_fail {
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
    ok($@,"Expecting error , got ''");

    ok(!$domain,"Expecting doesn't exists domain '$name'");

    my $domain2 = rvd_front()->search_domain($name);
    ok(!$domain,"Expecting doesn't exists domain '$name'");

}

sub test_req_create_domain{
    my $vm_name = shift;
    my ($mem, $disk) = @_;

    my $name = new_domain_name();

    my $req;
    {
        my $rvd_front = rvd_front();
        $req = $rvd_front->create_domain( name => $name
                    , id_owner => $USER->id
                    , memory => $mem
                    , disk => $disk
                    , vm => $vm_name
                    , @{$ARG_CREATE_DOM{$vm_name}}
        );
   
    }
    ok($req,"Expecting request to create_domain");

    rvd_back()->process_requests();

    wait_request($req);
    ok($req->status('done'),"Expecting status='done' , got ".$req->status);
    ok(!$req->error,"Expecting error '' , got '".($req->error or '')."'");

    my $domain = rvd_front()->search_domain($name);
    ok($domain,"Expecting domain '$name' , found : ".(defined $domain or 0));

    return $domain;
}

sub test_req_create_fail {
    my $vm_name = shift;
    my ($mem, $disk) = @_;

    my $name = new_domain_name();

    my $req;
    {
        my $rvd_front = rvd_front();
        $req = $rvd_front->create_domain( name => $name
                    , id_owner => $USER->id
                    , memory => $mem
                    , disk => $disk
                    , vm => $vm_name
                    , @{$ARG_CREATE_DOM{$vm_name}}
        );
   
        ok($req,"Expecting request to create_domain");
    }
    rvd_back->process_requests();

    wait_request($req);
    ok($req->status('done'),"Expecting status='done' , got ".$req->status);
    ok($req->error,"Expecting error , got '".($req->error or '')."'");

    my $domain = rvd_back->search_domain($name);
    ok(!$domain,"Expecting domain doesn't exist domain '$name'");

}

sub test_memory {
    my ($vm_name, $domain, $memory , $msg) = @_;
    $msg = "" if !$msg;
    $msg = "-$msg" if $msg;

    my $info2 = $domain->get_info();
    my $memory2 = $info2->{memory};
    ok($memory2 == $memory,"[$vm_name$msg] Expecting memory: '$memory' "
                                        ." , got $memory2 ") or exit;
}

sub test_disk {
    my ($vm_name, $domain, $size_exp, $msg) = @_;

    $msg = "" if !$msg;
    $msg = "-$msg" if $msg;

    my ($disk) = $domain->list_volumes();

    my $du = `du -bs $disk`;
    chomp $du;
    my ($size) = $du =~ m{(\d+)};

    ok($size,"Expecting size for volume $disk") or return;

    my $sub_test_disk = $TEST_DISK{$vm_name};
    ok($sub_test_disk,"[$vm_name$msg] Expecting a test for disks of type $vm_name") or return;

    $sub_test_disk->($vm_name, $disk, $size_exp);

}

sub test_disk_void {
    my ($vm_name, $disk, $size_exp) = @_;
    my $data;
    my $size = -s $disk;
    ok($size,"Expected size in ->{device}->{$disk}->{size}") or return;
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

sub test_args {
    my $vm_name = shift;

    my ($memory , $disk ) = (512 * 1024 , 3*1024*1024);

    {
        my $domain = test_create_domain($vm_name, $memory, $disk,"Direct");
        test_memory($vm_name, $domain, $memory, 'Direct');
        test_disk($vm_name, $domain, $disk,'Direct');
    }
    {
        my $domain = test_req_create_domain($vm_name, $memory, $disk, "Request");
        test_memory($vm_name, $domain, $memory, "Request") if $domain;
        test_disk($vm_name, $domain, $disk)     if $domain;
    }
}

sub test_small {
    my $vm_name = shift;

    my ($memory, $disk) = ( 2 , 1*1024*1024+1 );

    # fail memory
    test_create_fail($vm_name, 1 , 2*1024*1024 ,"Direct");

    # fails disk
    test_create_fail($vm_name, 512 * 1024, 1,"Direct");

    # fail memory req
    test_req_create_fail($vm_name, 1 , 2*1024*1024 ,"Direct");

    # fails disk req
    test_req_create_fail($vm_name, 512 * 1024, 1,"Direct");

}

#######################################################################

remove_old_domains();
remove_old_disks();
$Data::Dumper::Sortkeys = 1;

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

    my $vm_ok;
    eval {
        my $ravada = Ravada->new(@ARG_RVD);
        $USER = create_user("foo","bar")    if !$USER;

        my $vm = $ravada->search_vm($vm_name)  if $ravada;

        $vm_ok = 1 if $vm;
    };
    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm_ok && $vm_name =~/kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm_ok = undef;
        }

        diag($msg)      if !$vm_ok;
        skip $msg,10    if !$vm_ok;
        test_args($vm_name);
        test_small($vm_name);
    };
}

remove_old_domains();
remove_old_disks();

done_testing();

