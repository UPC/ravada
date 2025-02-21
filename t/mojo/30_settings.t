use warnings;
use strict;

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

my %FILES;
my %HREFS;

my %MISSING_LANG = map {$_ => 1 }
    qw(ca-valencia cs he ko);

my $ID_DOMAIN;

sub _remove_nodes($vm_name) {
    my @list_nodes = rvd_front->list_vms();

    my $name = base_domain_name();
    my @found = grep { $_->{name} =~ /^$name/} @list_nodes;

    for my $found (@found) {

        $t->get_ok("/v1/node/remove/".$found->{id});
        is($t->tx->res->code(),200) or die $t->tx->res->body;
    }

}

sub test_nodes($vm_name) {
    mojo_check_login($t);
    my $name = new_domain_name();

    _remove_nodes($vm_name);

    $t->post_ok('/v1/node/new' => form => {
        vm_type => $vm_name
        , name => $name
        , hostname => '1.2.3.99'
        , _submit => 1
    });
    is($t->tx->res->code(),200);

    exit if !$t->success;

    my @list_nodes = rvd_front->list_vms($vm_name);
    my ($found) = grep { $_->{name} eq $name } @list_nodes;
    ok($found,"Expecting $name in list vms ".Dumper(\@list_nodes)) or return;
    my $id_node = $found->{id};

    my $name2 = new_domain_name();
    $t->post_ok("/v1/node/set", json => {
            id => $found->{id}
            , name => $name2
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    @list_nodes = rvd_front->list_vms($vm_name);
    ($found) = grep { $_->{id} == $id_node } @list_nodes;
    is($found->{name}, $name2) or die Dumper($found);

    my $new_hostname = new_domain_name();
    $t->post_ok("/v1/node/set", json => {
            id => $id_node
            , hostname => $new_hostname
        }
    );

    @list_nodes = rvd_front->list_vms($vm_name);

    ($found) = grep { $_->{id} == $id_node } @list_nodes;
    is($found->{hostname}, $new_hostname) or die Dumper(\@list_nodes);

    test_exists_node( $id_node, $name2 );
    test_settings_item( $id_node, 'node' );

    $t->get_ok("/v1/node/remove/".$found->{id});
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    ok(! grep { $_->{id} == $found->{id} } rvd_front->list_vms($vm_name));

}

sub test_settings_item($id, $item) {
    $item = 'route' if $item eq 'network';
    my $url = '/'.$item.'/settings/'.$id.'.html';
    $t->get_ok($url);
    is($t->tx->res->code(),200, "Expecting $url") or die $t->tx->res->body;
}

sub test_exists_node($id_node, $name) {
    $t->post_ok("/v1/exists/vms", json => {
            id => $id_node
            , name => $name
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $result_exists = decode_json($t->tx->res->body);
    is($result_exists->{id},undef);

    $t->post_ok("/v1/exists/vms", json => {
            name => $name
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    $result_exists = decode_json($t->tx->res->body);
    is($result_exists->{id}, $id_node);
}

sub test_exists_network($id_network, $field, $name) {
    $t->post_ok("/v1/exists/networks", json => {
            id => $id_network
            , $field => $name
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $result_exists = decode_json($t->tx->res->body);
    is($result_exists->{id},undef);

    $t->post_ok("/v1/exists/networks", json => {
            $field => $name
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    $result_exists = decode_json($t->tx->res->body);
    is($result_exists->{id}, $id_network);
}

sub _remove_route($address) {
    my @list_networks = Ravada::Route::list_networks();

    my ($found) = grep { $_->{address} eq $address} @list_networks;
    return if !$found;

    $t->get_ok("/v2/route/remove/".$found->{id});
    is($t->tx->res->code(),200) or die $t->tx->res->body;

}

sub _remove_networks($id_vm) {
    my $sth = connector->dbh->prepare("SELECT vn.id FROM virtual_networks vn, vms v"
        ." WHERE vn.id_vm=v.id "
        ."   AND v.id=? AND vn.name like ?"
    );
    $sth->execute($id_vm, base_domain_name."%");

    while ( my ($id) = $sth->fetchrow) {
        my $id_req = mojo_request($t, "remove_network", { id => $id});
        if ($id_req) {
            my $req = Ravada::Request->open($id_req);
            die "Error in ".$req->command." id=$id" if $req->error;
        }
    }

}

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare("SELECT id,hostname FROM vms "
        ." WHERE vm_type=? AND is_active=1");
    $sth->execute($vm_name);
    my @vm;
    while (my $row = $sth->fetchrow_hashref ) {
        push @vm,($row);
    }
    my ($vm) = grep { $_->{hostname} eq 'localhost' } @vm;

    my $id_vm;
    $id_vm = $vm->{id}      if $vm;
    $id_vm = $vm[0]->{id}   if !$id_vm;

    return $id_vm;
}

sub test_networks_access($vm_name) {

    my ($name, $pass) = (new_domain_name, "$$ $$");
    my $user = create_user($name, $pass,0 );
    is($user->is_admin,0 );
    mojo_login($t, $name, $pass);

    my $id_vm = _id_vm($vm_name);

    my @urls =(
        "/admin/networks", "/network/new"
        , "/v2/vm/list_networks/$id_vm","/v2/network/new/".$id_vm);
    for my $url (@urls) {
        $t->get_ok($url)->status_is(403);
    }

    user_admin->grant($user,'create_networks');
    for my $url (@urls) {
        $t->get_ok($url)->status_is(200);
    }

    user_admin->revoke($user,'create_networks');
    user_admin->grant($user,'manage_all_networks');
    for my $url (@urls) {
        $t->get_ok($url)->status_is(200);
    }

    $user->remove();
    mojo_login($t, $USERNAME, $PASSWORD);

}

sub test_networks_access_grant($vm_name) {

    my ($name, $pass) = (new_domain_name, "$$ $$");
    my $user = create_user($name, $pass,0 );
    user_admin->grant($user,"create_networks");
    mojo_login($t, $name, $pass);

    my $id_vm = _id_vm($vm_name);

    $t->post_ok("/v2/network/new/".$id_vm => json => { name => base_domain_name() });
    my $data = decode_json($t->tx->res->body);
    ok(keys %$data) or die Dumper($data);

    $t->post_ok("/v2/network/set/" => json => $data );
    my $new_ok = decode_json($t->tx->res->body);
    ok($new_ok->{id_network}) or return;

    $t->get_ok("/settings/network".$new_ok->{id_network}.".html");

    $t->get_ok("/v2/vm/list_networks/".$id_vm);
    my $networks2 = decode_json($t->tx->res->body);
    my ($old) = grep { $_->{name} ne $data->{name} } @$networks2;
    ok($old,"Expecting more networks for VM $vm_name [ $id_vm ]")
        or die Dumper([map {$_->{name} } @$networks2]);

    is($old->{_can_change},0) or exit;

    $t->get_ok("/network/settings/".$old->{id}.".html")->status_is(403);
    $old->{autostart}=0;

    $t->post_ok("/v2/network/set/" => json => $old)->status_is(403);

    my ($new) = grep { $_->{name} eq $data->{name} } @$networks2;
    ok($new,"Expecting new network $data->{name}")
        or die Dumper([map {$_->{name} } @$networks2]);
    is($new->{_owner}->{id},$user->id);
    is($new->{_can_change},1) or exit;

    for ( 1 .. 2 ) {
        $new->{is_active} = (!$new->{is_active} or 0);
        $t->post_ok("/v2/network/set/" => json => $new)->status_is(200);
        wait_request();

        $t->get_ok("/v2/vm/list_networks/".$id_vm);

        my $networks3 = decode_json($t->tx->res->body);
        my ($net3) = grep { $_->{name} eq $new->{name}} @$networks3;
        is($net3->{is_active}, $new->{is_active}) or exit;
    }

    for ( 1 .. 2 ) {
        $new->{is_public} = (!$new->{is_public} or 0);
        $t->post_ok("/v2/network/set/" => json => $new)->status_is(200);
        wait_request();

        $t->get_ok("/v2/vm/list_networks/".$id_vm);
        my $networks4 = decode_json($t->tx->res->body);
        my ($net4) = grep { $_->{name} eq $new->{name}} @$networks4;
        is($net4->{is_public}, $new->{is_public}) or exit;
    }

    mojo_login($t, $USERNAME, $PASSWORD);

}

sub test_networks_admin($vm_name) {
    mojo_check_login($t);

    for my $url (qw( /admin/networks/ /network/new) ) {
        $t->get_ok($url);
        is($t->tx->res->code(),200, "Expecting access to $url");
    }

    my $id_vm = _id_vm($vm_name);
    die "Error: I can't find if for vm type = $vm_name" if !$id_vm;

    _remove_networks($id_vm);

    $t->get_ok("/v2/vm/list_networks/".$id_vm);
    my $networks = decode_json($t->tx->res->body);
    ok(scalar(@$networks));

    $t->post_ok("/v2/network/new/".$id_vm => json => { name => base_domain_name() });
    my $data = decode_json($t->tx->res->body);

    $t->post_ok("/v2/network/set/" => json => $data );

    my $new_ok = decode_json($t->tx->res->body);
    ok($new_ok->{id_network}) or die Dumper([$t->tx->res->body, $new_ok]);

    $t->get_ok("/v2/vm/list_networks/".$id_vm);
    my $networks2 = decode_json($t->tx->res->body);
    my ($new) = grep { $_->{name} eq $data->{name} } @$networks2;

    ok($new);
    is($new->{_can_change},1) or exit;
    is($new->{_owner}->{id},user_admin->id) or exit;
    $new->{is_active} = 0;

    $t->post_ok("/v2/network/set/" => json => $new);
    wait_request(debug => 1);
    $t->get_ok("/v2/vm/list_networks/".$id_vm);

    my $networks3 = decode_json($t->tx->res->body);
    my ($changed) = grep { $_->{name} eq $data->{name} } @$networks3;
    is($changed->{is_active},0) or die $changed->{name};

    $t->get_ok("/v2/network/info/".$changed->{id});

    my $changed4 = decode_json($t->tx->res->body);
    is($changed4->{is_active},0) or exit;

    $new->{is_public}=1;
    $t->post_ok("/v2/network/set/" => json => $new);
    wait_request(debug => 1);
    $t->get_ok("/v2/vm/list_networks/".$id_vm);

    my $networks5 = decode_json($t->tx->res->body);
    my ($changed5) = grep { $_->{name} eq $data->{name} } @$networks5;
    is($changed5->{is_public},1) or warn Dumper($changed5);

}

sub test_routes($vm_name) {
    mojo_check_login($t);
    my $name = new_domain_name();
    my $address = '1.2.3.0/24';

    _remove_route($address);

    $t->post_ok('/v2/route/set' => json => {
        name => $name
        , address =>  $address    });
    is($t->tx->res->code(),200) or die $t->tx->res->to_string();

    exit if !$t->success;

    my @list_networks = Ravada::Route::list_networks();
    my ($found) = grep { $_->{name} eq $name } @list_networks;
    ok($found,"Expecting $name in list vms ".Dumper(\@list_networks)) or return;
    my $id_network = $found->{id};

    my $name2 = new_domain_name();
    $t->post_ok("/v2/route/set", json => {
            id => $found->{id}
            , name => $name2
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    @list_networks = Ravada::Route::list_networks();
    ($found) = grep { $_->{id} == $id_network } @list_networks;
    is($found->{name}, $name2) or die Dumper($found);

    my $new_name = new_domain_name();
    $t->post_ok("/v2/route/set", json => {
            id => $id_network
            , name => $new_name
        }
    );

    @list_networks = Ravada::Route::list_networks();

    ($found) = grep { $_->{id} == $id_network } @list_networks;
    is($found->{name}, $new_name) or die Dumper(\@list_networks);

    test_exists_network($id_network, 'name', $new_name);
    test_exists_network($id_network, 'address', $address);

    test_settings_item( $id_network, 'network' );

    $t->get_ok("/v2/route/remove/".$found->{id});
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    ok(! grep { $_->{id} == $found->{id} } Ravada::Route::list_networks());

}

sub _find_files($dir) {
    return @{$FILES{$dir}} if exists $FILES{$dir};
    open my $find ,"-|", "find $dir -type f" or die $!;
    my @found;
    while (my $file =<$find>) {
        chomp $file;
        push @found,($file);
    }
    close $find;
    $FILES{$dir} = \@found;
    return @found;
}

sub _hrefs($file) {
    return @{$HREFS{$file}} if exists $HREFS{$file};
    open my $in,"<",$file or confess "$! $file";
    my @href;
    for my $line ( <$in> ) {
        chomp $line;
        my ($found) = $line =~ /href=["'](.*?)["']/;
        next if $found && $found =~ /^\?/;
        push @href,($found) if $found;
    }
    close $in;
    $HREFS{$file} = \@href;
    return @href;
}

sub _search_path_templates($path) {
    for my $file (_find_files("templates")) {
        for my $href ( _hrefs($file) ) {
            return 1 if $href eq $path;
        }
    }
    return 0;
}

sub _search_path($path) {
   return _search_path_templates($path);
}

# Check for unused routes
sub test_unused_routes() {
    my $routes = $t->app->routes->children;
    for my $route (@$routes){
        my $render = $route->render();
        my $unparsed = $route->pattern->unparsed();
        next if $render =~ m{^/robots.txt} || $render eq '/'
        || $render =~ m{^/(anonymous|login|test)$}
        || $render =~ m{^/(index).html}
        || $render eq '/anonymous_logout.html'
        || $unparsed eq '/anonymous/(#base_id).html'
        ;

        ok(_search_path($render), Dumper($unparsed,$render)) or exit;
    }
}

sub _fill_href($href) {
    $href=~ s/(.*)\{\{machine.id}}(.*)/${1}$ID_DOMAIN$2/;

    $href =~ s/(.*)\{\{.*vm_type}}(.*)/${1}kvm$2/;
    $href =~ s/(.*)\{\{showmachine.type}}(.*)/${1}kvm$2/;

    return $href;
}

sub test_missing_routes() {
    my %done;
    for my $file ( _find_files('templates') ) {
        for my $href (_hrefs($file) ) {
            next if $done{$href}++;
            next if $href =~ m{^#};
            next if $href =~ m{^(http|https)://};
            next if $href =~ m{^<%=.*?%>$};
            next if $href =~ m/^\{\{.*?}}$/;
            next if $href =~ m/^javascript/;
            next if $href =~ /anonymous/;

            my $href2 = _fill_href($href);
            mojo_check_login($t);
            $t->get_ok($href2, "file: $file href='$href'");
            like($t->tx->res->code(),qr/200|302|40\d+|500/) or die $t->tx->res->to_string();
        }
    }
    mojo_login($t, $USERNAME, $PASSWORD);
}

sub test_languages() {
    mojo_check_login($t);
    $t->get_ok("/translations");
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $lang = decode_json($t->tx->res->body);

    opendir my $ls,"lib/Ravada/I18N" or die $!;
    while (my $file = readdir $ls) {
        next if $file !~ /(.*)\.po$/;
        next if $MISSING_LANG{$1};
        ok($lang->{$1},"Expecting $1 in select");
    }
}

sub clean_clones() {
    wait_request( check_error => 0, background => 1);
    for my $domain (@{rvd_front->list_domains}) {
        my $base_name = base_domain_name();
        next if $domain->{name} !~ /$base_name/;
        remove_domain_and_clones_req($domain,0);
    }
}

sub _create_storage_pool($id_vm , $vm_name) {
    $t->get_ok("/list_storage_pools/$vm_name");
    my $sp = decode_json($t->tx->res->body);
    my $name = new_pool_name();
    my ($found) = grep { $_->{name} eq $name } @$sp;
    return $name if $found;

    my $dir0 = "/var/tmp/$$/";

    mkdir $dir0 if !-e $dir0;

    my $dir = $dir0."/".new_pool_name();

    mkdir $dir or die "$! $dir" if !-e $dir;


    my $req = Ravada::Request->create_storage_pool(
        uid => user_admin->id
        ,id_vm => $id_vm
        ,name => $name
        ,directory => $dir
    );
    wait_request( );
    is($req->error,'');

    return $name;
}

sub test_storage_pools($vm_name) {

    my $id_vm = _id_vm($vm_name);
    my $sp_name = _create_storage_pool($id_vm, $vm_name);

    $t->get_ok("/list_storage_pools/$vm_name");

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $sp = decode_json($t->tx->res->body);
    ok(scalar(@$sp));

    $t->get_ok("/list_storage_pools/$id_vm");

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $sp_id = decode_json($t->tx->res->body);
    ok(scalar(@$sp_id));
    is_deeply($sp_id, $sp);

    my ($sp_inactive) = grep { $_->{name} ne 'default' } @$sp_id;

    my $name_inactive= $sp_inactive->{name};
    die "Error, no name in ".Dumper($sp_inactive) if !$name_inactive;

    mojo_request($t, "active_storage_pool"
        ,{ id_vm => $id_vm, name => $name_inactive, value => 0 });

    $t->get_ok("/list_storage_pools/$vm_name?active=1");

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $sp_active = decode_json($t->tx->res->body);
    my ($found) = grep { $_->{name} eq $name_inactive } @$sp_active ;
    ok(!$found,"Expecting $name_inactive not found");

    mojo_request($t, "active_storage_pool"
        ,{ id_vm => $id_vm, name => $name_inactive, value => 1 });

    $t->get_ok("/list_storage_pools/$vm_name?active=1");
    $sp_active = decode_json($t->tx->res->body);
    ok(scalar(@$sp_active));
    ($found) = grep { $_->{name} eq $name_inactive } @$sp_active ;
    ok($found,"Expecting $name_inactive found");

}

sub  _search_public_base() {
    my $sth = connector->dbh->prepare(
        "SELECT id FROM domains WHERE is_public=1 "
        ." AND name <> 'ztest'"
    );
    $sth->execute();
    my ($id) = ($sth->fetchrow or '999');
    return $id;
}

########################################################################################

$ENV{MOJO_MODE} = 'devel';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

if (!rvd_front->ping_backend) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

($USERNAME, $PASSWORD) = ( user_admin->name, "$$ $$");

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

mojo_login($t, $USERNAME, $PASSWORD);

remove_old_domains_req(0); # 0=do not wait for them
clean_clones();

$ID_DOMAIN = _search_public_base();

test_languages();
test_missing_routes();

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {

    diag("Testing settings in $vm_name");

    test_networks_access( $vm_name );
    test_networks_access_grant($vm_name);
    test_networks_admin( $vm_name );
    test_storage_pools($vm_name);
    test_nodes( $vm_name );
    test_routes( $vm_name );
}

clean_clones();
remove_old_users();

done_testing();
