use warnings;
use strict;

use utf8;

use Carp qw(confess);
use Data::Dumper;
use HTML::Lint;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $t;

my $URL_LOGOUT = '/logout';
my ($USERNAME, $PASSWORD);
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my %BASE_NAME =(
    C => 'a'
    ,cyrillic => "пользователя"
    ,catalan => 'áçìüèò'
);

for my $lang (keys %BASE_NAME) {
    $BASE_NAME{$lang} = new_domain_name()."-".$BASE_NAME{$lang};
}
my $N = 0;
########################################################################

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare("SELECT id FROM vms"
        ." WHERE vm_type=? AND hostname=? ");
    $sth->execute($vm_name,'localhost');
    my ($id) = $sth->fetchrow;
    confess "Error no vm $vm_name" if !defined $id;
    return $id;
}

sub _test_discover($vm_name) {
    my $req = Ravada::Request->discover(
        uid => user_admin->id
        ,id_vm => _id_vm($vm_name)
    );
    wait_request();
    return if !$req->output;

    my $json = decode_json($req->output);
    my $base_name = base_domain_name();
    my @domains = grep { /^$base_name/ } @$json;
    ok(!scalar(@domains)) or confess Dumper(\@domains);
}

sub test_utf8($t, $vm_name) {
    for my $lang (reverse sort keys %BASE_NAME) {
        diag("testing $lang $vm_name");
        test_rename_ascii($t, $vm_name, $BASE_NAME{$lang});
        test_clone_utf8_domain($t, $vm_name, $BASE_NAME{$lang});
        test_clone_utf8_user($t, $vm_name, $BASE_NAME{$lang});
    }
}

sub test_rename_ascii($t, $vm_name, $base_name) {
    my $user_name = new_domain_name();

    my $user_db = Ravada::Auth::SQL->new( name => $user_name);
    $user_db->remove();

    my $user = create_user($user_name, $$);
    user_admin->make_admin($user->id);

    mojo_login($t, $user_name, $$);

    my $domain = _new_machine($vm_name, $user, $base_name);

    my $new_name = new_domain_name();

    my $id_req = mojo_request($t, "rename_domain", {
            id_domain => $domain->id
            ,name => $new_name
    });
    ok($id_req) or return;
    my $req = Ravada::Request->open($id_req);

    wait_request();
    is($req->error,'') or exit;

    my $domain2 = Ravada::Front::Domain->open($domain->id);
    is($domain2->name,$new_name) or exit;
    is($domain2->_data('name'), $new_name);
    is($domain2->_data('alias'), $new_name);

    Ravada::Request->remove_domain(
        uid => user_admin->id
        ,name => $domain2->name
    );
    _test_discover($vm_name);
}

sub test_clone_utf8_domain($t, $vm_name, $base_name) {
    test_clone_utf8_user($t, $vm_name,$base_name, 1);
}

sub _new_machine($vm_name, $user, $base_name) {

    my $iso_name = 'Alpine%64 bits';
    my $id_iso = search_id_iso($iso_name);

    _test_discover($vm_name);

    $t->post_ok("/new_machine.html",
        form => {
            backend => $vm_name
            ,name => $base_name
            ,disk => 1
            ,swap => 1
            ,data => 1
            ,memory => 1
            ,id_owner => $user->id
            ,id_iso => $id_iso
            ,submit => 1
            ,start => 0
        }
    )->status_is(302);
    wait_request(debug => 0);

    my ($created) = rvd_front->search_domain($base_name);
    ok($created, "Expecting $base_name created") or exit;
    _test_discover($vm_name);
    return $created;
}

sub test_clone_utf8_user($t, $vm_name, $name, $utf8_base=0) {
    confess if $name =~ /^\d+/;
    my $user_name = new_domain_name()."-$$-".$name."-".$N++;

    my $user_db = Ravada::Auth::SQL->new( name => $user_name);
    $user_db->remove();

    my $user = create_user($user_name, $$);
    user_admin->make_admin($user->id);

    mojo_login($t, $user_name, $$);
    my $base_name;
    if ($utf8_base) {
        $base_name = $user_name;
    } else {
        $base_name = new_domain_name()."-".$$;
    }

    my $domain = _new_machine($vm_name, $user, $base_name);
    ok($domain,"Expecting domain $base_name found") or exit;
        is($domain->alias, $base_name);

    like($domain->name,qr/^[a-z0-9_\-]+$/) or exit;
    my $info = $domain->info(user_admin);
    if ($base_name =~ /^[a-z0-9_\-]+$/) {
        is($domain->_data('alias'),undef);
        is($info->{alias},$info->{name});
    } else {
        is($domain->_data('alias'),$base_name);
        isnt($domain->_data('alias'),$domain->name);
        isnt($info->{alias},$info->{name});
        is($info->{alias},$base_name);
    }

    _test_discover($vm_name);

    $t->post_ok("/request/prepare_base/", json => {
            id_domain => $domain->id
        });
    $t->get_ok('/machine/public/'.$domain->id."/1")->status_is(200);
    wait_request(debug => 0);
    _test_list_machines_user($base_name, $user);
    my ($clone) = _test_clone($domain, $base_name, $user);

    _test_copy($domain, $base_name);

    remove_domain_and_clones_req($domain);
}

sub _test_list_machines_user($base_name, $user) {
    my $list_bases = rvd_front->list_machines_user($user);
    my ($found) = grep { $_->{name} eq $base_name } @$list_bases;
    ok($found,"Expecting base $base_name "
        .Dumper[map{$_->{name} } @$list_bases]) or exit;

}

sub _test_clone($domain, $base_name, $user) {
    $t->get_ok("/machine/clone/".$domain->id.".html")->status_is(200);
    die $t->tx->res->body() if $t->tx->res->code() != 200;
    wait_request(debug => 0);

    is(scalar($domain->clones),1) or exit;

    my $user_name = $user->name;
    for my $clone ($domain->clones) {

        like($clone->{name},qr/^[a-z0-9_\-\.]+$/) or exit;
        like($clone->{alias},qr/$base_name-$user_name/) or exit;

    }
    _test_discover($domain->type);
    return $domain->clones();
}

sub _test_copy($domain, $base_name) {
    my $copy_name = $base_name."-copy-".$base_name;
    $t->post_ok("/machine/copy/" => json => {
        id_base=> $domain->id
        ,new_name => $copy_name
    });
    wait_request(debug => 1);

    my ($copy) = rvd_front->search_domain($copy_name);
    ok($copy);
    like($copy->_data('name'),qr/^[a-z0-9_\-]+$/);
    unlike($copy->_data('name'),qr/--+/) or exit;

    _test_discover($domain->type);

    Ravada::Request->remove_domain(
        uid => user_admin->id
        ,name => $copy_name
    );

    _test_discover($domain->type);

}

########################################################################

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

my $connector_f = rvd_front->connector;
like($connector_f->{driver} , qr/mysql/i) or BAIL_OUT;

if (!ping_backend()) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);
remove_old_domains_req(0); # 0=do not wait for them

for my $vm_name (sort @{rvd_front->list_vm_types} ) {
    test_utf8($t, $vm_name);
}

remove_old_domains_req(0); # 0=do not wait for them
done_testing();

