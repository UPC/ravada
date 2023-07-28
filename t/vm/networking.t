use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

my $N = 100;
########################################################################

sub test_list_networks($vm) {
    my @list = $vm->list_virtual_networks();
    my ($default)= grep { $_->{name} eq 'default' } @list;
    ok($default);

    for my $net ( @list ) {
        my ($found) = _search_network(internal_id=>$net->{internal_id});
        is($found->{name}, $net->{name});
        ($found) = _search_network(id_vm => $net->{id_vm}, name => $net->{name});
        is($found->{internal_id}, $net->{internal_id});
    }

}

sub _search_network(%args) {
    my $sql = "SELECT * FROM virtual_networks "
    ." WHERE ".join(" AND ",map { "$_=?" } sort keys %args);
    my $sth = connector->dbh->prepare($sql);
    $sth->execute(map { $args{$_} } sort keys %args);
    my $found = $sth->fetchrow_hashref;
    return $found;
}

sub test_add_network($vm) {
    my $name = new_domain_name;
    my $net = {
        name => $name
        ,id_vm => $vm->id
        ,ip_address => '192.0.'.$N++.'.1'
        ,ip_netmask => '255.255.255.0'
    };
    my $user = create_user();
    my $req = Ravada::Request->create_network(
        uid => $user->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request(check_error => 0);
    like($req->error,qr/not authorized/);

    $req = Ravada::Request->create_network(
        uid => user_admin->id
        ,id_vm => $vm->id
        ,data => $net
    );
    wait_request( debug => 0);
    my($new) = grep { $_->{name} eq $name } $vm->list_virtual_networks();
    ok($new,"Expecting new network $name created") or return;

    like($new->{dhcp_start},qr/.*\.2$/);
    like($new->{dhcp_end},qr/.*\.254$/);
    ok($new->{internal_id});
    is($new->{is_active},1);
    is($new->{autostart},1);
    return $new;
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

    my ($default) = grep { $_->{name} eq 'default' } $vm->list_virtual_networks();
    $net2{bridge} = $default->{bridge};
    $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => \%net2
    );
    wait_request(check_error => 0);

    ($new) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    isnt($new->{bridge},$default->{bridge});
    _check_network_changed($new,'bridge') or exit;

    $net2{name} = new_domain_name();
    $req = Ravada::Request->change_network(
        uid => user_admin->id
        ,data => \%net2
    );
    wait_request(check_error => 0 );

    like($req->error,qr/can not be renamed/);

}

sub test_change_network_internal($vm, $net) {
    return if $vm->type ne 'KVM';

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
    return if $vm->type ne 'KVM';
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

sub test_disapeared_network($vm) {
    return if $vm->type ne 'KVM';
    my $net = test_add_network($vm);

    my $network = $vm->vm->get_network_by_name($net->{name});
    $network->destroy() if $network->is_active;
    $network->undefine();

    my ($net2) = grep { $_->{name} eq $net->{name} } $vm->list_virtual_networks();
    ok(!$net2, "Expecting $net->{name} removed");

    my $sth = connector->dbh->prepare("SELECT * FROM virtual_networks WHERE name=?");
    $sth->execute($net->{name});
    my $row = $sth->fetchrow_hashref;
    ok(!$row,"Expected $net->{name} removed from db".Dumper($row)) or exit;

    my ($default) = grep { $_->{name} eq 'default' } $vm->list_virtual_networks();
    ok($default) or exit;

    $sth->execute('default');
    $row = $sth->fetchrow_hashref;
    ok($row,"Expected default not removed from db".Dumper($row)) or exit;

}

sub test_add_down_network($vm) {
    return if $vm->type ne 'KVM';

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

        is($vm->has_networking,1) if $vm_name eq 'KVM';
        next if !$vm->has_networking();

        test_changed_uuid($vm);

        test_disapeared_network($vm);
        test_add_down_network($vm);

        test_list_networks($vm);
        my $net = test_add_network($vm);

        test_change_network_internal($vm, $net);

        test_change_network($net);

        test_remove_network($vm,$net);
    }
}

end();

done_testing();

