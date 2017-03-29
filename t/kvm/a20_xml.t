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

my $RVD_BACK = rvd_back($test->connector);
my $RVD_FRONT= rvd_front($test->connector);

my %ARG_CREATE_DOM = (
      kvm => [ id_iso => 1 ]
);
my @VMS = reverse keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");

sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    ok($ARG_CREATE_DOM{lc($vm_name)}) or do {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    };
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
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


#########################################################################

clean();

my $vm_name = 'kvm';
my $vm = rvd_back->search_vm($vm_name);

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    my $domain = test_create_domain($vm_name);
    my $clone = $domain->clone(user => $USER, name => new_domain_name());

    ok($clone);
    my @volumes = $clone->list_volumes();
    is(scalar @volumes,1);

    $domain->add_volume( name => 'vdb' , size => 1000 *1024);

    my @volumes_domain = $domain->list_volumes();
    is(scalar @volumes_domain, 2);

    my $clone2;
    eval  { $clone2 = $domain->clone(user => $USER, name => new_domain_name()) };
    is($@,'');
    ok($clone2,"Expecting a clone , got ".($clone2 or 'UNDEF'));

    if ($clone2) {
        my @volumes_clone2= $clone2->list_volumes();
        is(scalar @volumes_clone2, 1);
    }

    $clone->remove($USER);
    $clone2->remove($USER);
    $domain->remove_base($USER);

    my $clone3;
    eval  { $clone3 = $domain->clone(user => $USER, name => new_domain_name()) };
    is($@,'');
    ok($clone3,"Expecting a clone , got ".($clone3 or 'UNDEF'));

    if ($clone3) {
        my @volumes_clone3= $clone3->list_volumes();
        is(scalar @volumes_clone3, 2);
    }


}

clean();

done_testing();

