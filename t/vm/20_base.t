use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Mojo::JSON qw(decode_json);
use XML::LibXML;
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
my $BASE;

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

sub test_display_inactive($domain) {
    my $info = $domain->info(user_admin);
    ok(!exists $info->{display});

    my $display_h = $info->{hardware}->{display};
    isa_ok($display_h,'ARRAY') or die Dumper($info);
    is(scalar(@$display_h),1) or die Dumper($display_h);

    # the very first time it starts default display is fetched
    $domain->start(user_admin);
    my $display_up = $domain->info(user_admin)->{display};
    $domain->shutdown_now(user_admin);

    $info = $domain->info(user_admin);

    $display_h = $info->{hardware}->{display};
    isa_ok($display_h,'ARRAY') or die Dumper($info);
    is(scalar(@$display_h),1) or die Dumper($display_h);

    return $display_up;
}

sub test_display_removed_void($domain) {
    my $hardware= $domain->_value('hardware');
    is_deeply($hardware->{display},[]) or die Dumper($hardware->{display});
}

sub test_display_removed_kvm($domain) {
    my $doc = XML::LibXML->load_xml(string => $domain->domain->get_xml_description );
    my @display = $doc->findnodes("/domain/devices/graphics");
    is(scalar(@display),0) or die Dumper([map { $_->getAttribute('type') } @display ]);

}

sub test_display_removed($domain) {
    if ($domain->type eq 'KVM') {
        test_display_removed_kvm($domain);
    } elsif($domain->type eq 'Void') {
        test_display_removed_void($domain);
    } else {
        confess "I don't know how to test display removed for ".$domain->type;
    }
    my @ports = $domain->list_ports();
    is(scalar(@ports),0) or die Dumper(\@ports);

    my $sth = $domain->_dbh->prepare("SELECT * FROM domain_displays WHERE id_domain=?");
    $sth->execute($domain->id);
    my @displays;
    while ( my $row = $sth->fetchrow_hashref) {
        push @displays,($row);
    }
    is(scalar(@displays),0) or die Dumper(\@displays);
}

sub test_remove_display($vm) {
    my $domain = create_domain($vm);
    ok($domain->_has_builtin_display) or die $domain->name;
    my $display0 = $domain->info(user_admin)->{hardware}->{display};
    is(scalar(@$display0),1) or die $domain->name." ".Dumper($display0);
    my $req = Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,index => 0
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'') or exit;

    is($domain->_has_builtin_display,0 ) or die $domain->name;

    test_display_removed($domain);
    my $display = $domain->info(user_admin)->{hardware}->{display};
    is_deeply($display,[]) or die Dumper($display);

    $domain->remove(user_admin);
}

sub test_add_display_builtin($vm) {
    my $domain = create_domain($vm);
    my $req2 = Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,index => 0
    );

    wait_request();
    my $info = $domain->info(user_admin);
    ok(!exists $info->{display});
    is($domain->_has_builtin_display(),0) or die $domain->name;

    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,data => { driver => 'spice' }
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'');

    ok($domain->display_info(user_admin));
    is($domain->_has_builtin_display(),1) or die $domain->name;

    $domain->start(user_admin);
    $info = $domain->info(user_admin);
    ok($info->{display}) or die $domain->name;

    test_displays_added_on_refresh($domain,1);

    $domain->remove(user_admin);
}

sub test_add_display($vm) {
    my $domain = create_domain($vm);
    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,data => { driver => 'ssh' , port => 22 }
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'') or exit;

    is($domain->_has_builtin_display,1 ) or die $domain->name;

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    is($domain_f->_has_builtin_display,1 ) or die $domain->name;

    my $display = $domain->info(user_admin)->{hardware}->{display};
    is(scalar(@$display),2);
    is($display->[0]->{is_builtin},1);
    is($display->[1]->{is_builtin},0);

    $domain->start(user_admin);

    my $display_info = $domain->info(user_admin)->{display};

    ok($display_info);
    is($display_info->{is_builtin},1);

    $domain->shutdown_now(user_admin);
    my $req2 = Ravada::Request->remove_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,index => 0
    );
    wait_request(debug => 0);
    is($req2->status,'done');
    is($req2->error,'') or exit;

    is($domain->_has_builtin_display,0 ) or die $domain->name;
    $domain_f = Ravada::Front::Domain->open($domain->id);
    is($domain_f->_has_builtin_display,0 ) or die $domain->name;

    $domain->start(user_admin);
    my $info2 = $domain->info(user_admin);
    ok(!exists $info2->{display});

    test_displays_added_on_refresh($domain, 0);

    $domain->remove(user_admin);

}

