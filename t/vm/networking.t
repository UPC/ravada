use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Mojo::JSON qw(decode_json);
use Storable qw(dclone);
use Test::More;

use YAML qw(Dump LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my $N = 100;
########################################################################

sub test_list_networks($vm) {
    my @list = $vm->list_virtual_networks();
    my ($default)= @list;
    ok($default) or exit;

    my $public=0;
    for my $net ( @list ) {
        ok($net->{id_vm}) or die "Error: network missing id_vm ".Dumper($net);
        my ($found) = _search_network(internal_id=>$net->{internal_id});
        is($found->{name}, $net->{name});
        is($found->{id_vm}, $net->{id_vm});
        $public++ if $found->{is_public};
        ($found) = _search_network(id_vm => $net->{id_vm}, name => $net->{name});
        die "Error: network not found id_vm= $net->{id_vm}, name=$net->{name}"
        if !$found;
        is($found->{internal_id}, $net->{internal_id}) or die Dumper($found);
    }
    ok($public,"Expecting at least one public network discovered, got $public") or exit;

}

sub _search_network(%args) {
    my $sql = "SELECT * FROM virtual_networks "
    ." WHERE ".join(" AND ",map { "$_=?" } sort keys %args);
    my $sth = connector->dbh->prepare($sql);
    $sth->execute(map { $args{$_} } sort keys %args);
    my $found = $sth->fetchrow_hashref;
    return $found;
}

sub _get_active_network($vm) {
    my($active) = grep { $_->{is_active} } $vm->list_virtual_networks();
    return $active if $active;

    my @networks = $vm->list_virtual_networks();
    for my $old (@networks) {
        Ravada::Request->change_network(
            uid => user_admin->id
            ,data => { %$old, is_active => 1 }
        );
        wait_request();
        my ($net) = grep {$_->{id} == $old->{id}} $vm->list_virtual_networks();
        return $net if $net->{is_active};
    }
    die "Error: No network could be activated ".Dumper(\@networks);
}
sub test_create_fail ($vm) {

    my @networks = $vm->list_virtual_networks();

    my $net0 = _get_active_network($vm);
    my $name = new_domain_name;
    my $net = {
        name => $name
        ,id_vm => $vm->id
        ,ip_address => $net0->{ip_address}
        ,ip_netmask => '255.255.255.0'
        ,is_active => 1
    };
    my $req = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request(check_error => 0, debug => 0);
    like($req->error,qr/Network is already in use/) or die $name;
    my $out = decode_json($req->output);
    like($out->{id_network},qr/^\d+$/) or exit;

    my ($old) = grep { $_->{id} eq $out->{id_network} } @networks;
    ok(!$old,"Expecting new network is created");
}

sub test_duplicate_add($vm, $net) {
    my $net2 = dclone($net);
    delete $net2->{id};
    delete $net2->{internal_id};
    my $req = Ravada::Request->create_network(
        data => $net2
        ,uid => user_admin->id
        ,id_vm => $vm->id
    );
    wait_request( check_error => 0, debug => 0);
    like($req->error,qr/already exist/);
}

sub test_duplicate_bridge_add($vm, $net) {
    my ($net0) = grep { $_->{name} eq $net->{name}} $vm->list_virtual_networks();
    my $net2 = dclone($net);
    delete $net2->{id};
    delete $net2->{internal_id};
    delete $net2->{dhcp_start};
    delete $net2->{dhcp_end};
    $net2->{bridge} = $net0->{bridge};
    $net2->{name} = new_domain_name();
    $net2->{ip_address} = '192.51.200.1';

    my $req = Ravada::Request->create_network(
        data => $net2
        ,uid => user_admin->id
        ,id_vm => $vm->id
    );
    wait_request( check_error => 0, debug => 0);
    is($req->output,'{}');
    like($req->error,qr/already exists/) or exit;

    my ($net_created) = grep {$net2->{name} eq $_->{name} }
        $vm->list_virtual_networks();

    ok(!$net_created) or die "Expecting $net2->{name} not created";

    Ravada::Request->remove_network(
        uid => user_admin->id
        ,id => $net_created->{id}
    ) if $net_created;
}

# only admins or users that can manage all networks can do this
sub test_change_owner($vm) {
    my $user = create_user();
    my $new = $vm->new_network(new_domain_name);
    my $req = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $new
    );
    wait_request();

    my($new2) = grep { $_->{name} eq $new->{name} } $vm->list_virtual_networks();
    ok($new2) or return;
    $new2->{id_owner} = $user->id;
    my $req_change = Ravada::Request->change_network(
        uid => $user->id
        ,data => $new2
    );

    wait_request(check_error => 0, debug => 0);

    my($new2b) = grep { $_->{name} eq $new->{name} } $vm->list_virtual_networks();
    is($new2b->{id_owner}, user_admin->id);

    like($req_change->error,qr/not authorized/) or exit;

    user_admin->grant($user, 'create_networks');
    $req_change->status('requested');

    wait_request(check_error => 0);
    like($req_change->error,qr/not authorized/);
    my($new2c) = grep { $_->{name} eq $new->{name} } $vm->list_virtual_networks();
    is($new2c->{id_owner}, user_admin->id);

    user_admin->grant($user, 'manage_all_networks');
    $req_change->status('requested');
    wait_request(check_error => 0);
    is($req_change->error, '');

    my($new3) = grep { $_->{name} eq $new->{name} } $vm->list_virtual_networks();
    is($new3->{id_owner}, $user->id);

    $new2->{id_owner} = user_admin->id;
    my $req_change2 = Ravada::Request->change_network(
        uid => $user->id
        ,data => $new2
    );

    wait_request(check_error => 0);

    is($req_change2->error, '');

    my($new4) = grep { $_->{name} eq $new->{name} } $vm->list_virtual_networks();
    is($new4->{id_owner}, user_admin->id);

}

