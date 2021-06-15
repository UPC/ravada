use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector);

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
                    , id_owner => user_admin->id
                    , disk => 1024 * 1024
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

    my @ips = local_ips($domain->_vm);

    my @ips2 = grep { $_ ne '127.0.0.1' } @ips;
    skip("No IPs found in ".$domain->_vm->name,5) if !scalar @ips2;

    my $display;
    $domain->shutdown_now(user_admin);
    $domain->start(user => user_admin, remote_ip => '1.2.3.4' );# if !$domain->is_active;
    eval { $display = $domain->display( user_admin )};
    is($@,'');
    ok($display,"Expecting a display URI, got '".($display or '')."'") or return;

    my $ip;
    ($ip) = $display =~ m{^\w+://(.*):\d+} if defined $display;

    ok($ip,"Expecting an IP , got ''") or return;

    ok($ip ne '127.0.0.1', "[$vm_name] Expecting IP no '127.0.0.1', got '$ip'") or exit;


    # only test this for Void, it will fail on real VMs
    return if $vm_name ne 'Void';

    $Ravada::CONFIG->{display_ip} = $DISPLAY_IP;
    eval { $display = $domain->display( user_admin ) };
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

    eval { $domain->prepare_base( user_admin ) };
    ok(!$@, $@) or exit;
    ok($domain->is_base);
    is($domain->is_active(),0);
    $domain->is_public(1);

    my @files_target = $domain->list_files_base_target();
    for (@files_target) {
        ok($_->[0]) or exit;
        ok($_->[1],"No target in $_->[0]") or exit;
    }

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
    eval { $domain->prepare_base( user_admin ) };
    like($@, qr'.');
    is($domain->is_base,1);

    # So we remove the base
    eval { $domain->remove_base( user_admin ) };
    is($@,'');
    is($domain->is_base,0);

    # And prepare again
    eval { $domain->prepare_base( user_admin ) };
    is($@,'');
    is($domain->is_base,1);

    my $name_clone = new_domain_name();

    my $domain_clone;
    eval { $domain_clone = $RVD_BACK->create_domain(
        name => $name_clone
        ,id_owner => user_admin->id
        ,id_base => $domain->id
        ,vm => $vm_name
        );
    };
    is($@, '');
    ok($domain_clone,"Trying to clone from ".$domain->name." to $name_clone");
    test_devices_clone($vm_name, $domain_clone);
    test_display($vm_name, $domain_clone);

    ok($domain_clone->id_base && $domain_clone->id_base == $domain->id
        ,"[$vm_name] Expecting id_base=".$domain->id." got ".($domain_clone->id_base or '<UNDEF>')) or exit;

    my $domain_clone2 = $RVD_FRONT->search_clone(
         id_base => $domain->id,
        id_owner => user_admin->id
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

    $domain_clone->remove( user_admin );

    eval { $domain->remove_base( user_admin ) };
    is($@,'');

    eval { $domain->prepare_base( user_admin ) };
    is($@,'');
    ok($domain->is_base,"[$vm_name] Expecting domain is_base=1 , got :".$domain->is_base);
    ok(!$@,"[$vm_name] Error preparing base after clone removed :'".($@ or '')."'");

    eval { $domain->start( user_admin )};
    like($@,qr/bases.*started/i);
    is($domain->is_active,0,"Expecting base domains can't be run");

    $domain->is_base(0);
    ok(!$domain->is_base,"[$vm_name] Expecting domain is_base=0 , got :".$domain->is_base);

    $domain->is_base(1);
    ok($domain->is_base,"[$vm_name] Expecting domain is_base=1 , got :".$domain->is_base);

}

sub test_prepare_base_with_cd {
    my $vm = shift;
    my $domain = create_domain($vm);
    my @volumes = $domain->list_volumes_info;
    my ($cd) = grep { $_->file =~ /\.iso$/ } @volumes;
    die "Expecting a CDROM\n".Dumper(@volumes) if !$cd;

    eval {
        $domain->prepare_base(user => user_admin, with_cd => 1);
    };
    is($@,'') or exit;

    my @volumes_base = $domain->list_files_base_target;
    my ($cd_base) = grep { $_->[0] =~ /\.iso$/ } @volumes_base;
    ok($cd_base,"Expecting a CD base ".Dumper(\@volumes_base)) or exit;

    my $clone = rvd_back->create_domain(
             name => new_domain_name
        , id_base => $domain->id
        ,id_owner => user_admin->id
    );
    my @volumes_clone = $clone->list_volumes_info;
    for my $vol (@volumes_clone) {
        like(ref $vol->domain, qr/^Ravada::Domain/);
        like(ref $vol->vm, qr/^Ravada::VM/);
    }

    my ($cd_clone ) = grep { defined $_->file && $_->file =~ /\.iso$/ } @volumes_clone;
    ok($cd_clone,"Expecting a CD in clone ".Dumper([ map { delete $_->{domain}; delete $_->{vm}; $_ } @volumes_clone])) or exit;
    is($cd_clone->info->{target}, $cd_base->[1]) or exit;

    $clone->remove(user_admin);
    $domain->remove(user_admin);
}
sub test_prepare_base_with_cd_req {
    my $vm = shift;
    my $domain = create_domain($vm);
    my @volumes = $domain->list_volumes_info;
    my ($cd) = grep { $_->file =~ /\.iso$/ } @volumes;
    die "Expecting a CDROM\n".Dumper(@volumes) if !$cd;

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    ok($domain_f->info(user_admin)->{cdrom}) or die Dumper($domain_f->info(user_admin)->{hardware}->{disk});
    like($domain_f->info(user_admin)->{cdrom}->[0],qr/\.iso$/) or die Dumper($domain_f->info(user_admin)->{hardware}->{disk});

    my $req = Ravada::Request->prepare_base(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,with_cd => 1
    );
    wait_request( debug => 0 );
    is($req->status, 'done');
    is($req->error, '');

    is($domain->is_base, 1);

    my @volumes_base = $domain->list_files_base_target;
    my ($cd_base) = grep { $_->[0] =~ /\.iso$/ } @volumes_base;
    ok($cd_base,"Expecting a CD base ".Dumper(\@volumes_base));

    my $clone = rvd_back->create_domain(
             name => new_domain_name
        , id_base => $domain->id
        ,id_owner => user_admin->id
    );
    my @volumes_clone = $clone->list_volumes_info;
    my ($cd_clone ) = grep {defined $_->file && $_->file =~ /\.iso$/ } @volumes_clone;
    ok($cd_clone,"Expecting a CD in clone ".Dumper([ map { delete $_->{domain}; delete $_->{vm} } @volumes_clone])) or exit;

    $clone->remove(user_admin);

    for my $vol ( @volumes_clone ) {
        if ($vol->file =~ /\.iso$/) {
            ok(-e $vol->file, $vol->file);
        } else {
            ok(!-e $vol->file, $vol->file);
        }
    }

    $domain->remove_base(user_admin);

    for my $volume ( @volumes_base ) {
        my $file = $volume->[0];
        die $file if $file !~ m{^[0-9a-z_/\-\.]+$}i;
        if ($file =~ /\.iso$/) {
            ok(-e $file, $file);
        } else {
            ok(!-e $file, $file);
        }
    }

    $domain->prepare_base(user => user_admin, with_cd => 1);
    my @volumes_base2 = $domain->list_files_base;
    ok(grep(/\.iso$/,@volumes_base2));

    for my $volume ( @volumes_base ) {
        my $file = $volume->[0];
        die $file if $file !~ m{^[0-9a-z_/\-\.]+$}i;
        if ($file =~ /\.iso$/) {
            ok(-e $file, "File shouldn't be removed : $file") or exit;
        } else {
            ok(-e $file, $file);
        }
    }


    $domain->remove(user_admin);

    for my $volume ( @volumes_base ) {
        my $file = $volume->[0];
        die $file if $file !~ m{^[0-9a-z_/\-\.]+$}i;
        if ($file =~ /\.iso$/) {
            ok(-e $file, "File shouldn't be removed : $file") or exit;
        } else {
            ok(!-e $file, $file);
        }
    }

}

sub test_clone_with_cd {
    my $vm = shift;
    my $domain = create_domain($vm);
    my @volumes = $domain->list_volumes_info;
    my ($cd) = grep { $_->file =~ /\.iso$/ } @volumes;
    die "Expecting a CDROM\n".Dumper(@volumes) if !$cd;

    my $clone = $domain->clone(
             name => new_domain_name
            ,user => user_admin
         ,with_cd => 1
    );

    my @volumes_base = $domain->list_files_base_target;
    my ($cd_base) = grep { $_->[0] =~ /\.iso$/ } @volumes_base;
    ok($cd_base,"Expecting a CD base ".Dumper(\@volumes_base));

    my @volumes_clone = $clone->list_volumes_info;
    my ($cd_clone ) = grep { defined $_->file && $_->file =~ /\.iso$/ } @volumes_clone;
    ok($cd_clone,"Expecting a CD in clone ".Dumper([ map { delete $_->{domain}; delete $_->{vm}; $_ } @volumes_clone])) or exit;

}

sub test_clone_with_cd_req {
    my $vm = shift;
    my $domain = create_domain($vm);
    my @volumes = $domain->list_volumes_info;
    my ($cd) = grep { $_->file =~ /\.iso$/ } @volumes;
    die "Expecting a CDROM\n".Dumper(@volumes) if !$cd;

    my $clone_name = new_domain_name();
    my $req = Ravada::Request->clone(
            id_domain => $domain->id
             ,with_cd => 1
                ,name => $clone_name
                 ,uid => user_admin->id
    );
    wait_request(debug => 0);
    is($domain->is_base,1);
    is($req->status, 'done');
    is($req->error,'');

    my @volumes_base = $domain->list_files_base_target;
    my ($cd_base) = grep { $_->[0] =~ /\.iso$/ } @volumes_base;
    ok($cd_base,"Expecting a CD base ".Dumper(\@volumes_base));

    my $clone = rvd_back->search_domain($clone_name);
    my @volumes_clone = $clone->list_volumes_info;
    my ($cd_clone ) = grep { $_->file =~ /\.iso$/ } @volumes_clone;
    ok($cd_clone,"Expecting a CD in clone ".Dumper(\@volumes_clone));

}

sub test_prepare_base_active {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);

    ok(!$domain->is_base,"Domain ".$domain->name." should not be base") or return;
    eval { $domain->start( user_admin ) if !$domain->is_active() };
    ok(!$@,$@) or exit;
    eval { $domain->resume( user_admin )  if $domain->is_paused()  };
    ok(!$@,$@);

    ok($domain->is_active,"[$vm_name] Domain ".$domain->name." should be active") or return;
    ok(!$domain->is_paused,"[$vm_name] Domain ".$domain->name." should not be paused") or return;

    eval{ $domain->prepare_base( user_admin ) };
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

    $domain->prepare_base( user_admin );
    ok($domain->is_base,"Domain ".$domain->name." should be base") or return;

    my @files = $domain->list_files_base();
    ok(scalar @files,"Expecting files base, got ".Dumper(\@files)) or return;

    $domain->remove_base( user_admin );
    ok(!$domain->is_base,"Domain ".$domain->name." should be base") or return;

    for my $file (@files) {
        die $file if $file !~ m{^[0-9a-z_/\-\.]+$};
        if ($file =~ /\.iso$/) {
            ok(-e $file,"Expecting file base '$file' removed" );
        } else {
            ok(!-e $file,"Expecting file base '$file' removed" );
        }
    }

    my @files_deleted = $domain->list_files_base();
    is(scalar @files_deleted,0);

    my $sth = connector->dbh->prepare(
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
    $domain->prepare_base( user_admin );
    ok($domain->is_base,"[$vm_name] expecting domain is base, got "
                        .$domain->is_base);

    my @files = $domain->list_files_base();

    my $name_clone = new_domain_name();

    $domain->is_public(1);
    is($domain->is_base(), 1);
    my $clone = rvd_back()->create_domain( name => $name_clone
            ,id_owner => user_admin->id
            ,id_base => $domain->id
            ,vm => $vm_name
    );
    is($@, '');
    ok($clone,"[$vm_name] Expecting clone created");
    eval {$domain->remove_base( user_admin )};
    ok($@,"Expecting error removing base with clones, got '$@'");
    ok($domain->is_base,"[$vm_name] expecting domain is base, got "
                        .$domain->is_base);
    for my $file (@files) {
        die $file if $file !~ m{^[0-9a-z_/\-\.]+$}i;
        ok(-e $file,"[$vm_name] Expecting file base '$file' not removed" );
    }

    ##################################################################3
    # now we remove the clone, it should work

    $clone->remove( user_admin );

    eval {$domain->remove_base( user_admin )};
    ok(!$@,"Expecting not error removing base with clones, got '$@'");
    ok(!$domain->is_base,"[$vm_name] expecting domain is base, got "
                        .$domain->is_base);
    for my $file (@files) {
        die $file if $file !~ m{^[0-9a-z_/\-\.]+$}i;
        if ($file =~ /\.iso$/) {
            ok(-e $file,"[$vm_name] Expecting file base '$file' not removed" );
        } else {
            ok(!-e $file,"[$vm_name] Expecting file base '$file' removed" );
        }

    }

}

sub test_spinned_off_base {
    my $vm_name = shift;

    my $base= test_create_domain($vm_name);
    $base->prepare_base( user_admin );
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

    $clone->spinoff();
    $clone->prepare_base(user_admin);

    $base->remove_base(user_admin());
    # Base can get started now the clones are released
    eval { $base->start(user => user_admin ) };
    is($@,'');
    is($base->is_active,1);

    $base->shutdown_now( user_admin );
    is($base->is_active,0);

    $clone->remove_base(user_admin);

    # Base can get started now the clones are released even though they are not base
    eval { $base->start(user => user_admin ) };
    is($@,'');
    is($base->is_active,1);

    $clone->remove( $USER );
    $base->remove( user_admin );
}


sub test_private_base {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $domain = test_create_domain($vm_name);
    $domain->prepare_base( user_admin );
    is($domain->is_public, 0 );

    my $clone_name = new_domain_name();

    my $clone;
    # admin can clone
    eval { $clone = $domain->clone(user => user_admin, name => $clone_name); };
    is($@,'');

    my $clone2 = $vm->search_domain($clone_name);
    ok($clone2,"Expecting a clone");
    $clone->remove(user_admin)  if $clone;

    # when is public, any can clone
    $domain->is_public(1);
    eval { $clone = $domain->clone(user => $USER, name => $clone_name); };
    is($@,'');

    $clone2 = $vm->search_domain($clone_name);
    ok($clone2,"Expecting a clone");
    $clone->remove(user_admin)  if $clone;

}
sub test_domain_limit_admin {
    my $vm_name = shift;

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }

    my $domain = create_domain($vm_name, user_admin );
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now(user_admin)    if $domain->is_active;

    is(rvd_back->list_domains(user => user_admin , active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start( user_admin );
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => user_admin , active => 1),1);

    my $domain2 = create_domain($vm_name, user_admin );
    $domain2->shutdown_now( user_admin )   if $domain2->is_active;
    is(rvd_back->list_domains(user => user_admin , active => 1),1);

    $domain2->start( user_admin );
    my $req = Ravada::Request->enforce_limits(timeout => 1);
    rvd_back->_process_all_requests_dont_fork();
    sleep 1;
    rvd_back->_process_all_requests_dont_fork();
    my @list = rvd_back->list_domains(user => user_admin, active => 1);
    is(scalar @list,2) or die Dumper([map { $_->name } @list]);
}


