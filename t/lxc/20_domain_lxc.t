use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::LXC');
use_ok('Ravada::VM::LXC');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada= Ravada->new( connector => $test->connector);
my $vm_lxc;


my $CONT= 0;


sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $ravada->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove() };
        ok(!$@ , "Error removing domain $name : $@") or exit;
    }
    $domain = $ravada->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;
}

sub test_remove_domain_by_name {
    my $name = shift;

    diag("Removing domain $name");
    $ravada->remove_domain($name);

    my $domain = $ravada->search_domain($name, 1);
    die "I can't remove old domain $name"
        if $domain;

}

sub search_domain_db {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_new_domain {
    my $active = shift;
    
    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$CONT++;

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

    my $row =  search_domain_db($domain->name);
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");

    my $domain2 = $ravada->search_domain_by_id($domain->id);
    ok($domain2->id eq $domain->id,"Expecting id = ".$domain->id." , got ".$domain2->id);
    ok($domain2->name eq $domain->name,"Expecting name = ".$domain->name." , got "
        .$domain2->name);

    return $domain;
}

sub test_domain_inactive {
    my $domain = test_domain(0);
}

sub test_domain{

    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $ravada->list_domains();
    my $domain = test_new_domain($active);

    if (ok($domain,"test domain not created")) {
        my @list = $ravada->list_domains();
        ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
            .($n_domains+1)
            ." "
            .join(",", sort map { $_->name } @list)
        );
        ok(!$domain->is_base,"Domain shouldn't be base "
            .Dumper($domain->_select_domain_db()));

        # test list domains
        my @list_domains = $ravada->list_domains();
        ok(@list_domains,"No domains in list");
        my $list_domains_data = $ravada->list_domains_data();
        ok($list_domains_data && $list_domains_data->[0],"No list domains data ".Dumper($list_domains_data));
        my $is_base = $list_domains_data->[0]->{is_base} if $list_domains_data;
        ok($is_base eq '0',"Mangled is base '$is_base' ".Dumper($list_domains_data));

        # test prepare base
        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base"
            .Dumper($domain->_select_domain_db())

        );
        ok(!$domain->is_active,"domain should be inactive") if defined $active && $active==0;
        ok($domain->is_active,"domain should active") if defined $active && $active==1;

        ok(test_domain_in_virsh($domain->name,$domain->name)," not in virsh list all");
        my $vm_domain;
        eval { $vm_domain = $ravada->vm->[0]->vm->get_domain_by_name($domain->name)};
        ok($vm_domain,"Domain ".$domain->name." missing in VM") or exit;

        test_remove_domain($domain->name);
    }
}



################################################################
eval { $vm_lxc = Ravada::VM::LXC->new() };
SKIP: {

    my $msg = ($@ or "No LXC vitual manager found");

    if (!$vm_lxc) {
        diag("SKIPPING LXC tests: $msg");
        skip $msg,10;
    }
    my $domain = test_domain();

#test_new_domain();

#test_remove_container( $domain );

}

done_testing();
