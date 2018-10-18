use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
my $CAN_LXC = 0;
SKIP: {
    skip("LXC disabled in this release",2);

    use_ok('Ravada::Domain::LXC');
    use_ok('Ravada::VM::LXC');
    $CAN_LXC = 1;
}

my $RAVADA= Ravada->new( connector => connector() );
my $vm_lxc;

my $CONT= 0;


sub test_remove_domain {
    my $name = shift;
    diag("Removing domain $name");
    warn $name;
    my $domain = $vm_lxc->search_domain($name);
    warn $domain;
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
    my $name_cow = $name . "_cow";
    warn $name_cow;
    test_remove_domain($name_cow);
    test_remove_domain($name);

    #diag("Creating container $name. It may take looong time the very first time.");
    #my $domain = $vm_lxc->create_domain(name => $name, id_iso => 1, active => $active);
    #ok($domain,"Domain not created") or return;
    #my $exp_ref= 'Ravada::Domain::LXC';
    #ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
    #    if $domain;

    #my @cmd = ('lxc-info','-n',$name);
    #my ($in,$out,$err);
    #run3(\@cmd,\$in,\$out,\$err);
    #ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");
    return $name;
}

sub test_domain_create_from_base {
    my $name = shift; 
    diag("Test domain created from base: $name");
    #my $newdomain = $vm_lxc->_domain_create_from_base($name);
    my $newname = $name . "_cow";
    test_remove_domain($newname);

    my $self = $vm_lxc->_domain_create_from_base($name);
    warn $self;#$newdomain;
    ok(!$?,"Error create domain from base: $name");
    return $self if $self;# newdomain if $newdomain;
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

        my $ravada2= Ravada->new( connector => connector() );
        my $vm2 = $ravada2->search_vm('lxc');
        ok(!$vm2,"No LXC virtual manager should be found withoud LXC_LS defined");
    }
    ok($vm,"I can't find a LXC virtual manager from ravada");

my $domain = test_domain();

my $newdomain = test_domain_create_from_base($domain);
test_with_limits_base($newdomain);

#test_remove_domain($domain);

}

done_testing();
