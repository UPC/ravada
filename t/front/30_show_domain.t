use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $CONFIG_FILE = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($test->connector , $CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new(
    config => $CONFIG_FILE
    , connector => $test->connector
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar');

my %CREATE_ARGS = (
     KVM => { id_iso => 1,       id_owner => $USER->id }
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
    );
    
    ok($domain_b);

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);

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

    ok($domain_f->is_active);# && !$domain_f->is_active);

}

sub test_shutdown_domain {
    my $vm_name = shift;
    my $name = shift;

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $domain_b = $vm->search_domain($name);
    ok($domain_b,"Domain $name should be in backend");
    ok(!$domain_b->readonly,"Domain $name should not be readonly");

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f,"Domain $name should be in frontend");
    ok($domain_f->readonly,"Domain $name should be readonly");

    eval { $domain_b->start };
#    ok(!$@,"[$vm_name] Start domain $name expecting error: '' , got $@");

    ok($domain_f->is_active);

    eval { $domain_f->shutdown( force => 1) };
    ok($@,"[$vm_name] Shutdown should be denied from front ");
    ok($domain_f->is_active,"[$vm_name] Domain should be active");

    if ($vm_name =~ /kvm/i ) {
        eval {
            $domain_f->domain->shutdown();
        };
        ok($@,"[$vm_name] Shutdown should be denied from front ");
    }

    eval { $domain_b->shutdown(user => $USER,force => 1) };
    ok(!$@,$@);

    ok(!$domain_f->is_active);# && !$domain_f->is_active);

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
