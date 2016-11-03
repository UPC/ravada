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

rvd_back($test->connector, $FILE_CONFIG);

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


    return $domain;
}

sub test_memory {
    my ($vm_name,$domain) = @_;
    $domain->start($USER) if !$domain->is_active;

    my $exp_memory =  10000;
    $domain->set_memory($exp_memory);
    my $memory2;
    for ( 0 .. 5 ) {
                my $info2 = $domain->get_info();
                $memory2 = $info2->{memory};
                last if $memory2 == $exp_memory;
                sleep 2;
    }
    SKIP: {
        skip("possible virt bug",1) if $vm_name =~ /kvm/i;
        ok($memory2 == $exp_memory,"[$vm_name] Expecting memory: '$exp_memory' "
                                        ." , got $memory2 ") ;
    }
        
}


#######################################################################

remove_old_domains();
remove_old_disks();
$Data::Dumper::Sortkeys = 1;

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

    my $ravada;
    eval { $ravada = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $ravada->search_vm($vm_name) } if $ravada;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        my $domain = test_create_domain($vm_name);
        $domain->start($USER);
        my $info = $domain->get_info();
        ok($info,"[$vm_name] Expecting info from domain ".$domain->name." , got ".Dumper($info));
        my $memory = $info->{memory};
        ok($memory,"[$vm_name] Expecting memory from info, got '$memory'");

        my $max_mem= $info->{max_mem};
        ok($max_mem,"[$vm_name] Expecting max_mem from info, got '$max_mem'");

        test_memory($vm_name, $domain);
  
        {
            $domain->shutdown(user => $USER, timeout => 1);
            my $exp_mem= int($max_mem / 2);
            $domain->set_max_mem($exp_mem);

            my $info2 = $domain->get_info();
            my $memory2 = $info2->{max_mem};

            ok($memory2 == $exp_mem,"[$vm_name] Expecting memory: '$exp_mem' "
                                        ." , got $memory2 ".Dumper($info2)) ;
        
        }

        
    };
}

remove_old_domains();
remove_old_disks();

done_testing();

