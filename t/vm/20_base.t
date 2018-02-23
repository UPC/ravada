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

my $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG);
my $RVD_FRONT= rvd_front($test->connector, $FILE_CONFIG);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my @VMS = vm_names();
my $USER = create_user("foo","bar");

my $DISPLAY_IP = '99.1.99.1';

#######################################################################33

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub test_create_domain_swap {
    my $vm_name = shift;
    my $domain = test_create_domain($vm_name);

    $domain->add_volume_swap( size => 128 * 1024 * 1024 );
    return $domain;
}

sub test_files_base {
    my $domain = shift;
    my $n_expected = shift;

    my @files = $domain->list_files_base();

    ok(scalar @files == $n_expected,"Expecting $n_expected files base , got "
            .scalar @files);
    return;
}

sub test_display {
    my ($vm_name, $domain) = @_;

    my $display;
    $domain->start($USER) if !$domain->is_active;
    eval { $display = $domain->display($USER)};
    is($@,'');
    ok($display,"Expecting a display URI, got '".($display or '')."'") or return;

    my ($ip) = $display =~ m{^\w+://(.*):\d+} if defined $display;

    ok($ip,"Expecting an IP , got ''") or return;

    ok($ip ne '127.0.0.1', "[$vm_name] Expecting IP no '127.0.0.1', got '$ip'") or exit;


    # only test this for Void, it will fail on real VMs
    return if $vm_name ne 'Void';

    $Ravada::CONFIG->{display_ip} = $DISPLAY_IP;
    eval { $display = $domain->display($USER) };
    is($@,'');
    ($ip) = $display =~ m{^\w+://(.*):\d+};

    my $expected_ip =  Ravada::display_ip();
    ok($expected_ip,"[$vm_name] Expecting display_ip '$DISPLAY_IP' , got none in config "
        .Dumper($Ravada::CONFIG)) or exit;

    ok($ip eq $expected_ip,"Expecting display IP '$expected_ip', got '$ip'");

}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;
    my $n_volumes = (shift or 1);

    test_files_base($domain,0);
    $domain->shutdown_now($USER)    if $domain->is_active();

    eval { $domain->prepare_base( $USER) };
    ok(!$@, $@);
    ok($domain->is_base);
    is($domain->is_active(),0);
    $domain->is_public(1);

    my $front_domains = rvd_front->list_domains();
    my ($dom_front) = grep { $_->{name} eq $domain->name }
        @$front_domains;

    ok($dom_front,"Expecting the domain ".$domain->name
                    ." in list domains");

    if ($dom_front) {
        ok($dom_front->{is_base});
    }

    ok($domain->is_base);
    $domain->is_public(1);

    test_files_base($domain, $n_volumes);

    my @disk = $domain->disk_device();
    $domain->shutdown(user => $USER)    if $domain->is_active;

    # We can't prepare base if already prepared
    eval { $domain->prepare_base( $USER) };
    like($@, qr'.');
    is($domain->is_base,1);

    # So we remove the base
    eval { $domain->remove_base( $USER) };
    is($@,'');
    is($domain->is_base,0);

    # And prepare again
    eval { $domain->prepare_base( $USER) };
    is($@,'');
    is($domain->is_base,1);

    my $name_clone = new_domain_name();

    my $domain_clone;
    eval { $domain_clone = $RVD_BACK->create_domain(
        name => $name_clone
        ,id_owner => $USER->id
        ,id_base => $domain->id
        ,vm => $vm_name
        );
    };
    ok(!$@,"Clone domain, expecting error='' , got='".($@ or '')."'") or exit;
    ok($domain_clone,"Trying to clone from ".$domain->name." to $name_clone");
    test_devices_clone($vm_name, $domain_clone);
    test_display($vm_name, $domain_clone);

    ok($domain_clone->id_base && $domain_clone->id_base == $domain->id
        ,"[$vm_name] Expecting id_base=".$domain->id." got ".($domain_clone->id_base or '<UNDEF>')) or exit;

    my $domain_clone2 = $RVD_FRONT->search_clone(
         id_base => $domain->id,
        id_owner => $USER->id
    );
    ok($domain_clone2,"Searching for clone id_base=".$domain->id." user=".$USER->id
        ." expecting domain , got nothing "
        ." ".Dumper($domain)) or exit;

    if ($domain_clone2) {
        ok( $domain_clone2->name eq $domain_clone->name
        ,"Expecting clone name ".$domain_clone->name." , got:".$domain_clone2->name
        );

        ok($domain_clone2->id eq $domain_clone->id
        ,"Expecting clone id ".$domain_clone->id." , got:".$domain_clone2->id
        );
    }


    ok($domain->is_base);

    $domain_clone->remove($USER);

    eval { $domain->remove_base($USER) };
    is($@,'');

    eval { $domain->prepare_base($USER) };
    is($@,'');
    ok($domain->is_base,"[$vm_name] Expecting domain is_base=1 , got :".$domain->is_base);
    ok(!$@,"[$vm_name] Error preparing base after clone removed :'".($@ or '')."'");

    eval { $domain->start($USER)};
    like($@,qr/bases.*started/i);
    is($domain->is_active,0,"Expecting base domains can't be run");

    $domain->is_base(0);
    ok(!$domain->is_base,"[$vm_name] Expecting domain is_base=0 , got :".$domain->is_base);

    $domain->is_base(1);
    ok($domain->is_base,"[$vm_name] Expecting domain is_base=1 , got :".$domain->is_base);

}

sub test_prepare_base_active {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);

    ok(!$domain->is_base,"Domain ".$domain->name." should not be base") or return;
    eval { $domain->start($USER) if !$domain->is_active() };
    ok(!$@,$@) or exit;
    eval { $domain->resume($USER)  if $domain->is_paused()  };
    ok(!$@,$@);

    ok($domain->is_active,"[$vm_name] Domain ".$domain->name." should be active") or return;
    ok(!$domain->is_paused,"[$vm_name] Domain ".$domain->name." should not be paused") or return;

    eval{ $domain->prepare_base($USER) };
    ok(!$@,"[$vm_name] Prepare base, expecting error='', got '$@'") or exit;

    ok(!$domain->is_active,"[$vm_name] Domain ".$domain->name." should not be active")
            or return;
}

