use warnings;
use strict;

use Data::Dumper;
use JSON::XS;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

init($test->connector, $FILE_CONFIG);

my $USER = create_user("foo","bar");

#######################################################################

sub test_create_domain {
    my $vm_name = shift;
    my $name = ( shift or new_domain_name());

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"Expecting VM $vm_name") or return;


    if (!$ARG_CREATE_DOM{$vm_name}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    diag("[$vm_name] creating domain $name");
    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}})
    };

    ok($domain,"[$vm_name] Expecting VM $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );


    return $domain->name;
}

sub test_rename_domain {
    my ($vm_name, $domain_name) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    ok($domain,"[$vm_name] Expecting found $domain_name") or return;

    my $new_domain_name = new_domain_name();
    $domain->rename(name => $new_domain_name, user => $USER);

    my $domain0 = $vm->search_domain($domain_name);
    ok(!$domain0,"[$vm_name] Expecting not found $domain_name");

    my $domain1 = $vm->search_domain($new_domain_name);
    ok($domain1,"[$vm_name] Expecting renamed domain $new_domain_name") or return;

}

sub test_req_rename_domain {
    my ($vm_name, $domain_name) = @_;

    my $domain_id;
    {
        my $vm = rvd_back->search_vm($vm_name);
        my $domain = $vm->search_domain($domain_name);
        ok($domain,"[$vm_name-req] Expecting found $domain_name") or return;
        $domain_id = $domain->id;
    }
    my $new_domain_name = new_domain_name();
    my $req = Ravada::Request->rename_domain(
              uid => $USER->id,
             name => $new_domain_name,
        id_domain => $domain_id,
    );
    ok($req);
    rvd_back()->process_requests();
    wait_request($req);
    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$domain_name)
        or return;

    my $vm = rvd_back->search_vm($vm_name);

    my $domain0 = $vm->search_domain($domain_name);
    ok(!$domain0,"[$vm_name-req] Expecting not found $domain_name");

    my $domain1 = $vm->search_domain($new_domain_name);
    ok($domain1,"[$vm_name-req] Expecting renamed domain $new_domain_name") or return;
}


#######################################################################

remove_old_domains();
remove_old_disks();

for my $vm_name (qw( Void KVM )) {

    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

    my $ravada;
    eval { $ravada = Ravada->new(@ARG_RVD) };

    my $vm_ok;

    eval { my 
        $vm = $ravada->search_vm($vm_name);
        $vm_ok = 1 if $vm;
    } if $ravada;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm_ok;
        skip $msg,10    if !$vm_ok;

        my $domain_name = test_create_domain($vm_name);
        test_rename_domain($vm_name, $domain_name);
        test_create_domain($vm_name, $domain_name);

        $domain_name = test_create_domain($vm_name);
        test_req_rename_domain($vm_name, $domain_name) or next;
        test_create_domain($vm_name, $domain_name);
        
    };
}

remove_old_domains();
remove_old_disks();

done_testing();