sub test_displays_added_on_refresh($domain, $n_expected, $req_refresh=1) {

    my $sth_count = $domain->_dbh->prepare(
        "SELECT count(*) FROM domain_displays WHERE id_domain=?");
    $sth_count->execute($domain->id);
    my ($count0) = $sth_count->fetchrow;
    #    is($count0, $n_expected,"Expecting displays on table domain_displays");

    if ($req_refresh) {
        my $sth = $domain->_dbh->prepare("DELETE FROM domain_displays WHERE id_domain=?");
        $sth->execute($domain->id);
        my $req = Ravada::Request->refresh_machine(
            uid => user_admin->id
            ,id_domain => $domain->id
        );

        wait_request(debug => 0);
    }
    $sth_count->execute($domain->id);
    my ($count) = $sth_count->fetchrow;
    is($count, $n_expected,"Expecting displays on table domain_displays for ".$domain->name);

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    my $display = $domain_f->info(user_admin)->{hardware}->{display};
    is(scalar(@$display), $n_expected,"Expecting $n_expected displays on info->{hardware}->{display} in ".$domain->name) or confess Dumper($display);

}

sub test_display_iptables($vm) {
    return if $<;

    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    _add_all_displays($domain);

    flush_rules();
    $domain->start(
        user => user_admin
        ,remote_ip => '1.2.3.4'
    );
    wait_request(debug => 0, skip => [ 'set_time', 'refresh_machine_ports']);
    my $info = $domain->info(user_admin);

    my ($out_iptables_all, $err0) = $vm->run_command("iptables-save");
    my @iptables_all = split (/\n/,$out_iptables_all);
    my ($out_iptables, $err) = $vm->run_command("iptables-save","-t","nat");
    my @iptables = split (/\n/,$out_iptables);

    my %dupe_port;
    my @displays = @{$domain->info(user_admin)->{hardware}->{display}};
    for my $display ( @displays ) {
        for my $port ( $display->{port}, $display->{extra}->{tls_port} ) {
            next if !defined $port;
            ok(!$dupe_port{$port}," port $port duplicated $display->{driver} and "
                .($dupe_port{$port} or ''));
            $dupe_port{$port} = $display->{driver};
            my $display_ip = $display->{ip};
            ok(grep /--dport $port/,@iptables_all, "Expecting --dport $port ".Dumper(\@iptables_all)) or die $domain->name;
            if ($display->{is_builtin}) {
                ok(search_iptable_remote(local_ip => $display_ip, local_port => $port
                        , node => $vm),"Expecting iptables rule for"
                    ." $display->{driver} ->  $display->{ip} : $port");
            } else {
                ok(grep /^-A PREROUTING -d $display_ip\/.* --dport $port -j DNAT/,@iptables)
                    or die Dumper(\@iptables);
            }
        }
    }
    $domain->remove(user_admin);
    wait_request(debug => 1);
    ($out_iptables, $err) = $vm->run_command("iptables-save");
    @iptables = split (/\n/,$out_iptables);
    for my $display ( @displays ) {
        for my $port ( $display->{port}, $display->{extra}->{tls_port} ) {
            next if !defined $port;
            my @found = grep /--dport $port/, @iptables;
            is(scalar(@found),0,"expecting no --dport $port after removing ".$domain->name)
                or die Dumper(\@found,\@iptables);
            my $display_ip = $display->{ip};
            if ($display->{is_builtin}) {
                ok(!search_iptable_remote(local_ip => $display_ip, local_port => $port
                        , node => $vm),"Expecting iptables rule for"
                    ." $display->{driver} ->  $display->{ip} : $port");
            } else {
                ok(!grep /^-A PREROUTING -d $display_ip\/.* --dport $port -j DNAT/,@iptables)
                    or die Dumper(\@iptables);
            }
        }
    }
}

sub _add_all_displays($domain) {
    my $info = $domain->info(user_admin);
    my $options = $info->{drivers}->{display};
    for my $driver (@$options) {
        next if grep { $_->{driver} eq $driver } @{$info->{hardware}->{display}};

        my $req = Ravada::Request->add_hardware(
            uid => user_admin->id
            , id_domain => $domain->id
            , name => 'display'
            , data => { driver => $driver }
        );
    }
    wait_request();

}