sub test_devices_clone {
    my $vm_name = shift;
    my $domain = shift;

    my @volumes = $domain->list_volumes();
    ok(scalar(@volumes),"[$vm_name] domain ".$domain->name
        ." Expecting at least 1 volume cloned "
        ." got ".scalar(@volumes)) or exit;
    for my $disk (@volumes ) {
        ok(-e $disk,"Checking volume ".Dumper($disk)." exists") or exit;
    }
}

sub test_remove_base {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);
    ok($domain,"Expecting domain, got NONE") or return;

    my @files0 = $domain->list_files_base();
    ok(!scalar @files0,"Expecting no files base, got ".Dumper(\@files0)) or return;

    $domain->prepare_base($USER);
    ok($domain->is_base,"Domain ".$domain->name." should be base") or return;

    my @files = $domain->list_files_base();
    ok(scalar @files,"Expecting files base, got ".Dumper(\@files)) or return;

    $domain->remove_base($USER);
    ok(!$domain->is_base,"Domain ".$domain->name." should be base") or return;

    for my $file (@files) {
        ok(!-e $file,"Expecting file base '$file' removed" );
    }

    my @files_deleted = $domain->list_files_base();
    is(scalar @files_deleted,0);

    my $sth = $test->dbh->prepare(
        "SELECT count(*) FROM file_base_images"
        ." WHERE id_domain = ?"
    );
    $sth->execute($domain->id);
    my ($count) = $sth->fetchrow;
    $sth->finish;

    is($count,0,"[$vm_name] Count files base after remove base domain");

}

sub test_dont_remove_base_cloned {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);
    $domain->prepare_base($USER);
    ok($domain->is_base,"[$vm_name] expecting domain is base, got "
                        .$domain->is_base);

    my @files = $domain->list_files_base();

    my $name_clone = new_domain_name();

    $domain->is_public(1);
    my $clone = rvd_back()->create_domain( name => $name_clone
            ,id_owner => $USER->id
            ,id_base => $domain->id
            ,vm => $vm_name
    );
    eval {$domain->remove_base($USER)};
    ok($@,"Expecting error removing base with clones, got '$@'");
    ok($domain->is_base,"[$vm_name] expecting domain is base, got "
                        .$domain->is_base);
    for my $file (@files) {
        ok(-e $file,"[$vm_name] Expecting file base '$file' not removed" );
    }

    ##################################################################3
    # now we remove the clone, it should work

    $clone->remove($USER);

    eval {$domain->remove_base($USER)};
    ok(!$@,"Expecting not error removing base with clones, got '$@'");
    ok(!$domain->is_base,"[$vm_name] expecting domain is base, got "
                        .$domain->is_base);
    for my $file (@files) {
        ok(!-e $file,"[$vm_name] Expecting file base '$file' removed" );
    }

}

sub test_spinned_off_base {
    my $vm_name = shift;

    my $base= test_create_domain($vm_name);
    $base->prepare_base($USER);
    ok($base->is_base,"[$vm_name] expecting domain is base, got "
                        .$base->is_base);

    my $name_clone = new_domain_name();

    $base->is_public(1);
    my $clone = rvd_back()->create_domain( name => $name_clone
            ,id_owner => $USER->id
            ,id_base => $base->id
            ,vm => $vm_name
    );

    # Base can't started, it has clones
    eval { $base->start(user => $USER) };
    like($@,qr'.');
    is($base->is_active,0);

    $clone->prepare_base(user_admin);

    $base->remove_base(user_admin());
    # Base can get started now the clones are released
    eval { $base->start(user => $USER) };
    is($@,'');
    is($base->is_active,1);

    $base->shutdown_now($USER);
    is($base->is_active,0);

    $clone->remove_base(user_admin);

    # Base can get started now the clones are released even though they are not base
    eval { $base->start(user => $USER) };
    is($@,'');
    is($base->is_active,1);

    $clone->remove($USER);
    $base->remove($USER);
}


