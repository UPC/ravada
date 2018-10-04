use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

my $CAN_LXC = 0;
use_ok('Ravada');
SKIP: {
    skip("LXC disabled in this release",2);
    use_ok('Ravada::Domain::LXC');
    use_ok('Ravada::VM::LXC');
    $CAN_LXC = 1;
}

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
my $RAVADA= Ravada->new( connector => $test->connector);
$RAVADA->_install();
my $vm_lxc;

my $CONT= 0;


sub test_remove_domain {
    my $name = shift;

  
        diag("Removing domain $name");
        my $domain = $vm_lxc->search_domain($name);
        $domain->remove() if $domain;
        diag ("$@");
        ok(!$@ , "Error removing domain $name : $@") or exit;
  
    $domain = $RAVADA->search_domain($name);
    ok(!$domain, "I can't remove old domain $name") or exit;
}

sub test_new_domain {
    my $active = shift;
    
    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$CONT++;
    diag ("Test remove domain");
    test_remove_domain($name);

    diag("Creating container $name. It may take looong time the very first time.");
    my $domain = $vm_lxc->create_domain(name => $name, id_iso => 1, active => $active);
    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::LXC';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('lxc-info','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");
    return $name;
}

sub test_domain_create_from_base {
    my $name = shift; 
    diag("Test domain created from base: $name");
    #my $newdomain = $vm_lxc->_domain_create_from_base($name);
    my $self = $vm_lxc->_domain_create_from_base($name);
    warn $self;#$newdomain;
    ok(!$?,"Error create domain from base: $name");
    return $self if $self;# newdomain if $newdomain;
}

sub test_with_limits_template{
    my $name = shift;
    my $memory = "1G";
    my $swap = "512M";
    my $cpushares = "256";
    my $ioweight = "500";
    diag("Test add limit to domain created from template: $name");
    Ravada::Domain::LXC->limits($name,$memory,$swap,$cpushares,$ioweight);
    ok(!$?,"Error appliying limits to container: $name");
    return;
}

sub test_with_limits_base{
    my $name = shift;
    my $memory = "1G";
    my $swap = "512M";
    my $cpushares = "256";
    my $ioweight = "500";
    diag("Test add limit to domain created from base: $name");
    Ravada::Domain::LXC->limits($name,$memory,$swap,$cpushares,$ioweight);
    ok(!$?,"Error appliying limits to base container: $name");
    return;
}

sub test_domain{
    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $RAVADA->list_domains();
    
    diag("Test new domain n_domains= $n_domains");
    my $domain = test_new_domain($active);

    # if (ok($domain,"test domain not created")) {
    #     my @list = $RAVADA->list_domains();
    #     warn Dumper (@list);
    #     ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
    #         .($n_domains+1)
    #         ." "
    #         .join(",", sort map { $_->name } @list)
    #    );
        # ok(!$domain->is_base,"Domain shouldn't be base "
        #    .Dumper($domain->_select_domain_db()));

        # test list domains
        # my @list_domains = $RAVADA->list_domains();
        # ok(@list_domains,"No domains in list");

        # my $list_domains_data = $RAVADA->list_domains_data();
        # ok($list_domains_data && $list_domains_data->[0],"No list domains data ".Dumper($list_domains_data));
        # my $is_base = $list_domains_data->[0]->{is_base} if $list_domains_data;
        # ok($is_base eq '0',"Mangled is base '$is_base' ".Dumper($list_domains_data));

#TODO
        # test prepare base
#        test_prepare_base($domain);
#       ok($domain->is_base,"Domain should be base"
#            .Dumper($domain->_select_domain_db())
#        );
#        ok(!$domain->is_active,"domain should be inactive") if defined $active && $active==0;
#        ok($domain->is_active,"domain should active") if defined $active && $active==1;

#        ok(test_domain_in_virsh($domain->name,$domain->name)," not in virsh list all");
#        my $vm_domain;
#        eval { $vm_domain = $RAVADA->vm->[0]->vm->get_domain_by_name($domain->name)};
#        ok($vm_domain,"Domain ".$domain->name." missing in VM") or exit;

#        test_remove_domain($domain);
#    }
}



################################################################
eval { $vm_lxc = Ravada::VM::LXC->new() } if $CAN_LXC;
SKIP: {

    my $msg = ($@ or "No LXC vitual manager found");

    my $vm = $RAVADA->search_vm('lxc');

    if (!$vm_lxc) {
        ok(!$vm,"There should be no LXC backends");
        diag("SKIPPING LXC tests: $msg");
        skip $msg,10;
    } else {
        $Ravada::VM::LXC::CMD_LXC_LS = '';
        # twice to ignore warnings
        $Ravada::VM::LXC::CMD_LXC_LS = '';
        diag("Testing missing LXC");

        my $ravada2 = Ravada->new();
        my $vm2 = $ravada2->search_vm('lxc');
        ok(!$vm2,"No LXC virtual manager should be found withoud LXC_LS defined");
    }
    ok($vm,"I can't find a LXC virtual manager from ravada");
    #my $domain = test_domain();

#test_new_domain();
my $domain = test_domain();
#test_with_limits_template($domain);


my $newdomain = test_domain_create_from_base($domain);
test_with_limits_base($newdomain);

#test_remove_domain($domain);

}

done_testing();
