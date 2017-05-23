use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;
my $BACKEND = 'LXD';

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
init($test->connector, 't/etc/ravada.conf');
use_ok('Ravada');

my $RAVADA = rvd_back();
my $USER = create_user('foo','bar');

my ($n,$DOMAIN_NAME) = $0 =~ m{.*/(\d+)_(.*)\.t};
$DOMAIN_NAME =~ tr/_/-/;
$DOMAIN_NAME .= "$n";
my $CONT= 0;


sub test_remove_domain($vm_lxd, $name) {
    confess "Wrong LXD " if !ref($vm_lxd);
    my $domain = $vm_lxd->search_domain($vm_lxd, $name,1) or return;
    diag("Removing domain $name");
    $domain->remove() if $domain;
    diag ("$@");
    ok(!$@ , "Error removing domain $name : $@") or return;
  
    $domain = $RAVADA->search_domain($vm_lxd, $name,1);
    ok(!$domain, "I can't remove old domain $name") or return;

    ok(!search_domain_db($name),"Domain $name still in db");

    # TODO
#    my $out = `lxc-info -n $name`;
#    ok($?,"I can't remove old domain $name $out") or exit;
}

sub test_remove_domain_by_name($vm_lxd, $name) {

    diag("Removing domain: $name");
    $vm_lxd->remove_domain($name);

    my $domain = $vm_lxd->search_domain($vm_lxd, $name);
    ok(!$domain,"Expecting old domain $name no more, got $domain");
}

sub search_domain_db {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_array;
    return $row;
}

sub _new_name {
    return $DOMAIN_NAME."-".$CONT++;
}

sub test_new_domain {
    my $vm_lxd = shift;
    my $active = shift;
    
    my $name = _new_name();
    diag ("Test remove domain");
    test_remove_domain($vm_lxd, $name);

    diag("Creating container $name.");
    my $domain = $vm_lxd->_create_domain_http(name => $name, id_template => 1, active => $active
        , id_owner => $USER->id
        , vm => $BACKEND
    );
    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::LXD';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain)) or return
        if $domain;


    my @cmd = ('lxc','info',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");
    return $domain;
}

sub test_domain_inactive($vm_lxd) {
    my $domain = test_domain($vm_lxd, 0);
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base();

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? AND is_base='y'");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find ".$domain->name." in bases");
    $sth->finish;
}

sub test_domain($vm_lxd, $active = 1){
    $active = 1 if !defined $active;

    my $vm = $RAVADA->search_vm('lxd');

    my $n_domains = (scalar $vm->list_domains() or 0);
    diag("Test new domain n_domains= $n_domains");
    my $domain = test_new_domain($vm_lxd, $active);
    if (ok($domain,"test domain not created")) {
        my $name_here;
        eval { $name_here = $domain->name };
        ok($name_here, "No name found for domain ".($@ or ''));
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
        # TODO
#        test_prepare_base($domain);
#        ok($domain->is_base,"Domain should be base"
#            .Dumper($domain->_select_domain_db())
        #
        #);
        #ok(!$domain->is_active,"domain should be inactive") if defined $active && $active==0;
        #ok($domain->is_active,"domain should active") if defined $active && $active==1;

        test_remove_domain($vm_lxd, $domain->name);
    }
}

################################################################
my $vm_lxd;
eval { $vm_lxd = rvd_back->search_vm('lxd') };

use_ok('Ravada::Domain::LXD')   if $vm_lxd;
use_ok('Ravada::VM::LXD')       if $vm_lxd;

SKIP: {

    my $msg = ($@ or "No LXD vitual manager found");

    my $vm;
    eval { $vm = $RAVADA->search_vm('lxd') } if $RAVADA;

    if (!$vm_lxd) {
        ok(!$vm,"There should be no LXD backends");
        diag("SKIPPING LXD tests: $msg");
        skip $msg,10;
    } else {
        # TODO
#        $Ravada::VM::LXC::CMD_LXC_LS = '';
#        # twice to ignore warnings
#        $Ravada::VM::LXC::CMD_LXC_LS = '';
#        diag("Testing missing LXC");
        #
        #my $ravada2 = Ravada->new( connector => $test->connector);
        #my $vm2 = $ravada2->search_vm('lxd');
        #ok(!$vm2,"No LXC virtual manager should be found withoud LXC_LS defined");
    }
    ok($vm,"I can't find a LXD virtual manager from ravada");

    remove_old_domains();
    my $domain = test_domain($vm_lxd);
    test_remove_domain($vm_lxd, $domain)    if $domain;
}
remove_old_domains();

done_testing();