sub test_add_network($vm) {
    my $req_new = Ravada::Request->new_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => base_domain_name()
    );
    wait_request(debug => 0);

    my $net = decode_json($req_new->output);
    my $name = $net->{name};

    my $user = create_user();
    my $req = Ravada::Request->create_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request(check_error => 0);
    like($req->error,qr/not authorized/);
    my($new0) = grep { $_->{name} eq $name } $vm->list_virtual_networks();
    ok(!$new0,"Expecting no new network $name created") or return;

    $req = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request( debug => 0);

    my $out = decode_json($req->output);
    my($new) = grep { $_->{name} eq $name } $vm->list_virtual_networks();
    ok($new,"Expecting new network $name created") or die Dumper([$vm->list_virtual_networks]);
    isa_ok($out,'HASH')
    && is($out->{id_network},$new->{id});

    like($new->{dhcp_start},qr/.*\.2$/);
    like($new->{dhcp_end},qr/.*\.254$/);
    ok($new->{internal_id});
    is($new->{is_active},1);
    is($new->{autostart},1);
    is($new->{is_public},0);
    return $new;
}

sub test_remove_user($vm) {
    my $user = create_user();
    user_admin->make_admin($user->id);
    my $req = Ravada::Request->new_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,name => base_domain_name()
    );
    wait_request(debug => 0);

    my $data = decode_json($req->output);
    is($data->{id_vm},$vm->id);

    my $req_create = Ravada::Request->create_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,data => $data
    );
    wait_request(debug => 0);

    my($new0) = grep { $_->{name} eq $data->{name} } $vm->list_virtual_networks();
    is($new0->{id_owner}, $user->id) or exit;

    $user->remove();
    wait_request(debug => 0);

    my($new) = grep { $_->{name} eq $data->{name} } $vm->list_virtual_networks();
    ok(!$new,"Expecting removed network $new0->{id} $data->{name}") or exit;
}
sub test_remove_network($vm, $net) {
    my $user = create_user();
    my $req = Ravada::Request->remove_network(
        uid => $user->id
        ,id => $net->{id}
    );
    wait_request(check_error => 0);
    like($req->error,qr/not authorized/);
    user_admin->make_admin($user->id);
    $req->status('requested');

    wait_request(debug => 0);

    my($new) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    ok(!$new,"Expecting removed network $net->{name}") or exit;
}

