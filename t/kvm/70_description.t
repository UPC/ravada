use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

init();
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

our $TIMEOUT_SHUTDOWN = 10;

################################################################
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

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub add_description {
    my $domain = shift;
    my $description = shift;
    my $name = $domain->name;

    $domain->description($description);
}

sub test_description {
    my $vm_name = shift;

#    diag("Testing add description $vm_name");
    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    my $description = "This is a description test";
    add_description($domain, $description);

    my $domain2 = rvd_back->search_domain($domain->name);
    ok ($domain2->description eq $description, "I can't find description");
}
#######################################################

#######################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);
my $description = 'This is a description test';

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }
    skip($msg,10)   if !$vm;

    test_description($vm_name);
}

end();
done_testing();
