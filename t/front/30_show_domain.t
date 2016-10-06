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
    
    my $domain_b = $vm->create_domain(
        name => $name
        ,active => 0
        ,create_args($vm_name)
    );
    
    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);
    ok(exists $domain_f->{is_active});

    eval { $domain_b->shutdown };
    ok(!$@,$@);

    $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);
    ok(exists $domain_f->{is_active} && !$domain_f->{is_active});

    $domain_b->start;
    $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f);
    ok(exists $domain_f->{is_active} && $domain_f->{is_active});

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
    test_vm_ro($vm_name);
    test_create_domain($vm_name);
}

remove_old_domains();
remove_old_disks();

done_testing();
