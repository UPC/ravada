use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use File::Path qw(make_path);
use IPC::Run3 qw(run3);
use Mojo::JSON qw(decode_json encode_json);
use Ravada::HostDevice::Templates;
use Test::More;
use YAML qw( Dump );

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $N_DEVICE = 0;

my $PATH = "/var/tmp/$</ravada/dev";

#########################################################

sub _create_mock_devices($vm, $n_devices, $type, $value="fff:fff") {
    $vm->run_command("mkdir","-p",$PATH) if !$vm->file_exists($PATH);

    my $name = base_domain_name()."_${type} ID";

    for my $n ( 1 .. $n_devices ) {
        my $file= "$PATH/${name} $N_DEVICE$value${n} Foobar "
            .$vm->name;
        $vm->write_file($file,"fff6f017-3417-4ad3-b05e-17ae3e1a461".int(rand(10)));
    }
    $N_DEVICE ++;

    return ("find $PATH/",$name);
}

sub test_devices($vm, $node) {
    my ($list_command,$list_filter) = _create_mock_devices($vm, 3 , "USB" );
    my ($list_command2,$list_filter2) = _create_mock_devices($node, 3 , "USB" );

    my $templates = Ravada::HostDevice::Templates::list_templates($vm->type);
    my ($first) = $templates->[0];

    $vm->add_host_device(template => $first->{name});
    my @list_hostdev = $vm->list_host_devices();
    my ($hd) = $list_hostdev[-1];
    $hd->_data('list_command',$list_command);

    my $vm_name = $vm->name;
    my $node_name = $node->name;

    my @devices = $hd->list_devices;
    ok(grep /$vm_name/,@devices);
    ok(!grep /$node_name/,@devices);

    my @devices_nodes = $hd->list_devices_nodes;
    ok(grep /$vm_name/,@devices_nodes);
    ok(grep /$node_name/,@devices_nodes);

    test_assign($vm, $node, $hd);

    exit;
}

sub test_assign($vm, $node, $hd) {
    my $base = create_domain($vm);
    $base->add_host_device($hd);
    $base->prepare_base(user_admin);
    $base->set_base_vm(id_vm => $node->id, user => user_admin);
    is($node->list_host_devices,$vm->list_host_devices) or exit;

    my $base2 = create_domain($vm);
    $base2->add_host_device($hd);
    $base2->prepare_base(user_admin);
    $base2->set_base_vm(id_vm => $node->id, user => user_admin);

    my $req = Ravada::Request->clone(
            uid => user_admin->id
            ,id_domain => $base->id
            ,number => scalar($hd->list_devices_nodes)
    );
    wait_request();
    is(scalar($base->clones),scalar($hd->list_devices_nodes));
    for my $clone0 ($base->clones) {
        my $req = Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $clone0->{id}
        );
        wait_request();
        my $domain = Ravada::Domain->open($clone0->{id});
        is($domain->is_active,1);
        check_host_device($domain);
    }
}

sub check_host_device($domain) {
    if ($domain->type eq 'Void') {
        check_host_device_void($domain);
    } else {
        die "TODO";
    }
}

sub check_host_device_void($domain) {
    my $doc = $domain->_load();
    my @hostdev;
    for my $dev ( @{ $doc->{hardware}->{host_devices} } ) {
        push @hostdev,($dev);
        for my $item ( keys %$dev ) {
            like($item,qr/^\w+$/);
            like($dev->{$item}, qr(^[0-9a-z]+$)) or die Dumper($dev);
        }
    }

    is(scalar(@hostdev),1) or do {
        my $vm = Ravada::VM->open($domain->_data('id_vm'));
        die $domain->name." ".$vm->name;
    };
    warn Dumper([$domain->name,$domain->_data('id_vm'),\@hostdev]);
}

sub _clean_devices(@nodes) {
    my $base = base_domain_name();
    for my $vm (@nodes) {
        next if !defined $vm;
        $vm->run_command("mkdir","-p",$PATH) if !$vm->file_exists($PATH);
        my ($out, $err) = $vm->run_command("ls",$PATH);
        for my $line ( split /\n/,$out ) {
            next if $line !~ /$base/;
            $vm->run_command("rm","$PATH/$line");
        }
    }
}
#########################################################

init();
clean();

for my $vm_name ( 'Void' ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        my $node = remote_node($vm_name)  or next;
        clean_remote_node($node);

        _clean_devices($vm, $node);
        test_devices($vm, $node);
        _clean_devices($vm, $node);
        exit;
    }
}

end();
done_testing();
