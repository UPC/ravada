use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

my $BACKEND = 'KVM';

use_ok('Ravada');

my $RAVADA = rvd_back();
my $USER = create_user('foo','bar', 1);

sub test_vm_kvm {
    my $vm = $RAVADA->search_vm('kvm');
    ok($vm,"No vm found") or exit;
    ok(ref($vm) =~ /KVM$/,"vm is no kvm ".ref($vm)) or exit;

    ok($vm->type, "Not defined $vm->type") or exit;
    ok($vm->host, "Not defined $vm->host") or exit;

}
sub test_remove_domain {
    my $name = shift;
    my $user = (shift or $USER);

    my $domain;
    $domain = $RAVADA->search_domain($name,1);

    if ($domain) {
#        diag("Removing domain $name");
        eval { $domain->remove($user) };
        ok(!$@,"Domain $name should be removed ".$@) or exit;
    }
    $domain = $RAVADA->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

    ok(!search_domain_db($name),"Domain $name still in db");
}

sub test_remove_domain_by_name {
    my $name = shift;

#    diag("Removing domain $name");
    $RAVADA->remove_domain(name => $name, uid => $USER->id);

    my $domain = $RAVADA->search_domain($name, 1);
    die "I can't remove old domain $name"
        if $domain;

}

sub test_remove_corrupt_clone {
    my $vm = shift;

    my $base = create_domain($vm);
    $base->add_volume_swap( size => 1024 * 1024 );
    my $clone = $base->clone(
         name => new_domain_name
        ,user => user_admin
    );

    for my $file ( $clone->list_disks ) {
        open my $out, '>',$file or die "$! $file";
        print $out "bogus\n";
        close $out;
    }
    eval { $clone->start(user_admin) };
    diag($@);
    $clone->shutdown_now(user_admin);

    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub search_domain_db
 {
    my $name = shift;
    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_new_domain {
    my $active = shift;

    my $name = new_domain_name();

    test_remove_domain($name);

#    diag("Creating domain $name");
    my $domain = $RAVADA->create_domain(name => $name, id_iso => search_id_iso('Alpine')
        , active => $active
        , id_owner => $USER->id
        , vm => $BACKEND
        , disk => 1024 * 1024
    );

    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $row =  search_domain_db($domain->name);
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");

    my $domain2 = $RAVADA->search_domain($domain->name);
    ok($domain2->id eq $domain->id,"Expecting id = ".$domain->id." , got ".$domain2->id);
    ok($domain2->name eq $domain->name,"Expecting name = ".$domain->name." , got "
        .$domain2->name);

    return $domain;
}

sub test_new_domain_iso {
    my $active = shift;
    
    my $vm = rvd_back()->search_vm($BACKEND);
    my $iso = $vm->_search_iso(search_id_iso('Alpine'));
    my $name = new_domain_name();

    test_remove_domain($name);

#    diag("Creating domain $name");
    my $domain;
    eval {
      $domain = $RAVADA->create_domain(name => $name, id_iso => search_id_iso('alpine')
          , active => $active
        , id_owner => $USER->id , iso_file => $iso->{device}
        , vm => $BACKEND
        , disk => 1024 * 1024
        );
      };
    is($@,'') or return;
    
    ok($domain,"Domain not created");
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;
        
    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $row =  search_domain_db($domain->name);
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");

    my $domain2 = $RAVADA->search_domain($domain->name);

    ok($domain2->id eq $domain->id,"Expecting id = ".$domain->id." , got ".$domain2->id);
    ok($domain2->name eq $domain->name,"Expecting name = ".$domain->name." , got "
        .$domain2->name);
    #TODO HOW TO COMPARE THE ISO OF TWO MACHINES    

    return $domain;
}

sub test_prepare_base {
    my $domain = shift;
    $domain->prepare_base(user_admin);

    my $sth = connector->dbh->prepare("SELECT is_base FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my ($is_base) =  $sth->fetchrow;
    ok($is_base
            ,"Expecting is_base=1 got "
            .(${is_base} or '<UNDEF>'));
    $sth->finish;
}


sub test_domain_inactive {
    my $domain = test_domain(0);
}

sub test_domain{

    my $active = shift;
    $active = 1 if !defined $active;

    my $vm = $RAVADA->search_vm('kvm');
    my $n_domains = scalar $vm->list_domains();
    my $domain = test_new_domain($active);

    if (ok($domain,"test domain not created")) {
        my @list = $vm->list_domains();
        ok(scalar(@list) == $n_domains + 1,"Found ".scalar(@list)." domains, expecting "
            .($n_domains+1)
            ." "
            .join(" * ", sort map { $_->name } @list)
        ) or exit;
        ok(!$domain->is_base,"Domain shouldn't be base ");

        # test list domains
        my @list_domains = $vm->list_domains();
        ok(@list_domains,"No domains in list");
        my $list_domains_data = $RAVADA->list_domains_data();
        ok($list_domains_data && $list_domains_data->[0],"No list domains data ");
        my $is_base = $list_domains_data->[0]->{is_base} if $list_domains_data;
        ok($is_base eq '0',"Mangled is base '$is_base', it should be 0 ");

        ok(!$domain->is_active  ,"domain should be inactive") if defined $active && $active==0;
        ok($domain->is_active   ,"domain should be active")   if defined $active && $active==1;

        # test prepare base
        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base");
 
        ok(test_domain_in_virsh($domain->name,$domain->name)," not in virsh list all");
        my $domain2;
        $vm->connect();
        eval { $domain2 = $vm->vm->get_domain_by_name($domain->name)};
        ok($domain2,"Domain ".$domain->name." missing in VM") or exit;

        test_remove_domain($domain->name);
    }
}

sub test_domain_in_virsh {
    my $name = shift;
    my $vm = $RAVADA->search_vm('kvm');

    $vm->connect();
    for my $domain ($vm->vm->list_all_domains) {
        if ( $domain->get_name eq $name ) {
            $vm->disconnect;
            return 1 
        }
    }
    $vm->disconnect();
    return 0;
}

sub test_domain_missing_in_db {
    # test when a domain is in the VM but not in the DB

    my $active = shift;
    $active = 1 if !defined $active;

    my $n_domains = scalar $RAVADA->list_domains();
    my $domain = test_new_domain($active);
    ok($RAVADA->list_domains > $n_domains,"There should be more than $n_domains");

    if (ok($domain,"test domain not created")) {

        my $sth = connector->dbh->prepare("DELETE FROM domains WHERE id=?");
        $sth->execute($domain->id);

        my $domain2 = $RAVADA->search_domain($domain->name);
        ok(!$domain2,"This domain should not show up in Ravada, it's not in the DB");

        my $vm = $RAVADA->search_vm('kvm');
        my $domain3;
        $vm->connect();
        eval { $domain3 = $vm->vm->get_domain_by_name($domain->name)};
        ok($domain3,"I can't find the domain in the VM") or return;

        my @list_domains = $RAVADA->list_domains;
        ok($RAVADA->list_domains == $n_domains,"There should be only $n_domains domains "
                                        .", there are ".scalar(@list_domains));

        test_remove_domain($domain->name, user_admin());
    }
}


sub test_domain_by_name {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {
        test_remove_domain_by_name($domain->name);
    }
}

sub test_domain_with_iso {
  my $domain = test_new_domain_iso();
  
  if (ok($domain,"test domain not created")) {
      test_remove_domain_by_name($domain->name);
  }
}

sub test_prepare_import {
    my $domain = test_new_domain();

    if (ok($domain,"test domain not created")) {

        test_prepare_base($domain);
        ok($domain->is_base,"Domain should be base");

        test_remove_domain($domain->name);
    }

}

################################################################

my $vm;
clean();

eval { $vm = $RAVADA->search_vm('kvm') } if $RAVADA;
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    if ($vm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok("Ravada::Domain::$BACKEND");

test_vm_kvm();

remove_old_domains();
remove_old_disks();
test_domain();
test_remove_corrupt_clone($vm);
test_domain_with_iso();
test_domain_missing_in_db();
test_domain_inactive();
test_domain_by_name();
test_prepare_import();

};
clean();
done_testing();
