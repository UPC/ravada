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
    skip("LXC disabled in this release",3);
    use_ok('Ravada::Domain::LXC');
    use_ok('Ravada::VM::LXC');
    $CAN_LXC = 1;
};

my $RAVADA= Ravada->new( connector => connector() );
$RAVADA->_install();

my $vm_lxc;

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.t};
my $CONT= 0;


sub test_remove_domain {
    my $name = shift;
    my $domain = $vm_lxc->search_domain($name,1) or return;
    diag("Removing domain $name");
    $domain->remove() if $domain;
    diag ("$@");
    ok(!$@ , "Error removing domain $name : $@") or exit;
  
    $domain = $RAVADA->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;

    ok(!search_domain_db($name),"Domain $name still in db");

    my $out = `lxc-info -n $name`;
    ok($?,"I can't remove old domain $name $out") or exit;
}

sub test_remove_domain_by_name {
    my $name = shift;

    diag("Removing domain: $name");
    $vm_lxc->remove_domain($name);

    my $domain = $vm_lxc->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;
}

sub search_domain_db {
    my $name = shift;
    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_array;
    return $row;
}

sub _new_name {
    return $DOMAIN_NAME."_".$CONT++;
}

sub test_domain_from_base {
    my $base_name = shift;
    my $base = $vm_lxc->search_domain($base_name,1) or die "Unknown domain $base_name";

    my $name = _new_name();
    test_remove_domain($name);
    my $domain = $vm_lxc->create_domain(name => $name
        , id_base => $base->id);#, active => $active);

    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::LXC';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('lxc-info','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    return $domain;
}

sub test_new_domain {
    my $active = shift;
    
    my $name = _new_name();
    diag ("Test remove domain");
    test_remove_domain($name);

    diag("Creating container $name.");
    my $domain = $vm_lxc->create_domain(name => $name, id_template => 1, active => $active);
    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::LXC';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('lxc-info','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");
    #my $row =  search_domain_db($domain->name);
    #ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    my $pq = $domain->id;
    
    #my $domain2 = $vm_lxc->search_domain_by_id($domain->id);
    #ok($domain2->id eq $domain->id,"Expecting id = ".$domain->id." , got ".$domain2->id);
    #ok($domain2->name eq $domain->name,"Expecting name = ".$domain->name." , got "
    #    .$domain2->name);

    return $domain;
}

sub test_domain_inactive {
    my $domain = test_domain(0);
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base();

    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? AND is_base=1");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find ".$domain->name." in bases");
    $sth->finish;
}

sub test_domain{
    my $active = shift;
    $active = 1 if !defined $active;

    my $vm = $RAVADA->search_vm('lxc');

    my $n_domains = scalar $vm->list_domains();
    diag("Test new domain n_domains= $n_domains");
    my $domain = test_new_domain($active);
    if (ok($domain,"test domain not created")) {
        my @list = $vm->list_domains();
        ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
            .($n_domains+1)
            .". List: "
            .join(" * ", sort map { $_->name } @list)
        );
#PER AQUI
        ok(!$domain->is_base,"Domain shouldn't be base "
            .Dumper($domain->_select_domain_db()));

        # test list domains
        my @list_domains = $vm->list_domains();
        ok(@list_domains,"No domains in list");
        my $list_domains_data = $RAVADA->list_domains_data();
        ok($list_domains_data && $list_domains_data->[0],"No list domains data ".Dumper($list_domains_data));
        my $is_base = $list_domains_data->[0]->{is_base} if $list_domains_data;
        ok($is_base eq '0',"Mangled is base '$is_base' ".Dumper($list_domains_data));

        # test prepare base
        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base "
            ."is_base=".$domain->is_base." "
            .Dumper($domain->_select_domain_db())

        );
        ok(!$domain->is_active,"domain should be inactive") if defined $active && $active==0;
        ok($domain->is_active,"domain should active") if defined $active && $active==1;

    }
}

sub remove_old_domains_lxc_local {
    for ( 0 .. 10 ) {
        my $dom_name = $DOMAIN_NAME."_$_";

        my $domain = $RAVADA->search_domain($dom_name,1);
        $domain->shutdown_now() if $domain;
        test_remove_domain($dom_name);
    }

}

################################################################
eval { $vm_lxc = Ravada::VM::LXC->new() } if $CAN_LXC;
SKIP: {
    my $msg = ($@ or "No LXC vitual manager found");

    my $vm = $RAVADA->search_vm('lxc') if $RAVADA;

    if (!$vm_lxc) {
        ok(!$vm,"There should be no LXC backends");
        diag("SKIPPING LXC tests: $msg");
        skip $msg,10;
    } else {
        my $lxc_ls = $Ravada::VM::LXC::CMD_LXC_LS;
        $Ravada::VM::LXC::CMD_LXC_LS = '';
        diag("Testing missing LXC");

        my $ravada2;
        eval { $ravada2 = Ravada->new( connector => connector() ); };
        my $vm2 = $ravada2->search_vm('lxc')    if $ravada2;
        ok(!$vm2,"No LXC virtual manager should be found withoud LXC_LS defined");
        $Ravada::VM::LXC::CMD_LXC_LS = $lxc_ls;
        remove_old_domains_lxc_local();
        my $domain = test_domain();
        my $domain2 = test_domain_from_base($domain);
        test_remove_domain($domain);
        test_remove_domain($domain2);
    }
    ok($vm,"I can't find a LXC virtual manager from ravada");

}

done_testing();
