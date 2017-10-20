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

init($test->connector);
my $USER = create_user("foo","bar");

my $file_remote_config = "t/etc/remote_vm_2.conf";

#################################################################
sub test_node {
    my $vm_name = shift;
    my $config = shift;

    die "Error: missing host in remote config\n ".Dumper($config)
        if !$config->{host};

    my $vm = rvd_back->search_vm($vm_name);

    my $node;
    eval { $node = $vm->new(%{$config}) };
    ok(!$@,"Expecting no error connecting to $vm_name at ".Dumper($config).", got :'"
        .($@ or '')."'");
    ok($node) or return;

    is($node->host,$config->{host});
    like($node->name ,qr($config->{host}));
    ok($node->vm,"[$vm_name] Expecting a VM in node");

    ok($node->id) or exit;

    my $node2 = Ravada::VM->open($node->id);
    is($node2->id, $node->id);
    is($node2->name, $node->name);
    is($node2->public_ip, $node->public_ip);
    return $node;
}

#################################################################

clean($file_remote_config);

for my $vm_name ('KVM') {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        my $config;
        $config = remote_config_nodes($file_remote_config)
            if -e $file_remote_config;
        if (!keys %$config) {
            my $msg = "skipped, missing the remote configuration for $vm_name in the file "
                        .$file_remote_config;
            diag($msg);
            skip($msg,10);
        }

        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        my $fail = 0;
        for my $name (keys %$config) {
            warn $name;
            my $node = test_node($vm_name, $config->{$name});
            ok($node,"Expecting node $name created");
            ok($node->vm,"Expecting node $name has vm") if $node;
            $fail++ if !$node || !$node->vm;
        }
        skip("ERROR: $fail nodes failed",6) if $fail;
    }
}

clean($file_remote_config);
done_testing();