sub test_private_base {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = test_create_domain($vm_name);
    $domain->prepare_base($USER);

    my $clone_name = new_domain_name();

    my $clone;
    eval { $clone = $domain->clone(user => $USER, name => $clone_name); };
    like($@,qr(.));

    my $clone2 = $vm->search_domain($clone_name);
    ok(!$clone2,"Expecting no clone");

    # admin can clone
    eval { $clone = $domain->clone(user => user_admin, name => $clone_name); };
    is($@,'');

    $clone2 = $vm->search_domain($clone_name);
    ok($clone2,"Expecting a clone");
    $clone->remove(user_admin)  if $clone;

    # when is public, any can clone
    $domain->is_public(1);
    eval { $clone = $domain->clone(user => $USER, name => $clone_name); };
    is($@,'');

    $clone2 = $vm->search_domain($clone_name);
    ok($clone2,"Expecting a clone");
    $clone->remove(user_admin)  if $clone;

    # hide it again
    $domain->is_public(0);
    eval { $clone = $domain->clone(user => $USER, name => $clone_name); };
    like($@,qr(.));

    $clone2 = $vm->search_domain($clone_name);
    ok(!$clone2,"Expecting no clone");
}

sub test_domain_limit {
    my $vm_name = shift;

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $domain = create_domain($vm_name, $USER);
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now($USER)    if $domain->is_active;

    is(rvd_back->list_domains(user => $USER, active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start($USER);
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $USER, active => 1),1);

    my $domain2 = create_domain($vm_name, $USER);
    $domain2->shutdown_now($USER)   if $domain2->is_active;
    is(rvd_back->list_domains(user => $USER, active => 1),1);

    $domain2->start($USER);
    rvd_back->enforce_limits(timeout => 2);
    sleep 2;
    rvd_back->_process_requests_dont_fork();
    my @list = rvd_back->list_domains(user => $USER, active => 1);
    is(scalar @list,1) or die Dumper(\@list);
    is($list[0]->name, $domain2->name) if $list[0];
}

sub test_domain_limit_already_requested {
    my $vm_name = shift;

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $domain = create_domain($vm_name, $USER);
    ok($domain,"Expecting a new domain created") or return;
    $domain->shutdown_now($USER)    if $domain->is_active;

    is(rvd_back->list_domains(user => $USER, active => 1),0
        ,Dumper(rvd_back->list_domains())) or return;

    $domain->start($USER);
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $USER, active => 1),1);

    my $domain2 = create_domain($vm_name, $USER);
    $domain2->shutdown_now($USER)   if $domain2->is_active;
    is(rvd_back->list_domains(user => $USER, active => 1),1);

    $domain2->start($USER);
    my @list_requests = $domain->list_requests;
    is(scalar @list_requests,0,"Expecting 0 requests ".Dumper(\@list_requests));

    rvd_back->enforce_limits(timeout => 2);

    if (!$domain->can_hybernate) {
        @list_requests = $domain->list_all_requests();
        is(scalar @list_requests,1,"Expecting 1 request ".Dumper(\@list_requests));
        rvd_back->enforce_limits(timeout => 2);
        @list_requests = $domain->list_all_requests();

        is(scalar @list_requests,1,"Expecting 1 request ".Dumper(\@list_requests));

        sleep 3;

        rvd_back->_process_requests_dont_fork();
    }
    @list_requests = $domain->list_requests;
    is(scalar @list_requests,0,"Expecting 0 request ".Dumper(\@list_requests)) or exit;

    my @list = rvd_back->list_domains(user => $USER, active => 1);
    is(scalar @list,1) or die Dumper(\@list);
    is($list[0]->name, $domain2->name) if $list[0];
}

#######################################################################33


remove_old_domains();
remove_old_disks();

for my $vm_name ('Void','KVM') {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";


    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok($CLASS);

        test_domain_limit_already_requested($vm_name);

        my $domain = test_create_domain($vm_name);
        test_prepare_base($vm_name, $domain);
        test_prepare_base_active($vm_name);
        test_remove_base($vm_name);
        test_dont_remove_base_cloned($vm_name);

        test_private_base($vm_name);

        test_spinned_off_base($vm_name);
        test_domain_limit($vm_name);


        $domain->remove($USER);
        $domain = undef;

        my $domain2 = test_create_domain_swap($vm_name);
        test_prepare_base($vm_name, $domain2 , 2);
        $domain2->remove($USER);

        $domain2 = test_create_domain_swap($vm_name);
        $domain2->start($USER);
        $domain2->shutdown_now($USER);
        test_prepare_base($vm_name, $domain2 , 2);
        $domain2->remove($USER);

    }
}

remove_old_domains();
remove_old_disks();

done_testing();