sub test_display_info($vm) {
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    my $domain_f = Ravada::Front::Domain->open($domain->id);

    test_display_inactive($domain);

    $domain->start(user => user_admin, remote_ip => '1.2.3.4');
    my $display = $domain->info(user_admin)->{display};
    ok($display->{port}) or die $domain->name;
    my $info = $domain_f->info(user_admin);

    my $display_h = $info->{hardware}->{display};
    isa_ok($display_h,'ARRAY') or die Dumper($info);
    is(scalar(@$display_h),1) or die Dumper($display_h);
    is($display_h->[0]->{is_active},1) or die $domain->name;

    is($display_h->[0]->{file_extension},'vv') or die $domain->name
    if $vm->type eq 'KVM';

    delete $display_h->[0]->{id};
    delete $display_h->[0]->{id_domain_port};
    delete $display_h->[0]->{file_extension};

    $domain->_normalize_display($display,0);
    _test_compare($display_h->[0], $display) or exit;

    my $port = 356;
    my @display_args = (
        id_domain => $domain->id
        ,uid => user_admin->id
        ,name => 'display'
        ,data => {
            driver => 'rdp'
        }
    );
    my $req1 = Ravada::Request->add_hardware(@display_args);
    wait_request();
    is($req1->status,'done');
    is($req1->error,'');

    # if we try again it must fail , duplicated
    my $req2 = Ravada::Request->add_hardware(@display_args);
    wait_request(check_error => 0);
    is($req2->status,'done');
    like($req2->error,qr'.');

    my $exposed_port = $domain->exposed_port($port);
    ok($exposed_port,"Expecting exposed port $port") or exit;
    is($exposed_port->{restricted},1);
    is($exposed_port->{name},'rdp');

    ok($domain_f->_has_builtin_display) or die $domain->name;

    $info = $domain_f->info(user_admin);
    $display = $info->{display};
    isa_ok($display,'HASH') or die Dumper($info);
    $display_h = $info->{hardware}->{display};
    isa_ok($display_h,'ARRAY') or die Dumper($info->{hardware});
    is(scalar(@$display_h),2);
    $domain->_normalize_display($display,0);
    is($display_h->[0]->{id_domain_port},undef); # spice needs no exposed port
    delete $display_h->[0]->{id_domain_port};
    is($display_h->[0]->{is_active}, 1);
    delete $display_h->[0]->{is_active};
    delete $display_h->[0]->{file_extension};
    _test_compare($display_h->[0], $display) or exit;

    is($display_h->[0]->{driver}, 'spice') if $domain->type eq 'KVM';
    like($display_h->[0]->{password},qr{..+}) if $domain->type eq 'KVM';
    is($display_h->[0]->{id_exposed_port},undef); # spice doesn't need exposed port

    # rdp won't be active because that port isn't up yet
    is($display_h->[1]->{is_active}, 0) or die Dumper($display_h);
    is($display_h->[1]->{driver}, 'rdp');
    like($display_h->[1]->{port}, qr/^\d+/);
    isnt($display_h->[1]->{port}, $port) or die Dumper($display_h);
    is($display_h->[1]->{ip}, $display_h->[0]->{ip}) or exit;
    is($display_h->[1]->{listen_ip}, $display_h->[0]->{listen_ip});
    is($display_h->[1]->{id_domain_port},$exposed_port->{id}); # rdp needs exposed port
    $domain->shutdown_now(user_admin());

    $domain_f = Ravada::Front::Domain->open($domain->id);
    $domain->info(user_admin);
    $info = $domain_f->info(user_admin);
    $display_h = $info->{hardware}->{display};
    is($display_h->[0]->{is_active}, 0);
    is($display_h->[1]->{is_active}, 0) or exit;

    $domain->prepare_base(user_admin);

    my $clone = $domain->clone(name => new_domain_name
        ,user => user_admin
    );
    Ravada::Request->start_domain(uid => user_admin->id, id_domain => $clone->id
    ,remote_ip => '1.2.3.4');
    wait_request(debug => 0);
    my $info_c = $clone->info(user_admin);
    my $clone_h = Ravada::Front::Domain->open($clone->id);
    my $display_c = $clone_h->info(user_admin)->{hardware}->{display};
    isnt($display_c->[0]->{password}, $display_h->[0]->{password})
    if $display_h->[0]->{password};

    like($display_c->[1]->{id_domain_port},qr/^\d+$/);
    isnt($display_c->[1]->{id_domain_port},$display_h->[1]->{id_domain_port});

    delete $display_c->[0]->{password};
    delete $display_h->[0]->{password};

    isnt($display_c->[1]->{port}, $display_h->[1]->{port});
    for my $field (qw(display port is_active)) {
        for ( 0 .. 1 ) {
            delete $display_c->[$_]->{$field};
            delete $display_h->[$_]->{$field};
        }
    }

    _test_display_tls($display_c->[0], $vm);
    delete $display_c->[0]->{tls_port};
    delete $display_c->[0]->{extra}->{tls_port};
    delete $display_c->[0]->{file_extension};
    #    _test_compare_list($display_c, $display_h, $clone);

    test_iptables($clone);

    test_refresh_old_machine($clone);
    test_update_display($clone);

    $clone->remove(user_admin);
    $domain->remove(user_admin());

    test_display_clean($domain->id, $clone->id);
}

