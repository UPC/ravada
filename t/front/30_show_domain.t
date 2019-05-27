use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $CONFIG_FILE = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new(
    config => $CONFIG_FILE
    , connector => connector()
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar', 1);

my %CREATE_ARGS = (
     KVM => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
    ,LXC => { id_template => 1, id_owner => $USER->id }
    ,Void => { id_owner => $USER->id }
);

###################################################################

sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}

sub test_create_domain {
    my $vm_name = shift;

    my $name = new_domain_name();

    my $vm = $RVD_BACK->search_vm($vm_name);
    ok($vm,"Expecting VM $vm , got '".ref($vm)) or return;
    
    my $domain_b = $vm->create_domain(
        name => $name
        ,active => 0
        ,create_args($vm_name)
	,disk => 1024 * 1024
    );
    
    ok($domain_b);

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);

    my $domain_b2 = $RVD_BACK->search_domain($name);
    ok($domain_b2,"[$vm_name] expecting domain $name in backend") or exit;
    return $name;
}

sub test_start_domain { 

    my $vm_name = shift;
    my $name = shift;

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $domain_b = $vm->search_domain($name);
    ok($domain_b,"Domain $name should be in backend");

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f,"Domain $name should be in frontend");
    isa_ok($domain_f, 'Ravada::Front::Domain');

    if ($domain_b->is_active) {
        eval { $domain_b->shutdown(user => $USER)};
        ok(!$@,"[$vm_name] Start domain $name expecting error: '' , got $@");
    }

    ok(!$domain_f->is_active);

    eval { $domain_f->start($USER ) };
    ok($@,"[$vm_name] Start should be denied from front ");
    ok(!$domain_f->is_active,"[$vm_name] Domain should be active");

    if ($vm_name =~ /kvm/i ) {
        eval {
            $domain_f->domain->create();
        };
        ok($@,"[$vm_name] domain->create should be denied from front ");
    }

    eval { $domain_b->start($USER) };
    ok(!$@,$@);


    $domain_f = $RVD_FRONT->search_domain($name);
    is($domain_f->is_active,1);# && !$domain_f->is_active);

}

sub test_shutdown_domain {
    my $vm_name = shift;
    my $name = shift;

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $domain_b = $vm->search_domain($name);
    ok($domain_b,"Domain $name should be in backend");
    ok(!$domain_b->readonly,"Domain $name should not be readonly");

    my $vm2 = Ravada::VM->open( id => $vm->id);
    ok($vm2,"[$vm_name] expecting a VM") or exit;

    my $vm3 = Ravada::VM->open( id => $vm->id, readonly => 1);
    ok($vm3,"[$vm_name] expecting a VM") or exit;

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f,"Domain $name should be in frontend");
    ok($domain_f->readonly,"Domain $name should be readonly");

    eval { $domain_b->start };
#    ok(!$@,"[$vm_name] Start domain $name expecting error: '' , got $@");

    ok($domain_f->is_active);

    eval { $domain_f->shutdown( force => 1, user => user_admin) };
    ok($@,"[$vm_name] Shutdown should be denied from front ");
    ok($domain_f->is_active,"[$vm_name] Domain should be active");

    if ($vm_name =~ /kvm/i ) {
        eval {
            $domain_f->domain->shutdown();
        };
        ok($@,"[$vm_name] Shutdown should be denied from front ");
    }

    eval { $domain_b->force_shutdown($USER) };
    is($@,'');

    $domain_f = $RVD_FRONT->search_domain($name);
    is($domain_f->is_active,0);# && !$domain_f->is_active);

}

sub test_vm_ro {
    my $vm_name = shift;


    my $name = new_domain_name();

    my $vm = $RVD_FRONT->open_vm($vm_name);
    
    my $domain;
    eval { $domain = $vm->create_domain(
        name => $name
        ,active => 0
        ,create_args($vm_name)
        );
    };
    ok(!$domain,"I shouldn't create a domain in read only $vm_name");

}
##############################################################3

remove_old_domains();
remove_old_disks();

for my $vm_name (qw(Void KVM)) {
    my $vm = $RVD_BACK->search_vm($vm_name);
    if ( !$vm ) {
        diag("Skipping VM $vm_name in this system");
        next;
    }
    test_vm_ro($vm_name);
    my $dom_name = test_create_domain($vm_name);
    test_start_domain($vm_name, $dom_name);
    test_shutdown_domain($vm_name, $dom_name);
}

remove_old_domains();
remove_old_disks();

done_testing();
