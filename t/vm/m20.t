#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector);

##############################################################################

sub test_change_memory {
	my $vm = shift;

    my $domain = create_domain($vm->type);
    $domain->start(user_admin)  if !$domain->is_active();
    
    my $info = $domain->get_info;
    ok($info->{max_mem}, ($info->{max_mem}/(1024*1024))."GB" );
    
    my $nmemory = $info->{max_mem}+1024*1024;
    
    eval{ $domain->set_max_mem($nmemory) };
    ok($@,"Can't change max memory on active machine");
    
    $domain->shutdown_now( user_admin ) if $domain->is_active;
    is($domain->is_active,0);
        
    eval{ $domain->set_max_mem($nmemory) };
    ok(!$@, $@);
    
    my $info2 = $domain->get_info;
    ok($info2->{max_mem}==$nmemory, ($info2->{max_mem}/(1024*1024))."GB" );
    
    $domain->start(user_admin)  if !$domain->is_active();
    
    my $nmemory2 = 1024*1024/2;
    
    eval{ $domain->set_memory($nmemory2) };
    ok(!$@,$@);
    
    my $info3 = $domain->get_info;
    ok($info3->{memory}==$nmemory2, ($info3->{memory}/(1024*1024))."GB" ); #NO FUNCIONA!!!
    
    $domain->remove(user_admin);
}

sub test_change_memory_base {
	my $vm = shift;
	
	my $domain = create_domain($vm->type);
	$domain->shutdown_now(user_admin)    if $domain->is_active();

    eval { $domain->prepare_base( user_admin ) };
    ok(!$@, $@);
    ok($domain->is_base);
    
    eval { $domain->set_max_mem(1024*1024*2) };
    ok(!$@,$@);
     
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description);
    ok($doc,$doc);
    
    $domain->remove(user_admin);
}

##############################################################################

clean();

use_ok('Ravada');

for my $vm_name ( q(KVM) ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg       if !$vm;

        diag("Testing change memory on $vm_name");

        test_change_memory($vm);
        test_change_memory_base($vm);

    }
}

clean();

done_testing();