sub test_domain_limit_noadmin {
    my $vm_name = shift;
    my $user = $USER;
    user_admin->grant($user,'create_machine');
    is($user->is_admin,0);

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $domain = create_domain($vm_name, $user);
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now($USER)    if $domain->is_active;

    is(rvd_back->list_domains(user => $user, active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start( $user);
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->shutdown_now( $user )   if $domain2->is_active;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    $domain2->start( $user );
    my $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    rvd_back->_process_all_requests_dont_fork();
    sleep 1;
    rvd_back->_process_all_requests_dont_fork();
    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1) or die Dumper(\@list);
    is($list[0]->name, $domain2->name) if $list[0];

    $domain->remove(user_admin);
    $domain2->remove(user_admin);
}

sub test_domain_limit_allowed {
    my $vm_name = shift;
    my $user = $USER;
    user_admin->grant($user,'create_machine');
    user_admin->grant($user,'start_many');
    is($user->is_admin,0);

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $domain = create_domain($vm_name, $user);
    ok($domain,"Expecting a new domain created") or exit;
    $domain->shutdown_now($USER)    if $domain->is_active;

    is(rvd_back->list_domains(user => $user, active => 1),0
        ,Dumper(rvd_back->list_domains())) or exit;

    $domain->start( $user);
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->shutdown_now( $user )   if $domain2->is_active;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    $domain2->start( $user );
    my $req = Ravada::Request->enforce_limits(timeout => 1);
    rvd_back->_process_all_requests_dont_fork();
    sleep 1;
    rvd_back->_process_all_requests_dont_fork();
    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,2) or die Dumper([ map { $_->name } @list]);

    user_admin->revoke($user,'start_many');
    is($user->can_start_many,0) or exit;

    $req = Ravada::Request->enforce_limits(timeout => 1,_force => 1);
    rvd_back->_process_all_requests_dont_fork();
    sleep 1;
    rvd_back->_process_all_requests_dont_fork();
    @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1,"[$vm_name] expecting 1 active domain")
        or die Dumper([ map { $_->name } @list]);
 
    $domain->remove(user_admin);
    $domain2->remove(user_admin);
}


