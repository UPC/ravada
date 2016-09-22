use warnings;
use strict;

use Data::Dumper;
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

##########################################################

sub test_vm_connect {
    my $vm_name = shift;

    my $class = "Ravada::VM::$vm_name";
    my $obj = {};

    bless $obj,$class;

    my $vm = $obj->new();
    ok($vm);
    ok($vm->host eq 'localhost');
}

sub test_search_vm {
    my $vm_name = shift;

    return if $vm_name eq 'Void';

    my $class = "Ravada::VM::$vm_name";

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find a $vm virtual manager");
    ok(ref $vm eq $class,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $class");
}

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

sub test_manage_domain {
    my $domain = shift;

    my $display;
    eval { $display = $domain->display($USER) };
    ok($display,"No display for ".$domain->name." $@");
}

sub test_remove_domain {
    my $domain = shift;
    eval { $domain->remove };
    ok(!$@ , "Error removing domain ".$domain->name." ".ref($domain).": $@") or exit;

}

#######################################################

remove_old_domains();

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS);

    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_vm_connect($vm_name);
        test_search_vm($vm_name);
        my $domain = test_create_domain($vm_name);
        test_manage_domain($domain);
        test_remove_domain($domain);
    };
}
done_testing();