sub _test_display_tls($display, $vm) {
    return if $display->{driver} ne 'spice';
    SKIP: {
        skip("Missing TLS configuration see https://ravada.readthedocs.io/en/latest/docs/spice_tls.html",1) if !check_libvirt_tls();;
        my $tls_port = $display->{extra}->{tls_port};
        like($tls_port,qr/^\d+$/);

        my $tls_json = $vm->_data('tls');
        my $tls;
        eval { $tls = decode_json($tls_json) if $tls_json };
        is($@, '', $tls_json." in ".$vm->name);
        isa_ok($tls, 'HASH');
        ok($tls->{subject},Dumper($tls)) or die;
        ok($tls->{ca}, Dumper($tls));
        is($tls->{subject}, $vm->tls_host_subject());
        is($tls->{ca}, $vm->tls_ca());

        ok(search_iptable_remote(local_ip => $display->{ip}, local_port => $tls_port, node => $vm),"Expecting iptables rule for -> $display->{ip} : $tls_port");
    };
}

sub _get_internal_port_display_kvm($domain) {
    my $doc = XML::LibXML->load_xml(string => $domain->xml_description());
    my $path = "/domain/devices/graphics";
    my ($graphics) = $doc->findnodes($path);
    die "Error: no $path in ".$domain->name if !$graphics;
    return $graphics->getAttribute('port');
}

sub _get_internal_port_display_void($domain) {
    my $data = $domain->_value('hardware');
    return $data->{display}->[0]->{port};
}

sub _get_internal_port_display($domain) {
    confess "Error: domain ".$domain->name." should be up to get internal port display"
    if !$domain->is_active();

    return _get_internal_port_display_kvm($domain) if $domain->type eq 'KVM';
    return _get_internal_port_display_void($domain) if $domain->type eq 'Void';
    die "I don't know how to get internal display port for ".$domain->type;
}

sub test_iptables($domain) {
    return if $>;
    my ($iptables, $err) = $domain->_vm->run_command("/usr/sbin/iptables-save");
    my @iptables = split /\n/,$iptables;
    my ($display_builtin, $display_exp) = @{$domain->info(user_admin)->{hardware}->{display}};
    my $internal_port = _get_internal_port_display($domain);
    my $port_builtin = $display_builtin->{port};

    is($internal_port, $port_builtin) or confess;
    my @iptables_builtin = grep { /^-A.*--dport $port_builtin -j ACCEPT/ } @iptables;
    is(scalar(@iptables_builtin),1,"Expecting one entry with $port_builtin, got "
    .scalar(@iptables_builtin)) or do {
        confess Dumper(\@iptables) if !scalar(@iptables_builtin);
        confess Dumper(\@iptables_builtin);
    };

    my $port_rdp = $display_exp->{port};
    my @iptables_rdp = grep { /^-A PREROUTING.*--dport $port_rdp -j DNAT .*356/ } @iptables;
    is(scalar(@iptables_rdp),1,"Expecting one entry with $port_rdp, got "
    .scalar(@iptables_rdp)) or do {
        die Dumper(\@iptables) if !scalar(@iptables_rdp);
        die Dumper(\@iptables_rdp);
    };


}

sub test_update_display($clone) {
    $clone->_store_display({ driver => 'bogus' });
    $clone->_store_display({ driver => 'bogus 2' });
}