sub test_domain_limit_already_requested {
    my $vm_name = shift;

    for my $domain ( rvd_back->list_domains()) {
        $domain->shutdown_now(user_admin);
    }
    my $user = create_user("limit$$","bar");
    user_admin->grant($user, 'create_machine');
    my $domain = create_domain($vm_name, $user);
    ok($domain,"Expecting a new domain created") or return;
    $domain->shutdown_now($user)    if $domain->is_active;

    is(rvd_back->list_domains(user => $USER, active => 1),0
        ,Dumper(rvd_back->list_domains())) or return;

    $domain->start( $user );
    is($domain->is_active,1);

    ok($domain->start_time <= time,"Expecting start time <= ".time
                                    ." got ".time);

    sleep 1;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    my $domain2 = create_domain($vm_name, $user);
    $domain2->shutdown_now($USER)   if $domain2->is_active;
    is(rvd_back->list_domains(user => $user, active => 1),1);

    $domain2->start( $user );
    my @list_requests = grep { $_->command ne 'set_time'} $domain->list_requests;
    is(scalar @list_requests,0,"Expecting 0 requests ".Dumper(\@list_requests));

    is(rvd_back->list_domains(user => $user, active => 1),2);
    my $req = Ravada::Request->enforce_limits(timeout => 1, _force => 1);
    rvd_back->_process_all_requests_dont_fork();

    is($req->status,'done');
    is($req->error, '');

    my @list = rvd_back->list_domains(user => $user, active => 1);
    is(scalar @list,1) or die Dumper([ map { $_->name } @list]);
    is($list[0]->name, $domain2->name) if $list[0];

    $domain2->remove($user);
    $domain->remove($user);

    $user->remove();
}

