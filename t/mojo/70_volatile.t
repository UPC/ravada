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

my $MAX_LOAD = 10;
my ($USERNAME, $PASSWORD);
###############################################################

sub _wait_ip($id_domain0, $seconds=60) {

    my $domain;
    for my $count ( 0 .. $seconds ) {
        my $id_domain = $id_domain0;

        if ($id_domain0 !~ /^\d+$/) {
            $id_domain = _search_domain_by_name($id_domain);
            next if !$id_domain;
        }

        Ravada::Request->refresh_machine(
            id_domain => $id_domain
            ,uid => user_admin->id
        );

        my $info;
        eval {
        $domain = Ravada::Front::Domain->open($id_domain);
        $info = $domain->info(user_admin);
        };
        warn $@ if $@ && $@ !~ /Unknown domain/;
        return if $@ || ($count && !$domain->is_active);
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

            my $new_name = base_domain_name()."-".$vm_name."-$name";
            push @names,($new_name);
            my $base = rvd_front->search_domain($new_name);
            next if $base && $base->id;
            my $info = $base0->info(user_admin)->{hardware};
            my $ram = int($info->{memory}->[0]->{memory} / 2/1024);

            mojo_request_url_post($t,"/machine/copy"
                ,{id_base => $base0->id, new_name => $new_name
                    , copy_ram => $ram, copy_number => 1}, 0);

        }
    } else {

        my $iso_name = 'Alpine%';
        _download_iso($iso_name);
        for ( 1 .. 2 ) {
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
            push @names,($name);
        }
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
        last if scalar(@bases)>1 && !$ENV{TEST_LONG};
    }
    for my $base (@bases) {
        if ($base->id_base) {
            mojo_request($t,"spinoff",{id_domain => $base->id}, 0);
        }
    }

    return @bases;
}

sub _start_nodes() {
    my $sth = connector->dbh->prepare("SELECT id,name FROM vms");
    $sth->execute();
    while ( my ($id_vm,$name) = $sth->fetchrow) {
        Ravada::Request->start_node(
            uid => user_admin->id
            ,id_node => $id_vm
        );
        my $node_domain = Ravada::Front::Domain->new(name => $name);
        next if !$node_domain->is_known();
        Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $node_domain->id
        );
    }
    wait_request();

}

sub _set_base_vms($vm_name, $id_base, $network) {
    my $sth = connector->dbh->prepare("SELECT id,name FROM vms WHERE vm_type=?");
    $sth->execute($vm_name);
    my $count_nodes=0;
    while ( my ($id_vm,$name) = $sth->fetchrow) {
        $count_nodes++;
        mojo_request($t,"start_node" , { id_node => $id_vm }, 0);
        my $node_domain = Ravada::Front::Domain->new(name => $name);
        next if !$node_domain->is_known();
        Ravada::Request->start_domain(uid => user_admin->id
            ,id_domain => $node_domain->id
        );
    }
    die "Error: we need at least 2 $vm_name nodes , $count_nodes found"
    if $count_nodes<2;

    $sth->execute($vm_name);
    while ( my ($id_vm, $name) = $sth->fetchrow) {
        $t->post_ok("/node/enable/$id_vm.json");

        my $id_req = mojo_request($t,"set_base_vm", { id_vm => $id_vm, id_domain => $id_base, value => 1 }, 0);
        mojo_request($t,"clone", { id_domain => $id_base , after_request => $id_req, name => new_domain_name()
                    ,options => { network => $network->{name} }
            });
    }

}

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare("SELECT id FROM vms WHERE vm_type=? AND hostname='localhost'");
    $sth->execute($vm_name);
    my ($id) = $sth->fetchrow;
    die "Error: vm_type=$vm_name not found in VMS" if !$id;
    return $id;
}

sub _count_nodes($vm_name) {
    my $sth = connector->dbh->prepare(
        "SELECT count(*) FROM vms WHERE vm_type=?"
        ."  AND is_active=1 AND enabled=1"
    );
    $sth->execute($vm_name);
    my ($count) = $sth->fetchrow;
    warn "No nodes found for vm_type=$vm_name" if !$count;
    return ($count or 1);
}

sub _new_network($vm_name,$id_vm) {

    my $net;

    for my $cont ( 140 .. 150 ) {
        my $req_new = Ravada::Request->new_network(
            uid => user_admin->id
            ,id_vm => $id_vm
            ,name => base_domain_name()
        );
        wait_request(debug => 0);
        like($req_new->output , qr/\d+/) or exit;

        $net = decode_json($req_new->output);
        $net->{ip_address} =~ s/(\d+\.\d+\.)\d+(.*)/$1$cont$2/;
        my $name = $net->{name};

    }

    _create_network_nodes($vm_name, $net);

    return $net;
}

sub _create_network_nodes($vm_name, $net) {
    my $sth = connector->dbh->prepare(
        "SELECT id FROM vms WHERE vm_type=?"
        ."  AND is_active=1 AND enabled=1"
    );
    $sth->execute($vm_name);
    while ( my ($id_vm) = $sth->fetchrow ) {
        $net->{id_vm} = $id_vm;
        Ravada::Request->create_network(
            uid => user_admin->id
            ,id_vm => $id_vm
            ,data => $net
        );

    }
}