sub test_refresh_old_machine($clone) {
    $clone->shutdown_now(user_admin);
    my $sth = connector->dbh->prepare("DELETE FROM domain_displays WHERE id_domain=?");
    $sth->execute($clone->id);
    my $req = Ravada::Request->refresh_machine(uid => user_admin->id
        ,id_domain => $clone->id);
    wait_request(debug => 0);

    is($req->status,'done');
    is($req->error,'');

    $sth = connector->dbh->prepare("SELECT * FROM domain_displays WHERE id_domain=?");
    $sth->execute($clone->id);
    my $row = $sth->fetchrow_hashref;
    ok($row);

    my $clone_f = Ravada::Front::Domain->open($clone->id);
    my $info = $clone_f->info(user_admin);
    ok(scalar(@{$info->{hardware}->{display}}));

}

sub test_display_clean(@id) {
    for my $id ( @id ) {
        for my $table ('domain_displays', 'domain_ports') {
            my $sth = connector->dbh->prepare("SELECT * FROM $table"
                ." WHERE id_domain=?"
            );
            $sth->execute($id);
            my $row = $sth->fetchrow_hashref;
            ok(!$row,Dumper($table, $row));
        }
    }
}

sub _test_compare($display1, $display2) {
    my %display1b = %$display1;
    my %display2b = %$display2;
    delete $display1b{id};

    delete $display1b{id_domain}
    if !exists $display2b{id_domain};

    delete %display1b{'n_order','display'};
    delete %display2b{'n_order','display'};

    is_deeply(\%display1b, \%display2b) or confess;
}

sub _test_compare_list($display1, $display2, $domain=undef) {
    for my $d (@$display1,@$display2) {
        delete $d->{id};
        delete $d->{id_domain};
        delete $d->{n_order};
    }
    is_deeply($display1, $display2) or confess $domain->name;
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

    $clone->remove(user_admin);
    $domain->remove(user_admin);
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

    $clone->remove(user_admin);
    $domain->remove(user_admin);
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
    $domain->remove(user_admin);
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

    $domain->remove(user_admin);
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
    eval { $clone = $domain->clone(user => $USER, name => $clone_name); };
    like($@,qr(private)) or exit;

    my $clone2 = $vm->search_domain($clone_name);
    ok(!$clone2,"Expecting no clone");
    $clone2->remove(user_admin) if $clone2;

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

    $domain2->remove(user_admin);
    $domain->remove(user_admin);
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
    my $domain = create_domain($vm,user_admin,'Alpine',1);
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

sub test_change_display_settings($vm) {
    my $domain = create_domain($vm);
    if ($vm->type eq 'Void') {
        test_change_display_settings_kvm($domain);
    } elsif ($vm->type eq 'KVM') {
        test_change_display_settings_kvm($domain);
    }
    $domain->remove(user_admin);
}

sub test_change_display_settings_kvm($domain) {
    $domain->start(user_admin);
    my $display = $domain->info(user_admin)->{display};
    $domain->shutdown_now(user_admin);

    my @display = $domain->_get_controller_display();
    isa_ok($display[0]->{extra},'HASH') or exit;
    ok($display[0]->{driver}) or die Dumper($display[0]);
    ok($domain->_is_display_builtin($display[0]->{driver})) or exit;

    for my $driver_name (qw(image jpeg zlib playback streaming)) {
        my $driver = $domain->drivers($driver_name);
        die "Error: missing driver $driver_name" if !defined $driver;
        my @options = $driver->get_options;
        die "Error: no options for driver $driver_name" if !scalar(@options);
        for my $option ( @options ) {
            my $req = Ravada::Request->change_hardware(
                uid => user_admin->id
                ,id_domain => $domain->id
                ,hardware => 'display'
                ,data => { $driver_name => $option->{value} , driver => $display->{driver} }
                ,index => 0
            );
            wait_request(debug => 0);
            is($req->status, 'done');
            is($req->error,'') or exit;
            my @display = $domain->_get_controller_display();
            is($display[0]->{extra}->{$driver_name}, $option->{value}, $driver_name)
                or die Dumper( $domain->name , $display[0]);
        }
    }
}

sub test_exposed_port($domain, $driver) {
    $domain->start(user_admin);
    my @ports = $domain->list_ports();
    $driver = 'rdp' if $driver =~ /rdp/i;
    my $port = grep { $_->{name} eq $driver } @ports;
    if ( $domain->_is_display_builtin($driver) ) {
        ok(!$port) or die Dumper($port);
    } else {
        ok($port,"Expecting exposed port for $driver") or die Dumper(\@ports);
    }
    $domain->shutdown_now(user_admin);
}

sub test_display_drivers($vm, $remove) {
    my $domain = $BASE->clone(name => new_domain_name(), user => user_admin);

    for ( 0 .. scalar($domain->_get_controller_display())-1) {
        Ravada::Request->remove_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,name => 'display'
            ,index => 0
        );
    }
    wait_request(debug => 0);
    my $n_displays=0;
    for my $driver ( @{$domain->info(user_admin)->{drivers}->{display}} ) {
        my $req = Ravada::Request->add_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,name => 'display'
            ,data => { driver => $driver }
        );
        wait_request(debug => 0);
        is($req->status, 'done');
        is($req->error, '');
        $n_displays++;
        test_displays_added_on_refresh($domain, $n_displays, 0);

        test_exposed_port($domain, $driver);

        $req->status('requested');

        wait_request(debug => 0, check_error => 0);
        is($req->status, 'done');
        like($req->error, qr/uplicate|already exported/i);

        test_displays_added_on_refresh($domain, $n_displays, 0);

        $domain->start(user => user_admin, remote_ip => '1.2.3.5');
        wait_request(debug => 0);
        $domain->shutdown(user => user_admin, timeout => 10);
        if ($remove) {
            Ravada::Request->remove_hardware(
                uid => user_admin->id
                ,id_domain => $domain->id
                ,name => 'display'
                ,index => 0
            );
            $n_displays--;
            wait_request(debug => 0);
        }
    }
    my $displays0 = $domain->info(user_admin)->{hardware}->{display};
    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,data => { driver => 'fail'}
    );
    wait_request(debug => 0, check_error => 0);
    is($req->status, 'done');
    like($req->error, qr/unknown/i);

    my $displays1 = $domain->info(user_admin)->{hardware}->{display};
    is(scalar(@$displays1),scalar(@$displays0)) or exit;

    $domain->remove(user_admin);
}

