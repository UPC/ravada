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

    $domain->start($USER) if !$domain->is_active();
    ok(!$domain->is_locked,"Domain ".$domain->name." should not be locked");

    my $display;
    eval { $display = $domain->display($USER) };
    ok($display,"No display for ".$domain->name." $@");
}

sub test_pause_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    my $display;
    eval { $domain->pause($USER) };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->resume($USER) };
    ok(!$@,"[$vm_name] Resuming domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

}


sub test_remove_domain {
    my $domain = shift;
    diag("Removing domain ".$domain->name);
    my $domain0 = rvd_back()->search_domain($domain->name);
    ok($domain0, "Domain ".$domain->name." should be there in ".ref $domain);


    eval { $domain->remove($USER) };
    ok(!$@ , "Error removing domain ".$domain->name." ".ref($domain).": $@") or exit;

    my $domain2 = rvd_back()->search_domain($domain->name);
    ok(!$domain2, "Domain ".$domain->name." should be removed in ".ref $domain);

}

sub test_search_domain {
    my $domain = shift;
    my $domain0 = rvd_back()->search_domain($domain->name);
    ok($domain0, "Domain ".$domain->name." should be there in ".ref $domain);
};

sub test_json {
    my $vm_name = shift;
    my $domain_name = shift;

    my $domain = rvd_back()->search_domain($domain_name);

    my $json = $domain->json();
    ok($json);
    my $dec_json = decode_json($json);
    ok($dec_json->{name} && $dec_json->{name} eq $domain->name 
        ,"[$vm_name] expecting json->{name} = '".$domain->name."'"
        ." , got ".($dec_json->{name} or '<UNDEF>')." for json ".Dumper($dec_json)
    );
    
    my $vm = rvd_back()->search_vm($vm_name);
    my $domain2 = $vm->search_domain_by_id($domain->id);
    my $json2 = $domain2->json();
    ok($json2);
    my $dec_json2 = decode_json($json2);
    ok($dec_json2->{name} && $dec_json2->{name} eq $domain2->name 
        ,"[$vm_name] expecting json->{name} = '".$domain2->name."'"
        ." , got ".($dec_json2->{name} or '<UNDEF>')." for json ".Dumper($dec_json2)
    );

}

#######################################################

remove_old_domains();
remove_old_disks();

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS) or next;

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
        test_json($vm_name, $domain->name);
        test_search_domain($domain);
        test_manage_domain($domain);
        test_pause_domain($vm_name, $domain);
        test_remove_domain($domain);
    };
}
done_testing();
