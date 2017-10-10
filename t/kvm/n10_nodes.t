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
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

my $REMOTE_CONFIG;
##########################################################

sub test_node {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $node;
    eval { $node = $vm->new(%{$REMOTE_CONFIG}) };
    ok(!$@,"Expecting no error connecting to $vm_name at ".Dumper($REMOTE_CONFIG).", got :'"
        .($@ or '')."'");
    ok($node) or return;

    is($node->host,$REMOTE_CONFIG->{host});
    like($node->name ,qr($REMOTE_CONFIG->{host}));
    ok($node->vm,"[$vm_name]");

    return $node;
}

sub test_sync {
    my ($vm_name, $node, $clone) = @_;

    $clone->rsync($node);
    # TODO test synced files

}

sub test_domain {
    my $vm_name = shift;
    my $node = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $base = create_domain($vm_name);
    is($base->_vm->host, 'localhost');

    $base->prepare_base(user_admin);

    my $clone = $base->clone(name => new_domain_name
        ,user => user_admin
    );

    test_sync($vm_name, $node, $clone);

    $clone->migrate($node);

    eval { $clone->start(user_admin) };
    ok(!$@,"[$vm_name] Expecting no error, got ".($@ or ''));
    is($clone->is_active,1);

    my $ip = $node->ip;
    like($clone->display(user_admin),qr($ip));
    return $clone;
}
clean();

for my $vm_name ('Void','KVM') {
my $vm;
eval { $vm = rvd_back->search_vm($vm_name) };

SKIP: {

    my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
    $REMOTE_CONFIG = remote_config($vm_name);
    if (!keys %$REMOTE_CONFIG) {
        my $msg = "skipped, missing the remote configuration in the file "
            .$Test::Ravada::FILE_CONFIG_REMOTE;
        diag($msg);
        skip($msg,10);
    }

    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip($msg,10)   if !$vm;

    my $node = test_node($vm_name);
    test_domain($vm_name, $node);

}

}

clean();

done_testing();
