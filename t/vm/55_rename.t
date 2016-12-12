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

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    if (!$ARG_CREATE_DOM{$vm_name}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
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


    return $domain->name;
}

sub test_rename_domain {
    my ($vm_name, $domain_name) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    ok($domain,"Expecting found $domain_name") or return;

    my $new_domain_name = new_domain_name();
    $domain->rename($new_domain_name);

    my $domain0 = $vm->search_domain($domain_name);
    ok(!$domain0,"Expecting not found $domain_name");

    my $domain1 = $vm->search_domain($new_domain_name);
    ok($domain1,"Expecting found $new_domain_name");

}

sub test_req_rename_domain {
    my ($vm_name, $domain_name) = @_;
}


#######################################################################

remove_old_domains();
remove_old_disks();

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
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
        test_req_rename_domain($vm_name, $domain_name);
        
    };
}

remove_old_domains();
remove_old_disks();

done_testing();

