use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Digest::MD5;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

$Ravada::Domain::MIN_FREE_MEMORY = 256 * 1024;

init();

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
    warn $@ if $@;

    return if !$node;

    shutdown_node($node)   if $node->ping && !$node->is_active();
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

    my ($front_domain) = grep { $_->{name} eq $domain->name } @$list_domains2;
    is($front_domain->{name}, $domain->name);
    is($front_domain->{is_active}, 0);

    my $ip = '1.2.3.4';
    $domain->start( user => user_admin, remote_ip => $ip );
    is($domain->remote_ip, $ip);

    my ($back_domain ) = grep {$_->name eq $domain->name } $vm->list_domains(active => 1);
    ok($back_domain,"Expecting ".$domain->name." in list active") ;
    is($back_domain->name, $domain->name)   if $back_domain;

    my $list_domains3 = rvd_front->list_domains();
    my ($front_domain3) = grep { $_->{name} eq $domain->name } @$list_domains3;
    is($front_domain3->{is_active}, 1);
    is($front_domain3->{remote_ip}, $ip);

    $domain->remove(user_admin());
}

sub test_list_vms_refresh($vm_name) {

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

    my ($front_domain2) = grep { $_->{name} eq $domain->name } @$list_domains2;
    is($front_domain2->{name}, $domain->name);
    is($front_domain2->{is_active}, 0);

    my $ip = '1.2.3.4';
    $domain->start( user => user_admin, remote_ip => $ip );
    is($domain->remote_ip, $ip);

    my ($back_domain) = grep { $_->name eq $domain->name } $vm->list_domains(active => 1);
    is($back_domain->name, $domain->name);
    is($back_domain->is_active, 1);

    my $list_domains3 = rvd_front->list_domains();
    my ($front_domain3) = grep { $_->{name} eq $domain->name } @$list_domains3;
    is($front_domain3->{name}, $domain->name);
    is($front_domain3->{is_active}, 1) or exit;
    is($front_domain3->{remote_ip}, $ip);

    $domain->remove(user_admin());
}


sub test_list_remote($node, $migrate=0) {

    my $vm = rvd_back->search_vm($node->type);

    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->set_base_vm(vm => $node, user => user_admin);
    my $domain = $base->clone(name => new_domain_name, user => user_admin);

    $domain->migrate($node);
    is($domain->_vm->host, $node->host);

    if (!$migrate) {
        $domain->_set_vm($vm,1);
        is($domain->_vm->host, $vm->host);
    }

    start_domain_internal($domain);
    if ($migrate) {
        is($domain->_vm->host, $node->host);
    } else {
        is($domain->_vm->host, $vm->host);
    }

    my $list_domains = rvd_front->list_domains();

    my ($front_domain) = grep { $_->{name} eq $domain->name} @$list_domains;

    is($front_domain->{name}, $domain->name) or exit;
    is($front_domain->{is_active},0);

    if ($migrate) {
        is($front_domain->{node}, $node->name);
    } else {
        is($front_domain->{node}, $vm->name);
    }

    rvd_back->_cmd_refresh_vms();
    $list_domains = rvd_front->list_domains();
    ($front_domain) = grep { $_->{name} eq $domain->name} @$list_domains;
    is($front_domain->{is_active},1, $domain->id." ".$domain->name."\n".Dumper($front_domain))
            or exit;

    shutdown_domain_internal($domain);
    $list_domains = rvd_front->list_domains();
    ($front_domain) = grep { $_->{name} eq $domain->name} @$list_domains;

    is($front_domain->{is_active},1);

    rvd_back->_cmd_refresh_vms();
    $list_domains = rvd_front->list_domains();
    ($front_domain) = grep { $_->{name} eq $domain->name} @$list_domains;
    is($front_domain->{is_active},0);

    $domain->remove(user_admin());
    $base->remove(user_admin());
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

        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing remote node in $vm_name");
        test_list_vms($vm_name);
        test_list_vms_refresh($vm_name);

        my $node = create_node($vm_name);
        test_list_remote($node);
        test_list_remote($node, 'migrate' );
        remove_node($node);
    }
}

#################################################################

clean();
clean_remote();

done_testing();
