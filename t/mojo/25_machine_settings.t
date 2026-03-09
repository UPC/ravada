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

########################################################################
sub create_machine($vm_name) {
    my $name = new_domain_name();
    my $iso_name = 'Alpine%';
    mojo_check_login($t);
    $t->post_ok('/new_machine.html' => form => {
            backend => $vm_name
            ,id_iso => search_id_iso($iso_name)
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,start => 0
            ,submit => 1
        }
    )->status_is(302);
    wait_request();
    my $base;
    for ( 1 .. 120 ) {
        $base = rvd_front->search_domain($name);
        last if $base;
        sleep 1;
        diag("waiting for $name");
    }
    return $base;

}

sub test_change_owner($domain) {
    my $pass = "$$ $$";
    my $name = new_domain_name();
    my $user = Ravada::Auth::SQL->new(name => $name );
    $user->remove();
    $user = create_user($name, $pass);
    $t->post_ok("/machine/set" =>
    json => {id => $domain->id
        , options => { owner => { name => $name, id => $user->id }}});

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $domain2 = Ravada::Front::Domain->open($domain->id);
    is($domain2->_data('id_owner'), $user->id);
}

sub test_change_settings($domain) {
    my $info = $domain->info(user_admin);
    my %new = (
        autostart => 1
        , shutdown_disconnected => 1
        , volatile_clones => 1
        , max_virt_cpu => 3
        , n_virt_cpu => 2
        , max_mem => 3000
        , memory => 2048
        , shutdown_grace_time => 20
        , auto_compact => 1
        , balance_policy => 1
    );
    my %old;
    for my $field (sort keys %new) {
        next if !exists $info->{$field};
        die "Error: domain ".$domain->name." already $field = ".$new{$field}
            if $info->{$field} eq $new{$field};
    
        $t->post_ok("/machine/set" =>
        json => {id => $domain->id
        , options => { $field => $new{$field}}});

        wait_request() if $field =~ /mem|cpu/;
        my $info2 = $domain->info(user_admin);
        if ($field =~ /mem/) {
            is(int($info2->{$field}/1024), $new{$field}, $field) or exit;
        } else {
            is($info2->{$field}, $new{$field}, $field) or exit;
        }
        $old{$field} = $info->{$field};
    }
    $t->post_ok("/machine/set" =>
        json => {id => $domain->id, %old });
    wait_request();

    my $info3 = $domain->info(user_admin);
    for my $field (sort keys %old) {
        if ($field =~ /mem/) {
            is(int($info3->{$field}/1024), $new{$field}, $field) or exit;
        } else {
            is($info3->{$field}, $new{$field}, $field) or exit;
        }
    }
}

########################################################################
$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);

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

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {

    diag("Testing machine settings in $vm_name");
    my $base = create_machine($vm_name);
    test_change_settings($base);
    test_change_owner($base);

}

end();

done_testing();