sub test_display_port_already_used($vm) {
    my $domain = create_domain($vm);
    $domain->expose( port => 22 );
    my $req = Ravada::Request->add_hardware(
          uid => user_admin->id
        ,name => 'display'
        ,data => { driver => 'x2go' }
        ,id_domain =>$domain->id
    );
    wait_request(check_error => 0);
    is($req->status,'done');
    like($req->error,qr'already');
    $domain->remove(user_admin);
}

sub test_display_conflict($vm) {
    diag("Test display conflict");
    my $domain = $BASE->clone(name => new_domain_name, user => user_admin);
    $domain->start( remote_ip => '1.1.1.1' , user => user_admin);
    my ($display_builtin) = @{$domain->info(user_admin)->{hardware}->{display}};
    $domain->shutdown_now(user_admin);

    my $req = Ravada::Request->add_hardware(
          uid => user_admin->id
        ,name => 'display'
        ,data => { driver => 'x2go' }
        ,id_domain =>$domain->id
    );
    wait_request(check_error => 0);
    is($req->status,'done');

    my $port = $domain->exposed_port(22);
    my $sth = connector->dbh->prepare("UPDATE domain_ports SET public_port=? "
        ." WHERE id=?");
    $sth->execute($display_builtin->{port},$port->{id});

    $sth = connector->dbh->prepare("UPDATE domain_displays SET port=? "
        ." WHERE id_domain=?");
    $sth->execute($display_builtin->{port},$domain->id);

    my $port2 = $domain->exposed_port(22);
    is($port2->{public_port},$display_builtin->{port});

    $domain->shutdown(user => user_admin, timeout => 30);
    wait_request(debug => 0);

    $domain->start( remote_ip => '1.1.1.1' , user => user_admin);
    wait_request(debug => 0);

    my $display = $domain->info(user_admin)->{hardware}->{display};
    isnt($display->[0]->{port}, $display->[1]->{port});
    is($display->[0]->{is_active},1);
    is($display->[1]->{is_active},1);

    my $port3 = $domain->exposed_port(22);
    isnt($port3->{public_port},$display_builtin->{port}) or die;

    $domain->remove(user_admin);

}

sub _next_port_builtin($domain0) {
    $domain0->start(user => user_admin, remote_ip => '1.2.3.4');
    my $displays = $domain0->info(user_admin)->{hardware}->{display};
    my $next_port_builtin = $displays->[0]->{port};

    $next_port_builtin = $displays->[0]->{extra}->{tls_port}
    if $displays->[0]->{extra}->{tls_port};

    $next_port_builtin++;
    diag("Next port builtin will  be $next_port_builtin");

    return $next_port_builtin;
}

