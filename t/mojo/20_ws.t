use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Mojo::JSON 'decode_json';
use Test::More;
use Test::Mojo;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $USERNAME;
my $PASSWORD = "$$ $$";

my $USER;

########################################################################################

=pod

sub _init_mojo_client {
    return if $USERNAME;
    $T->get_ok('/')->status_is(200)->content_like(qr/name="login"/);

    my $user_admin = user_admin();
    my $pass = "$$ $$";

    $USERNAME = $user_admin->name;
    $PASSWORD = $pass;

    mojo_login($T, $user_admin->name, $pass) or exit;
    $T->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);
}

=cut

sub list_machines_user($t, $headers={}){
    mojo_check_login($t);
    $t->websocket_ok("/ws/subscribe" => $headers)->send_ok("list_machines_user")->message_ok->finish_ok;

    confess if !$t->message || !$t->message->[1];

    my $name = base_domain_name();
    my @machines = grep { $_->{name} =~ /^$name/ } @{decode_json($t->message->[1])};
    _clean_machines_info(\@machines);
    return @machines;
}

sub _clean_machines_info($machines) {
    for (@$machines) {
        for my $key (keys %$_ ) {
            delete $_->{$key} unless $key =~ /id|name|base|clone/;
        }
    }
}

sub list_machines($t) {
    $t->websocket_ok("/ws/subscribe")->send_ok("list_machines")->message_ok->finish_ok;

    return if !$t->message || !$t->message->[1];

    my $name = base_domain_name();
    my @machines = grep { $_->{name} =~ /^$name/ } @{decode_json($t->message->[1])};
    _clean_machines_info(\@machines);
    return @machines;
}

sub _create_bases($t, $vm_name) {
    my @base;
    for ( 0 .. 1 ) {
        my $base =  mojo_create_domain($t, $vm_name);
        push @base, ($base);
    }
    return @base;
}

sub test_bases($t, $bases) {
    my $n_bases = 0;
    my $n_machines = scalar(@$bases);
    for my $base ( @$bases ) {
        $t->get_ok("/machine/prepare/".$base->id.".json")->status_is(200);
        wait_request(debug => 0, background => 1);
        $n_bases++;
        my @machines_user = list_machines_user($t);
        is(@machines_user, $n_bases, Dumper(\@machines_user)) or exit;
        my $n_clones = 2;
        mojo_request($t, "clone", { id_domain => $base->id, number => $n_clones });
        $n_machines += $n_clones;

        my @machines = list_machines($t);
        is( scalar(@machines), scalar(@$bases), Dumper(\@machines)) or exit;
    }
}

sub _login_non_admin($t) {
    my $user_name = base_domain_name().".doe";
    remove_old_user($user_name);
    $USER = create_user($user_name, $$);
    mojo_login($t, $user_name,$$);
}

sub test_bases_non_admin($t,$bases) {
    my $n_public = 0;
    for my $base (@$bases) {
        is(list_machines_user($t),$n_public);
        $base->is_public(1);
        is($base->is_public, 1);
        is(list_machines_user($t),++$n_public);
    }
}

sub test_list_machines_non_admin($t, $bases) {
    my $url = "/machine/clone/".$bases->[0]->id.".html";
    $t->get_ok($url)->status_is(200);
    wait_request(background => 1);
    my @list_bases = list_machines_user($t);
    my ($clone) = grep { $_->{name_clone} } @list_bases;
    ok($clone,Dumper(\@list_bases)) or exit;

    my @list_machines = list_machines($t);
    is(scalar(@list_machines),0);

    Ravada::Request->prepare_base(
        uid => user_admin->id
        ,id_domain => $clone->{id_clone}
    );
    wait_request(background => 1);
    user_admin->grant($USER,'shutdown_clones');

    @list_machines = list_machines($t);
    is(scalar(@list_machines),1) or exit;
}

sub test_bases_access($t,$bases) {
    for (@$bases) { $_->is_public(1) };

    my $base0 = $bases->[0];
    my      $type = 'client';
    my     $value = 'ca-ca';
    my $attribute = 'Accept-Language';
    $base0->grant_access(
              type => $type
        ,attribute => $attribute
            ,value => $value
    );

    my @list_machines = list_machines_user($t);
    is(scalar(@list_machines),1,Dumper(\@list_machines));

    $t->tx->req->headers->add( $attribute => $value );
    @list_machines = list_machines_user($t ,{ $attribute => $value });
    is(scalar(@list_machines),2) or exit;

    my @access = $base0->list_access('client');
    $base0->delete_access(@access);
    @access = $base0->list_access;
    is(scalar(@access),0,Dumper(\@access));

    @list_machines = list_machines_user($t);
    is(scalar(@list_machines),2);

    for (@$bases) { $_->is_public(0) };
}

########################################################################################

init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

if (!rvd_front->ping_backend()) {
    diag("SKIPPING: Backend not available");
    done_testing();
    exit;
}
mojo_clean();

$USERNAME = user_admin->name;
my $t = mojo_init();

for my $vm_name ( @{rvd_front->list_vm_types} ) {

    diag("Testing Web Services in $vm_name");

    mojo_login($t, $USERNAME, $PASSWORD);
    my @bases = _create_bases($t, $vm_name);
    is(list_machines_user($t), 0);
    is(list_machines($t), scalar(@bases)) or exit;

    test_bases($t,\@bases);

    _login_non_admin($t);
    test_bases_access($t,\@bases);

    test_bases_non_admin($t, \@bases);
    test_list_machines_non_admin($t,\@bases);
    test_bases_access($t,\@bases);

    remove_old_domains_req();
    while( list_machines_user($t) ) {
        remove_old_domains_req();
    }
}
mojo_clean($t);

done_testing();