sub _check_network_changed($net, $field) {
    my $sth = connector->dbh->prepare(
        "SELECT * FROM virtual_networks WHERE id=?"
    );
    $sth->execute($net->{id});
    my $row = $sth->fetchrow_hashref;
    is($row->{$field},$net->{$field}, $field) or exit;
}

sub test_change_network($net) {
    my %net2 = %$net;
    $net2{dhcp_end} =~ s/(.*)\.\d+$/$1.100/;
    my $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => \%net2
    );
    wait_request();
    my $vm = Ravada::VM->open($net->{id_vm});

    my($new) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    is($new->{dhcp_end},$net2{dhcp_end}) or die $net->{name};

    _check_network_changed($new,'dhcp_end');

    for my $is (0, 1) {
        $net2{is_active} = $is;
        $req = Ravada::Request->change_network(
            uid => user_admin->id
            ,data => \%net2
        );
        wait_request(debug => 0);

        ($new) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
        is($new->{is_active},$is);
        _check_network_changed($new,'is_active');
    }

    $net2{autostart} = 0;
    $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => \%net2
    );
    wait_request();

    ($new) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    is($new->{autostart},0);
    _check_network_changed($new,'autostart');

    for ( 1 .. 2 ) {
        $net2{is_active} = (!$net2{is_active} or 0);
        $req = Ravada::Request->change_network(
            uid => user_admin->id
            ,data => \%net2
        );
        wait_request();
        my ($new2) = grep { $_->{name} eq $net2{name} } $vm->list_virtual_networks();
        is($new2->{is_active},$net2{is_active});
    }

    for ( 1 .. 2 ) {
        $net2{is_public} = (!$net2{is_public} or 0);
        $req = Ravada::Request->change_network(
            uid => user_admin->id
            ,data => \%net2
        );
        wait_request(debug => 0);
        my ($new2) = grep { $_->{name} eq $net2{name} } $vm->list_virtual_networks();
        is($new2->{is_public}, $net2{is_public},"Expecting is_public=$net2{is_public}")
            or die $net2{name};
    }

    my ($default) = grep { $_->{name} eq 'default' } $vm->list_virtual_networks();
    $net2{bridge} = $default->{bridge};
    $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => \%net2
    );
    wait_request(check_error => 0, debug => 0);
    like($req->error,qr/already in use/);

    $net2{name} = new_domain_name();
    $net2{bridge}='virbr99';
    $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => \%net2
    );
    wait_request(check_error => 0 );

    like($req->error,qr/can not be renamed/);

}

sub test_change_network_internal($vm, $net) {
    if ($vm->type eq 'KVM') {
        test_change_network_internal_kvm($vm, $net);
    } elsif ($vm->type eq 'Void') {
        test_change_network_internal_void($vm, $net);
    }
}

sub test_change_network_internal_void($vm, $net) {
    my $file_out = $vm->dir_img."/networks/".$net->{name}.".yml";

    my $start_new = $net->{dhcp_start};
    my ($n) = $start_new =~ /.*\.(\d+)/;
    $n++;
    $start_new =~ s/(.*)\.(\d+)/$1.$n/;
    $net->{dhcp_start}=$start_new;

    DumpFile($file_out,$net);

    my ($net2) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    is($net2->{dhcp_start},$start_new) or die Dumper($net2);
}

sub test_change_network_internal_kvm($vm, $net) {
    my $network = $vm->vm->get_network_by_name($net->{name});
    die "Error: I can't find network $net->{name}" if !$network;

    my $doc = XML::LibXML->load_xml( string => $network->get_xml_description );
    my ($range) = $doc->findnodes("/network/ip/dhcp/range");
    my $start_new = $range->getAttribute('start');
    my ($n) = $start_new =~ /.*\.(\d+)/;
    $n++;
    $start_new =~ s/(.*)\.(\d+)/$1.$n/;
    $range->setAttribute('start' , $start_new);

    $network->destroy();
    $network= $vm->vm->define_network($doc->toString);
    $network->create();

    my $network2 = $vm->vm->get_network_by_name($net->{name});
    my ($range2) = $doc->findnodes("/network/ip/dhcp/range");
    is($range2->getAttribute('start'), $start_new) or exit;

    my ($net2) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    is($net2->{dhcp_start},$start_new) or exit;

}