sub _set_public_exposed($domain, $port) {
    my $sth = $domain->_dbh->prepare("UPDATE domain_ports "
        ." SET public_port=? "
        ." WHERE id_domain=?"
    );
    $sth->execute($port, $domain->id);

    $sth = $domain->_dbh->prepare("UPDATE domain_displays "
        ." SET port=? "
        ." WHERE id_domain=? AND is_builtin=0 "
    );
    $sth->execute($port, $domain->id);
}

sub _add_hardware($domain, $name, $data) {
    my $req = Ravada::Request->add_hardware(
          uid => user_admin->id
        ,name => $name
        ,data => $data
        ,id_domain =>$domain->id
    );
    wait_request(check_error => 0);
}

sub _conflict_port($domain1, $port_conflict) {
    my @domains;
    for my $n ( 1 .. 100) {
        my $domain = $BASE->clone(name => new_domain_name, user => user_admin, memory => 128*1024);
        push @domains,($domain);
        $domain->start(user => user_admin, remote_ip => '2.3.4.'.$n);
        delete_request('set_time');
        wait_request( debug => 0 );
        my $displays = $domain->info(user_admin)->{hardware}->{display};
        my $current_port = $displays->[0]->{port};
        last if $current_port >= $port_conflict;
    }
    Ravada::Request->refresh_machine_ports(uid => user_admin->id
        ,id_domain => $domain1->id
    );
    wait_request( debug => 0 );

    return @domains;
}

sub _check_iptables_fixed_conflict($vm, $port) {
    #the $port should be in chain RAVADA accept because it is builtin
    # and not on the pre-routing
    my ($out,$err) = $vm->run_command("iptables-save");
    die $err if $err;
    my @iptables_ravada = grep { /^-A RAVADA/ } split /\n/,$out;
    my @accept = grep /^-A RAVADA -s.*--dport $port .*-j ACCEPT/, @iptables_ravada;
    is(scalar(@accept),1,"Expecting --dport $port ") or die Dumper(\@iptables_ravada,\@accept);

    my @drop = grep /^-A RAVADA -d.*--dport $port .*-j DROP/, @iptables_ravada;
    is(scalar(@drop),1) or die Dumper(\@iptables_ravada,\@drop);

    my @iptables_prerouting = grep(/^-A PREROUTING .*--dport $port/, split(/\n/,$out));
    is(scalar(@iptables_prerouting),0) or die Dumper(\@iptables_prerouting);
}

sub test_display_conflict_next($vm) {
    my $domain0 = $BASE->clone(name => new_domain_name, user => user_admin, memory =>128*1024);
    my $next_port_builtin = _next_port_builtin($domain0);
    $Ravada::VM::FREE_PORT= $next_port_builtin+3;

    my $domain1 = $BASE->clone(name => new_domain_name, user => user_admin, memory => 128*1024);
    _add_hardware($domain1, 'display', { driver => 'x2go'} );
    # conflict x2go with previous builtin display
    _set_public_exposed($domain1, $next_port_builtin);

    $domain1->start(user => user_admin, remote_ip => '2.3.4.5');
    wait_request(debug => 0);
    my $displays1 = $domain1->info(user_admin)->{hardware}->{display};
    isnt($displays1->[1]->{port}, $next_port_builtin);

    # Now conflict x2go with next builtin display
    my $port_conflict = $displays1->[1]->{port};
    my @domains = _conflict_port($domain1, $port_conflict);

    my $displays1b
    = $domain1->info(user_admin)->{hardware}->{display};
    isnt($displays1b->[1]->{port}, $port_conflict) or die;
    like($displays1b->[1]->{port},qr/^\d+$/);

    _check_iptables_fixed_conflict($vm, $port_conflict) if !$<;

    for (@domains) {
        $_->remove(user_admin);
    }
    $domain1->remove(user_admin);
    $domain0->remove(user_admin);
}

