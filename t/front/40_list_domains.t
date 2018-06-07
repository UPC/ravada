use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG);
my $RVD_FRONT= rvd_front($test->connector, $FILE_CONFIG);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

#########################################################

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

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

    return $domain;
}

sub test_list_domains {
    my $vm_name = shift;
    my $domain = shift;

    my $list_domains = rvd_front->list_domains();
    is(scalar@$list_domains,1,Dumper($list_domains));

    is($list_domains->[0]->{remote_ip},undef);

    $domain->start($USER);
    ok($domain->is_active,"Domain should be active, got ".$domain->is_active);
    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{remote_ip},undef);
    is($list_domains->[0]->{is_active}, 1 );

    shutdown_domain_internal($domain);
    ok(!$domain->is_active,"Domain should not be active, got ".$domain->is_active);

    rvd_back->_cmd_refresh_vms();
    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active}, 0, );

    my $remote_ip = '99.88.77.66';
    $domain->start(user => $USER, remote_ip => $remote_ip);
    ok($domain->is_active,"Domain should be active, got ".$domain->is_active);
    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{remote_ip}, $remote_ip);
    is($list_domains->[0]->{is_active}, 1);
    is($list_domains->[0]->{is_hibernated}, 0);

    $domain->hibernate($USER);
    is($domain->is_hibernated, 1);
    is($domain->status, 'hibernated');

    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active}, 0);
    is($list_domains->[0]->{is_hibernated}, 1);
    is($list_domains->[0]->{status}, 'hibernated');

    rvd_back->_cmd_refresh_vms();

    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active}, 0);
    is($list_domains->[0]->{is_hibernated}, 1);
    is($list_domains->[0]->{status}, 'hibernated');
}

sub test_list_bases {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $user2 = create_user('malcolm.reynolds','serenity');

    my $base = create_domain($vm_name);
    my $list = rvd_front->list_machines_user($user2);
    is(scalar @$list, 0);

    $base->prepare_base(user_admin);

    $list = rvd_front->list_machines_user($user2);
    is(scalar @$list, 0);

    $list = rvd_front->list_machines_user(user_admin);
    is(scalar @$list, 1);

    $base->remove(user_admin);
    $user2->remove();
}
#########################################################

remove_old_domains();
remove_old_disks();


for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";


    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok($CLASS);

        my $domain = test_create_domain($vm_name);
        test_list_domains($vm_name, $domain);

        test_list_bases($vm_name);
        $domain->remove($USER);

    }
}

remove_old_domains();
remove_old_disks();

done_testing();