sub test_clone($vm_name, $n=undef) {
    if (!defined $n) {
        $n=1;
        $n=10 if $ENV{TEST_LONG};
    }
    my $id_vm = _id_vm($vm_name);

    my @bases = bases($vm_name);

    diag("Testing ".scalar(@bases)." bases in $vm_name");
    return if !scalar(@bases);

    my $network = _new_network($vm_name, $id_vm);
    my $network_name = $network->{name};

    for my $base ( @bases ) {
        mojo_request($t,"prepare_base", {id_domain => $base->id });
        $base->is_public(1);
        $base->volatile_clones(1);

        is($base->_data('id_vm'), $id_vm) or die $base->name;

        Ravada::Request->remove_clones(
            uid => user_admin->id
            ,id_domain => $base->id
            ,at => time + 300+_count_nodes($vm_name)*2
        );

    }

    for my $base (@bases) {
        _set_base_vms($vm_name, $base->id, $network);
        is($base->_data('id_vm'), $id_vm) or die $base->name;
    }

    my $times = 1;
    $times = 20 if $ENV{TEST_LONG};

    my $seconds = 0;
    LOOP: for my $count0 ( 0 .. $times ) {
        my $count_created=0;
        for my $count1 ( 0 .. $n*_count_nodes($vm_name) ) {
            for my $base ( @bases ) {
                next if !$base->is_base;

                next if $base->list_requests > 10;
                last LOOP if _too_loaded("clone");
                last LOOP if !$ENV{TEST_LONG} && _volatiles_in_nodes($base);

                my $user = create_user(new_domain_name(),$$);
                my $ip = (0+$count0.$count1) % 255;

                my $name = new_domain_name();
                my $info = $base->info(user_admin);
                my $mem = $info->{max_mem};
                Ravada::Request->clone(
                    uid => $user->id
                    ,id_domain => $base->id
                    ,remote_ip => "192.168.122.$ip"
                    ,start => 1
                    ,name => $name
                    ,options => { network => $network_name }
                );
                delete_request('set_time','force_shutdown');
                $count_created++;
                next if $vm_name eq 'Void';
                if (_slightly_loaded() ) {
                    wait_request(debug => 1);
                    _wait_ip($name,$seconds++);
                }
                last if _too_loaded();
            }
        }
        login($USERNAME, $PASSWORD);
        for my $base ( @bases ) {
            for ( 1 .. 10 ) {
                last if _too_loaded("waiting");
                wait_request();
                last if $base->clones >= $n || !$base->list_requests;
                sleep 1;
            }
            for my $clone ( $base->clones ) {
                $t->get_ok("/machine/remove/".$clone->{id}.".json")->status_is(200);
                delete_request('set_time','force_shutdown');
            }
            $t->get_ok('/machine/remove_clones/'.$base->id.".json");
        }
        wait_request();
    }
    for my $base ( @bases ) {
        $t->get_ok('/machine/remove_clones/'.$base->id.".json");
    }
}

sub _volatiles_in_nodes($base) {
    my %vms;
    for my $clone ( $base->clones ) {
        next if !$clone->{is_volatile};
        $vms{$clone->{id_vm}}++;
    }
    return scalar(keys(%vms));
}

sub _search_domain_by_name($name) {
    my $sth = connector->dbh->prepare("SELECT id FROM domains "
        ." WHERE name=?"
    );
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    return $id;
}

sub _slightly_loaded($msg="") {
    open my $in,"<","/proc/loadavg" or die $!;
    my ($load) = <$in>;
    close $in;
    chomp $load;
    $load =~ s/\s.*//;
    return $load>$MAX_LOAD/3;
}


sub _too_loaded($msg="") {
    open my $in,"<","/proc/loadavg" or die $!;
    my ($load) = <$in>;
    close $in;
    chomp $load;
    $load =~ s/\s.*//;
    return $load>$MAX_LOAD;
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
            my $file = $entry->{file};
            next if !$file || $file !~ m{/$base};
            push @remove,($file);
        }
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
    my $sth = connector->dbh->prepare("SELECT name,is_base FROM domains "
            ." WHERE vm=?"
            ." AND name like 'tst_%'"
    );
    $sth->execute($vm_name);

    my $base_name = base_domain_name();
    while (my ($name, $is_base) = $sth->fetchrow) {
        next if $vm_name eq 'KVM' && $is_base;
        next if $name !~ /^$base_name/;
        Ravada::Request->remove_domain(uid => user_admin->id
            ,name => $name
        );
    }
}

sub _clean_old_bases($vm_name) {
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

        my $new_name = base_domain_name()."-".$vm_name."-$name";
        my $base = rvd_front->search_domain($new_name);
        next if !$base;

        $sth_clones->execute($base->id);
        while (my ($id, $name)=$sth_clones->fetchrow) {
            next if !$name;
            Ravada::Request->remove_domain(name => $name
                   ,uid => user_admin->id
           );
        }
    }
    wait_request();
}

sub _clean_old($vm_name) {
    _clean_old_bases($vm_name);
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

_start_nodes();
remove_networks_req();

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

_init();
Test::Ravada::_discover();

_init_mojo_client();
login();

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {
    diag("Testing volatile clones in $vm_name");

    _clean_old($vm_name);

    test_clone($vm_name);
}

remove_old_domains_req(0); # 0=do not wait for them
remove_networks_req();

end();
done_testing();
