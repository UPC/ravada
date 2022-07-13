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
    $t->get_ok('/'.$item.'/settings/'.$id.'.html');
    is($t->tx->res->code(),200) or die $t->tx->res->body;
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

sub _remove_network($address) {
    my @list_networks = Ravada::Network::list_networks();

    my ($found) = grep { $_->{address} eq $address} @list_networks;
    return if !$found;

    $t->get_ok("/v1/network/remove/".$found->{id});
    is($t->tx->res->code(),200) or die $t->tx->res->body;

}

sub test_networks($vm_name) {
    mojo_check_login($t);
    my $name = new_domain_name();
    my $address = '1.2.3.0/24';

    _remove_network($address);

    $t->post_ok('/v1/network/set' => json => {
        name => $name
        , address =>  $address    });
    is($t->tx->res->code(),200) or die $t->tx->res->to_string();

    exit if !$t->success;

    my @list_networks = Ravada::Network::list_networks();
    my ($found) = grep { $_->{name} eq $name } @list_networks;
    ok($found,"Expecting $name in list vms ".Dumper(\@list_networks)) or return;
    my $id_network = $found->{id};

    my $name2 = new_domain_name();
    $t->post_ok("/v1/network/set", json => {
            id => $found->{id}
            , name => $name2
        }
    );
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    @list_networks = Ravada::Network::list_networks();
    ($found) = grep { $_->{id} == $id_network } @list_networks;
    is($found->{name}, $name2) or die Dumper($found);

    my $new_name = new_domain_name();
    $t->post_ok("/v1/network/set", json => {
            id => $id_network
            , name => $new_name
        }
    );

    @list_networks = Ravada::Network::list_networks();

    ($found) = grep { $_->{id} == $id_network } @list_networks;
    is($found->{name}, $new_name) or die Dumper(\@list_networks);

    test_exists_network($id_network, 'name', $new_name);
    test_exists_network($id_network, 'address', $address);

    test_settings_item( $id_network, 'network' );

    $t->get_ok("/v1/network/remove/".$found->{id});
    is($t->tx->res->code(),200) or die $t->tx->res->body;

    ok(! grep { $_->{id} == $found->{id} } Ravada::Network::list_networks());

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
    $href=~ s/(.*)\{\{machine.id}}(.*)/${1}1$2/;
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

sub clean_clones() {
    wait_request( check_error => 0, background => 1);
    for my $domain (@{rvd_front->list_domains}) {
        my $base_name = base_domain_name();
        next if $domain->{name} !~ /$base_name/;
        remove_domain_and_clones_req($domain,0);
    }
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

test_missing_routes();

for my $vm_name (@{rvd_front->list_vm_types} ) {

    diag("Testing settings in $vm_name");

    test_nodes( $vm_name );
    test_networks( $vm_name );
}

clean_clones();

done_testing();