sub test_changed_uuid($vm) {
    if($vm->type eq 'KVM') {
        test_changed_uuid_kvm($vm);
    }
}

sub test_changed_uuid_kvm($vm) {
    my $net = test_add_network($vm);

    my $network = $vm->vm->get_network_by_name($net->{name});
    my $doc = XML::LibXML->load_xml(string => $network->get_xml_description());

    $network->destroy() if $network->is_active;
    $network->undefine();

    my ($uuid_xml) = $doc->findnodes("/network/uuid");
    $uuid_xml->removeChildNodes();
    my $new_uuid = $vm->_unique_uuid();
    $uuid_xml->appendText($new_uuid);

    $vm->vm->define_network($doc->toString());

    my ($net2) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    ok($net2,"Expecting $net->{name} found");
    is($net2->{internal_id},$new_uuid) or die Dumper($net2);

    my $sth = connector->dbh->prepare("SELECT * FROM virtual_networks "
        ." WHERE name=?"
    );
    $sth->execute($net->{name});
    my $row = $sth->fetchrow_hashref;
    is($row->{internal_id},$new_uuid) or exit;

}

sub _remove_network_internal($vm,$name) {
    if ($vm->type eq 'KVM') {
        _remove_network_internal_kvm($vm, $name);
    } elsif ($vm->type eq 'Void') {
        _remove_network_internal_void($vm, $name);
    } else {
        die $vm->type;
    }
}

sub _remove_network_internal_kvm($vm, $name) {
    my $network = $vm->vm->get_network_by_name($name);
    $network->destroy() if $network->is_active;
    $network->undefine();
}

sub _remove_network_internal_void($vm, $name) {
    my $file_out = $vm->dir_img."/networks/$name.yml";
    unlink $file_out or die "$! $file_out" if $vm->file_exists($file_out);
}

sub test_disapeared_network($vm) {
    my ($default0) = $vm->list_virtual_networks();

    my $net = test_add_network($vm);
    _remove_network_internal($vm, $net->{name});

    my ($net2) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    ok(!$net2, "Expecting $net->{name} removed");

    my $sth = connector->dbh->prepare("SELECT * FROM virtual_networks WHERE name=?");
    $sth->execute($net->{name});
    my $row = $sth->fetchrow_hashref;
    ok(!$row,"Expected $net->{name} removed from db".Dumper($row)) or exit;

    my ($default) = grep { $_->{name} eq $default0->{name} } $vm->list_virtual_networks();
    ok($default) or exit;

    $sth->execute($default0->{name});
    $row = $sth->fetchrow_hashref;
    ok($row,"Expected default not removed from db".Dumper($row)) or exit;

}

sub test_add_down_network($vm) {

    my $test = test_add_network($vm);
    $test->{is_active} = 0;
    my $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => $test
    );
    wait_request();

    my $sth = connector->dbh->prepare("DELETE FROM virtual_networks "
        ." WHERE name=? "
    );
    $sth->execute($test->{name});

    my ($net2) = grep { $_->{name} eq $test->{name} } $vm->list_virtual_networks();
    ok($net2,"Expecting $test->{name} network listed") or exit;
}

sub test_public_network($vm, $net) {

    my $net2 = dclone($net);
    my $user2 = create_user();

    my $req_change = Ravada::Request->change_network(
        uid => $user2->id
        ,data => {%$net, id_owner => $user2->id }
    );

    wait_request(check_error => 0);
    like($req_change->error,qr/not authorized/);

    my $req_change2 = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => {%$net, id_owner => $user2->id, is_public=>1 }
    );

    wait_request(check_error => 0, debug => 0);
    is($req_change2->error,'');

    my $domain = create_domain($vm);
    $domain->is_public(1);
    $domain->prepare_base(user_admin);

    user_admin->grant($user2,'change_settings');
    user_admin->grant($user2,'create_networks');

    my $clone = $domain->clone(user => $user2,name => new_domain_name);

    my $hw_net = $clone->info(user_admin)->{hardware}->{network}->[0];
    ok($hw_net) or die $clone->name;
    my %hw_net2 = %$hw_net;

    my $list_nets = rvd_front->list_networks($vm->id,$user2->id);
    ok(scalar(@$list_nets) >= 1,"Expecting at least 1 network allowed, got "
        .scalar(@$list_nets)) or exit;

    $hw_net2{network}=$net->{name};
    is($user2->can_change_hardware_network($clone, \%hw_net2),1) or exit;

    my $req = Ravada::Request->change_hardware(
        uid => $user2->id
        ,id_domain => $clone->id
        ,hardware => 'network'
        ,index => 0
        ,data => \%hw_net2
    );
    wait_request(check_error => 0, debug => 0);
    is($req->error,'');


    my $net3 = _search_network(id => $net->{id});
    is($net3->{id_owner}, $user2->id) or exit;

    is($user2->can_change_hardware_network($clone, {network => $net3->{name}}),1) or exit;

    $req->status('requested');
    wait_request(check_error => 0);
    is($req->error, '');

    my $clone4 = Ravada::Front::Domain->open($clone->id);
    my $hw_net4 = $clone4->info(user_admin)->{hardware}->{network}->[0];

    is($hw_net2{network}, $net->{name});
}

