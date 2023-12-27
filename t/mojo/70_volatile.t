use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

$ENV{MOJO_MODE} = 'development';
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my $URL_LOGOUT = '/logout';

$Test::Ravada::BACKGROUND=1;
my $t;

my $BASE_NAME = "zz-test-base-alpine";
my $RAM = 0.5;

my ($USERNAME, $PASSWORD);
###############################################################

sub _wait_ip($id_domain) {
    my $domain;
    for ( 1 .. 60 ) {
        Ravada::Request->refresh_machine(
            id_domain => $id_domain
            ,uid => user_admin->id
        );

        $domain = Ravada::Front::Domain->open($id_domain);
        my $info = $domain->info(user_admin);
        return $info->{ip} if exists $info->{ip} && $info->{ip};
        diag("Waiting for ".$domain->name. " ip") if !(time % 10);
        sleep 1;
    }
}

sub _init_mojo_client {
    my $user_admin = user_admin();
    my $pass = "$$ $$";

    $USERNAME = $user_admin->name;
    $PASSWORD = $pass;

    login($user_admin->name, $pass);
    $t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);
}

sub bases($vm_name) {
    mojo_check_login($t);

    my @names;
    if ($vm_name eq 'KVM') {
        my $sth = connector->dbh->prepare("SELECT name FROM domains "
            ." WHERE is_base=1 AND (id_base IS NULL or id_base=0)"
            ." AND name like 'zz-test%'"
        );
        $sth->execute();
        while (my ($name) = $sth->fetchrow) {
            my $base0 = rvd_front->search_domain($name);
            die "Error: test base $name not found" if !$base0;

            my $new_name = new_domain_name()."-".$vm_name."-$name";
            diag($new_name);
            push @names,($new_name);
            my $base = rvd_front->search_domain($new_name);
            next if $base && $base->id;
            diag("creating");
            my $info = $base0->info(user_admin)->{hardware};
            my $ram = int($info->{memory}->[0]->{memory} / 2/1024);

            mojo_request_url_post($t,"/machine/copy"
                ,{id_base => $base0->id, new_name => $new_name
                    , copy_ram => $ram, copy_number => 1}, 0);

        }
    } else {

        my $iso_name = 'Alpine%';
        _download_iso($iso_name);
        mojo_check_login($t);
        my $name = new_domain_name()."-".$vm_name."-$$";
        $t->post_ok('/new_machine.html' => form => {
                backend => $vm_name
                ,id_iso => search_id_iso($iso_name)
                ,name => $name
                ,disk => 1
                ,ram => 1
                ,swap => 1
                ,submit => 1
            }
        )->status_is(302);
        die $t->tx->res->body if $t->tx->res->code() != 302;
    }
    my @bases;
    for my $name (@names) {
        my $base;
        for ( 1 .. 60 ) {
            $base = rvd_front->search_domain($name);
            last if $base;
            wait_request();
        }
        ok($base, "Expecting domain $name created") or exit;
        push @bases,($base);
    }
    for my $base (@bases) {
        if ($base->id_base) {
            mojo_request($t,"spinoff",{id_domain => $base->id}, 0);
        }
    }

    return @bases;
}

sub _set_base_vms($vm_name, $id_base) {
    my $sth = connector->dbh->prepare("SELECT id FROM vms WHERE vm_type=?");
    $sth->execute($vm_name);
    while ( my ($id_vm) = $sth->fetchrow) {
        mojo_request($t,"start_node" , { id_node => $id_vm }, 0);
    }

    $sth->execute($vm_name);
    while ( my ($id_vm) = $sth->fetchrow) {
        $t->post_ok("/node/enable/$id_vm.json");
        my $id_req = mojo_request($t,"set_base_vm", { id_vm => $id_vm, id_domain => $id_base, value => 1 }, 0);
        mojo_request($t,"clone", { id_domain => $id_base , after_request => $id_req, name => new_domain_name() });
    }

}

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare("SELECT id FROM vms WHERE vm_type=? AND hostname='localhost'");
    $sth->execute($vm_name);
    my ($id) = $sth->fetchrow;
    die "Error: vm_type=$vm_name not found in VMS" if !$id;
    return $id;
}

