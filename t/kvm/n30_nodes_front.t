use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

init($test->connector);

clean();
clean_remote();

my $REMOTE_CONFIG;
#############################################################

sub create_node {
    my $vm_name = shift;

    die "Error: missing host in remote config\n ".Dumper($REMOTE_CONFIG)
        if !$REMOTE_CONFIG->{host};

    my $vm = rvd_back->search_vm($vm_name);

    my $node;
    my @list_nodes0 = rvd_front->list_vms;

    eval { $node = $vm->new(%{$REMOTE_CONFIG}) };

    shutdown_node($node)   if $node->ping && !$node->_connect_rex();
    start_node($node);

    clean_remote_node($node);

    return $node;
}

sub test_list_vms($vm_name) {

    my $vm = rvd_back->search_vm($vm_name);

    my $list_domains = rvd_front->list_domains();
    my @list_domains_b = $vm->list_domains();

    my $domain = create_domain($vm_name);

    my @list_domains2_b = $vm->list_domains();
    is(scalar @list_domains_b+1, scalar @list_domains2_b);

    my @list_domains_active2_b = $vm->list_domains( active => 1);
    is(scalar ($vm->list_domains(active => 1)), 0);

    my $list_domains2 = rvd_front->list_domains();

    is(scalar @$list_domains2, scalar @$list_domains +1
        , Dumper($list_domains2, $list_domains) );

    is($list_domains2->[0]->{name}, $domain->name);
    is($list_domains2->[0]->{is_active}, 0);

    my $ip = '1.2.3.4';
    $domain->start( user => user_admin, remote_ip => $ip );
    is($domain->remote_ip, $ip);

    is(scalar ($vm->list_domains(active => 1)), 1) ;

    my $list_domains3 = rvd_front->list_domains();
    is($list_domains3->[0]->{is_active}, 1);
    is($list_domains3->[0]->{remote_ip}, $ip);

    $domain->remove(user_admin());
}

sub test_list_vms_refresh($vm_name) {

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = create_domain($vm_name);

    start_domain_internal($domain);
    my $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active},0);

    rvd_back->_cmd_refresh_vms();
    is(rvd_front->list_domains()->[0]->{is_active},1);

    shutdown_domain_internal($domain);
    is(rvd_front->list_domains()->[0]->{is_active},1);

    rvd_back->_cmd_refresh_vms();
    is(rvd_front->list_domains()->[0]->{is_active},0);

    $domain->remove(user_admin());
}

#############################################################

for my $vm_name ('KVM' , 'Void' ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');
        $REMOTE_CONFIG = remote_config($vm_name);
        if (!keys %$REMOTE_CONFIG) {
            my $msg = "skipped, missing the remote configuration for $vm_name in the file "
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

        diag("Testing remote node in $vm_name");
#        my $node = create_node($vm_name);
        test_list_vms($vm_name);
        test_list_vms_refresh($vm_name);
#        remove_node($node);
    }
}

#################################################################

clean();
clean_remote();

done_testing();