sub test_manage_all_networks($vm, $net) {

    my $net2 = dclone($net);
    my $user2 = create_user();

    my $req_change2 = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => {%$net, is_public=>0 }
    );

    wait_request(check_error => 0, debug => 0);
    is($req_change2->error,'');

    my $domain = create_domain($vm);
    $domain->is_public(1);
    $domain->prepare_base(user_admin);

    user_admin->grant($user2,'change_settings');
    user_admin->grant($user2,'manage_all_networks');

    my $clone = $domain->clone(user => $user2,name => new_domain_name);

    my $hw_net = $clone->info(user_admin)->{hardware}->{network}->[0];
    ok($hw_net) or die $clone->name;
    my %hw_net2 = %$hw_net;

    $hw_net2{network}=$net->{name};
    is($user2->can_change_hardware_network($clone, \%hw_net2),1) or exit;

    my $req = Ravada::Request->change_hardware(
        uid => $user2->id
        ,id_domain => $clone->id
        ,hardware => 'network'
        ,index => 0
        ,data => \%hw_net2
    );
    wait_request(check_error => 0, debug => 0);
    is($req->error,'');

    my $clone4 = Ravada::Front::Domain->open($clone->id);
    my $hw_net4 = $clone4->info(user_admin)->{hardware}->{network}->[0];

    is($hw_net2{network}, $net->{name});
}

sub test_new_network($vm) {
    my $req = Ravada::Request->new_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => base_domain_name()."_"
    );
    wait_request();
    my $data = decode_json($req->output);
    is($data->{id_vm},$vm->id);

    my $req_create = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $data
    );
    wait_request(debug => 0);

    my $req2 = Ravada::Request->new_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,name => base_domain_name()."_"
    );
    wait_request();
    my $new_net = decode_json($req_create->output);

    my $data2 = decode_json($req2->output);
    for my $field( keys %$data) {
        next if $field =~ /^(id_vm|ip_netmask|is_active|autostart)/;

        isnt($data2->{$field}, $data->{$field},$field);
    }
    Ravada::Request->remove_network(
        uid => user_admin->id
        ,id => $new_net->{id_network}
    );
    wait_request();

}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {
    diag("testing $vm_name");

    SKIP: {

        my $msg = "SKIPPED test: No $vm_name VM found ";
        my $vm;
        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
        } else {
            $vm = Ravada::VM->open( type => $vm_name );
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        is($vm->has_networking,1) if $vm_name eq 'KVM'
        || $vm_name eq 'Void';
        next if !$vm->has_networking();

        test_remove_user($vm);

        test_create_fail($vm);

        test_list_networks($vm);

        my $net = test_add_network($vm);
        test_manage_all_networks($vm,$ net);
        test_public_network($vm, $net);

        test_change_owner($vm);

        test_new_network($vm);

        test_duplicate_add($vm, $net);

        test_duplicate_bridge_add($vm, $net);

        test_change_network_internal($vm, $net);
        test_change_network($net);

        test_changed_uuid($vm);

        test_disapeared_network($vm);
        test_add_down_network($vm);

        test_remove_network($vm,$net);
    }
}

end();

done_testing();