sub test_prepare_fail($vm) {
    my $domain = create_domain($vm,undef,undef,1);
    my @volumes = $domain->list_volumes_info();
    is(scalar @volumes,3);
    for (@volumes) {
        next if $_->file =~ /\.iso$/;
        like($_->file,qr(-vd[a-c]-)) or exit;
    }
    for my $vol ( @volumes ) {
        next if $vol->file =~ /\.iso$/;
        my $base_file = $vol->base_filename();
        open my $out , '>',$base_file;
        close $out;
    }
    eval {
        $domain->prepare_base(user_admin);
    };
    like($@,qr/already exists/);
    is($domain->is_base,0) or exit;
    for my $vol ( @volumes ) {
        my $backing_file;
        eval { $backing_file = $vol->backing_file };
        is($backing_file,undef) if $vol->file =~ /\.iso/;
        like($@,qr/./, $vol->file) if $@;
    }

    # Now we only have the second file already there
    my $base_file = $volumes[0]->base_filename();
    unlink $base_file;

    eval {
        $domain->prepare_base(user_admin);
    };
    like($@,qr/already exists/);
    for my $vol ( @volumes ) {
        my $backing_file = $vol->backing_file;
        is($backing_file,undef);
    }


    $domain->remove(user_admin);
}

sub test_prepare_chained($vm) {
    my $domain = create_domain($vm);
    my $clone = $domain->clone(name => new_domain_name()
        , user => user_admin
    );
    $clone->prepare_base(user_admin);
    is($clone->id_base, $domain->id);
    is($clone->is_base, 1);

    my $clone2 = $clone->clone(name => new_domain_name()
        , user => user_admin
    );
    is($clone->id_base, $domain->id);
    is($clone->is_base, 1);
    is($clone2->id_base, $clone->id);

    my %files_base = map { $_ => 1 } $domain->list_files_base();
    for my $file ( $clone->list_files_base() ) {
        ok(!exists $files_base{$file},"Expecting $file not in base ".$domain->name) or exit;
        unlike($file,qr/--+/);
    }

    $clone2->spinoff();
    for my $vol ($clone2->list_volumes_info) {
        ok(!$vol->backing_file
            ,"Expecting no backing file for ".( $vol->file or "<UNDEF>")." in ".$clone2->name);
    }
    $clone2->remove(user_admin);
    $clone->remove(user_admin);
    $domain->remove(user_admin);

}

