use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
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


#########################################################################

if ($>)  {
    diag("SKIPPED: Test must run as root");
    done_testing();
    exit;
}

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    my $domain = test_create_domain($vm_name);
    $domain->is_public(1);
    my $clone = $domain->clone(user => user_admin , name => new_domain_name());

    ok($clone);
    my @volumes = $clone->list_volumes();
    is(scalar @volumes,1);

    $domain->add_volume( name => $domain->name.'.vdb' , size => 1000 *1024);

    my @volumes_domain = $domain->list_volumes();
    is(scalar @volumes_domain, 3);

    my $clone2;
    eval  { $clone2 = $domain->clone(user => $USER, name => new_domain_name()) };
    is($@,'');
    ok($clone2,"Expecting a clone , got ".($clone2 or 'UNDEF'));

    if ($clone2) {
        my @volumes_clone2= $clone2->list_volumes();
        is(scalar @volumes_clone2, 1);
    }

    $clone->remove( user_admin );
    $clone2->remove( user_admin );
    $domain->remove_base( user_admin );

    my $clone3;
    eval  { $clone3 = $domain->clone(user => user_admin , name => new_domain_name()) };
    is($@,'');
    ok($clone3,"Expecting a clone , got ".($clone3 or 'UNDEF'));

    if ($clone3) {
        my @volumes_clone3= $clone3->list_volumes();
        is(scalar @volumes_clone3, 2);
    }


}

end();

done_testing();