sub test_clone($vm_name, $n=10) {
    my $id_vm = _id_vm($vm_name);

    my @bases = bases($vm_name);

    for my $base ( @bases ) {
        mojo_request($t,"prepare_base", {id_domain => $base->id });
        $base->is_public(1);
        $base->volatile_clones(1);

        is($base->_data('id_vm'), $id_vm) or die $base->name;
    }

    for my $base (@bases) {
        _set_base_vms($vm_name, $base->id);
        is($base->_data('id_vm'), $id_vm) or die $base->name;
    }

    my $times = 2;
    $times = 20 if $ENV{TEST_LONG};

    for my $count0 ( 0 .. $times ) {
        for my $count1 ( 0 .. $n*scalar(@bases) ) {
            for my $base ( @bases ) {
                next if !$base->is_base || $base->is_locked;
                my $user = create_user(new_domain_name(),$$);
                my $ip = (0+$count0.$count1) % 255;

                Ravada::Request->clone(
                    uid => $user->id
                    ,id_domain => $base->id
                    ,remote_ip => "192.168.122.$ip"
                    ,start => 1
                );
                delete_request('set_time','force_shutdown');
            }
        }
        for my $base ( @bases ) {
            for ( 1 .. 10 ) {
                wait_request();
                last if $base->clones >= $n;
                diag(scalar($base->clones));
                sleep 1;
            }
            mojo_login($t, $USERNAME, $PASSWORD);
            for my $clone ( $base->clones ) {
                $t->get_ok("/machine/shutdown/".$clone->{id}.".json")->status_is(200);
                delete_request('set_time','force_shutdown');
            }
        }
        wait_request();
    }
}

sub login( $user=$USERNAME, $pass=$PASSWORD ) {
    $t->ua->get($URL_LOGOUT);

    confess "Error: missing user" if !defined $user;

    $t->post_ok('/login' => form => {login => $user, password => $pass});
    like($t->tx->res->code(),qr/^(200|302)$/)
    or die $t->tx->res->body;
    #    ->status_is(302);

    exit if !$t->success;
    mojo_check_login($t, $user, $pass);
}

sub _download_iso($iso_name) {
    my $id_iso = search_id_iso($iso_name);
    my $sth = connector->dbh->prepare("SELECT device FROM iso_images WHERE id=?");
    $sth->execute($id_iso);
    my ($device) = $sth->fetchrow;
    return if $device;
    my $req = Ravada::Request->download(id_iso => $id_iso);
    for ( 1 .. 300 ) {
        last if $req->status eq 'done';
        _wait_request(debug => 1, background => 1, check_error => 1);
    }
    is($req->status,'done');
    is($req->error, '') or exit;

}
sub _remove_unused_volumes() {
    my $sth = connector->dbh->prepare("SELECT id FROM vms WHERE hostname='localhost'");
    $sth->execute;
    my $base = base_domain_name();
    while ( my ($id) = $sth->fetchrow ) {
        my $req = Ravada::Request->list_unused_volumes(uid => user_admin->id
            , id_vm => $id
        );
        wait_request();
        next if !$req->output;
        my $list = decode_json($req->output);
        my @remove;
        for my $entry ( @{$list->{list}} ) {
            warn Dumper($entry);
            my $file = $entry->{file};
            next if !$file || $file !~ m{/$base};
            push @remove,($file);
        }
        warn Dumper(\@remove);
        if (@remove) {
            my $req = Ravada::Request->remove_files(
                files => \@remove
                ,uid => user_admin->id
                ,id_vm => $id
            );
        }
    }
}

sub _init() {
    my $sth = connector->dbh->prepare("DELETE FROM requests WHERE "
        ." status = 'requested' OR status ='waiting'"
    );
    $sth->execute();
}

sub _clean_old_known($vm_name) {
    my $sth = connector->dbh->prepare("SELECT name FROM domains "
            ." WHERE is_base=1 AND (id_base IS NULL or id_base=0)"
            ." AND name like 'zz-test%'"
    );
    my $sth_clones = connector->dbh->prepare("SELECT id,name FROM domains "
        ." WHERE id_base=?"
    );
    $sth->execute();
    while (my ($name) = $sth->fetchrow) {
        my $base0 = rvd_front->search_domain($name);
        die "Error: test base $name not found" if !$base0;

        my $new_name = new_domain_name()."-".$vm_name."-$name";
        my $base = rvd_front->search_domain($new_name);
        next if !$base;

        $sth_clones->execute($base->id);
        while (my ($id, $name)=$sth_clones->fetchrow) {
            next if !$name;
            diag("remove $name");
            my $clone = Ravada::Front::Domain->open($id);
            remove_domain($clone);
        }
    }
    wait_request();
}

sub _clean_old($vm_name) {
    _clean_old_known($vm_name);
    _remove_unused_volumes();
}

#########################################################
$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

if (!ping_backend()) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

_init();

_init_mojo_client();
login();

for my $vm_name (@{rvd_front->list_vm_types} ) {
    diag("Testing new machine in $vm_name");

    _clean_old($vm_name);

    test_clone($vm_name);
}

end();
done_testing();