#######################################################################33


remove_old_domains();
remove_old_disks();

for my $vm_name ( vm_names() ) {

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

        test_prepare_chained($vm);
        test_prepare_fail($vm);

        test_domain_limit_already_requested($vm_name);

        test_prepare_base_with_cd($vm);
        test_clone_with_cd($vm);

        test_prepare_base_with_cd_req($vm);
        test_clone_with_cd_req($vm);

        my $domain = test_create_domain($vm_name);
        test_prepare_base($vm_name, $domain);
        test_prepare_base_active($vm_name);
        test_remove_base($vm_name);
        test_dont_remove_base_cloned($vm_name);

        test_private_base($vm_name);

        test_spinned_off_base($vm_name);
        test_domain_limit_admin($vm_name);
        test_domain_limit_noadmin($vm_name);
        test_domain_limit_allowed($vm_name);


        $domain->remove( user_admin );
        $domain = undef;

        my $domain2 = test_create_domain_swap($vm_name);
        test_prepare_base($vm_name, $domain2 , 2);
        $domain2->remove( user_admin );

        $domain2 = test_create_domain_swap($vm_name);
        $domain2->start( user_admin );
        $domain2->shutdown_now( user_admin );
        test_prepare_base($vm_name, $domain2 , 2);
        $domain2->remove( user_admin );

    }
}

end();
done_testing();