sub test_display_conflict_non_builtin($vm) {
    my $base= $BASE->clone(name => new_domain_name, user => user_admin);
    my $req = Ravada::Request->add_hardware(
          uid => user_admin->id
        ,name => 'display'
        ,data => { driver => 'x2go' }
        ,id_domain =>$base->id
    );
    wait_request(check_error => 0);
    is($req->status,'done');
    $base->prepare_base(user_admin);

    my $clone0 = $base->clone(name => new_domain_name, user => user_admin);
    $clone0->start(user => user_admin , remote_ip => '2.3.4.5');

    my ($display0a, $display0b) = @{$clone0->info(user_admin)->{hardware}->{display}};

    my $port = $clone0->exposed_port(22);

    my $clone1 = $base->clone(name => new_domain_name, user => user_admin);
    $clone1->start(user => user_admin , remote_ip => 1);

    my ($display1a, $display1b) = @{$clone1->info(user_admin)->{hardware}->{display}};

    #    my $sth = connector->dbh->prepare("UPDATE domain_ports SET public_port=? "
    #    ." WHERE id=?");
    # $sth->execute($display1b->{port},$port->{id});

    my $sth = $clone1->_dbh->prepare("UPDATE domain_displays SET port=? "
        ." WHERE id_domain=?");
    $sth->execute($display1b->{port},$clone1->id);

    $clone0->shutdown(user => user_admin, timeout => 30);
    $clone1->shutdown(user => user_admin, timeout => 30);
    wait_request(debug => 0);

    $clone0->start( remote_ip => '1.1.1.1' , user => user_admin);
    $clone0->info(user_admin);
    $clone1->start( remote_ip => '1.1.1.1' , user => user_admin);
    wait_request(debug => 0);

    my $display0 = $clone0->info(user_admin)->{hardware}->{display};
    my $display1 = $clone1->info(user_admin)->{hardware}->{display};
    for my $d0 (@$display0 ) {
        for my $d1 (@$display1) {
            isnt($d0->{port},$d1->{port},$clone0->name." $d0->{driver}"
                ." - ".$clone1->name." $d1->{driver}");
        }
    }

    $clone0->remove(user_admin);
    $clone1->remove(user_admin);
    $base->remove(user_admin);
}

sub test_display_in_clone_kvm($clone, $driver) {
    my $doc = XML::LibXML->load_xml(string => $clone->domain->get_xml_description);
    my ($display) = $doc->findnodes("/domain/devices/graphics\[\@type='$driver']");
    ok($display,"Expecting $driver display in ".$clone->name);
}
sub test_display_in_clone_void($clone, $driver) {
    my $hardware = $clone->_value('hardware');
    my $found;
    for my $display ( @{$hardware->{display}} ) {
        if ($display->{driver} eq $driver) {
            $found = $display;
            last;
        }
    }
    ok($found, "Expecting $driver in hardware->display ".Dumper($hardware)) or die;
}

sub test_display_in_clone($clone, $driver) {
    if ($clone->type eq 'KVM') {
        test_display_in_clone_kvm($clone,$driver);
    }elsif ($clone->type eq 'Void') {
        test_display_in_clone_void($clone,$driver);
    } else {
        warn "TODO: check displays in clone ".$clone->type;
    }
}

sub test_displays_cloned($vm) {
    my $base= $BASE->clone(name => new_domain_name, user => user_admin);
    _add_all_displays($base);

    $base->prepare_base(user_admin);
    my $clone = $base->clone(name => new_domain_name, user => user_admin);

    for my $display ( @{$base->info(user_admin)->{hardware}->{display}} ) {
        if ($display->{is_builtin}) {
            test_display_in_clone($clone, $display->{driver});
        }
    }
    $clone->remove(user_admin);
    $base->remove(user_admin);
}

sub test_removed_leftover($vm) {
    my $domain = create_domain($vm);
    $domain->expose(23);
    my $req = Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display'
        ,data => { driver => 'x2go' }
    );
    wait_request(debug => 0);
    is($req->status,'done');
    is($req->error,'');

    $domain->remove(user_admin);
    Test::Ravada::_check_leftovers();
    $domain->remove(user_admin);
    Test::Ravada::_check_leftovers();
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
        if ($vm_name eq 'KVM') {
            $BASE = import_domain($vm,'zz-test-base-alpine');
        } else {
            $BASE = create_domain($vm);
        }
        flush_rules() if !$<;

        test_display_iptables($vm);

        test_display_conflict($vm);
        test_displays_cloned($vm);

        test_removed_leftover($vm);

        test_display_conflict_next($vm);# if $vm_name ne 'Void';
        test_display_conflict_non_builtin($vm);

        test_display_info($vm);

        test_display_port_already_used($vm);
        test_change_display_settings($vm);

        test_remove_display($vm);

        test_display_drivers($vm,0);
        test_display_drivers($vm,1); #remove after testing display type

        test_add_display_builtin($vm);
        test_add_display($vm);

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

        $BASE->remove(user_admin) if $vm_name eq 'Void';
    }
}

end();
done_testing();
