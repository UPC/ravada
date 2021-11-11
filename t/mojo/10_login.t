use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use HTML::Lint;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $t;

my $URL_LOGOUT = '/logout';
my ($USERNAME, $PASSWORD);
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my $BASE_NAME = "zz-test-base-alpine";
########################################################################################

sub remove_machines(@machines) {
    my $t0 = time;
    for my $name ( @machines ) {
        my $domain = rvd_front->search_domain($name) or next;
        remove_domain_and_clones_req($domain,1); #remove and wait
    }
    _wait_request(debug => 0, background => 1, timeout => 120);
}

sub _wait_request(@args) {
    my $t0 = time;
    wait_request(@args);

    if ( $USERNAME && time - $t0 > $SECONDS_TIMEOUT ) {
        login();
    }

}


sub login( $user=$USERNAME, $pass=$PASSWORD ) {
    $t->ua->get($URL_LOGOUT);

    confess "Error: missing user" if !defined $user;

    $t->post_ok('/login' => form => {login => $user, password => $pass});
    like($t->tx->res->code(),qr/^(200|302)$/);
    #    ->status_is(302);

    exit if !$t->success;
    mojo_check_login($t, $user, $pass);
}

sub test_many_clones($base) {
    login();

    my $n_clones = 30;
    $n_clones = 100 if $base->type =~ /Void/i;

    $n_clones = 10 if !$ENV{TEST_STRESS} && ! $ENV{TEST_LONG};

    $t->post_ok('/machine/copy' => json => {id_base => $base->id, copy_number => $n_clones, copy_ram => 0.128 });
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;

    my $response = $t->tx->res->json();
    ok(exists $response->{request}) or return;
    wait_request(request => $response->{request}, background => 1);

    login();
    my $sequential = 0;
    $sequential = 1 if $base->type eq 'Void';
    $t->post_ok('/request/start_clones' => json =>
        {   id_domain => $base->id, sequential => $sequential
        }
    );
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;
    $response = $t->tx->res->json();
    if (exists $response->{request}) {
        wait_request(request => $response->{request}, background => 1);
    } else {
        warn Dumper($response);
    };

    wait_request(debug => 0, background => 1);
    ok(scalar($base->clones)>=$n_clones);

    test_iptables_clones($base);
    test_re_expose($base) if $base->type eq 'Void';
    test_different_mac($base, $base->clones) if $base->type ne 'Void';
    for my $clone ( $base->clones ) {
        my $req = Ravada::Request->remove_domain(
            name => $clone->{name}
            ,uid => user_admin->id
        );
    }
}

sub test_different_mac(@domain) {
    my %found;
    for my $domain (@domain) {
        $domain = Ravada::Front::Domain->open($domain->{id})
            if ref($domain) !~/^Ravada/;
        my $xml = XML::LibXML->load_xml(string => $domain->_data_extra('xml'));
        my (@if_mac) = $xml->findnodes('/domain/devices/interface/mac');
        for my $if_mac (@if_mac) {
            my $mac = $if_mac->getAttribute('address');
            ok(!exists $found{$mac},"Error: MAC $mac from ".$domain->name
                ." also in domain : ".($found{$mac} or '')) or exit;
            $found{$mac} = $domain->name;
        }
    }
}

sub test_iptables_clones($base) {
    delete_request('set_time','screenshot','refresh_machine_ports');
    wait_request(background => 1, debug => 0);
    my %port_display;
    for my $clone_data ( $base->clones ) {
        next if $clone_data->{is_base};
        if ($clone_data->{status} ne 'active') {
            diag("$clone_data->{name} $clone_data->{status}");
            next;
        }
        my $clone = Ravada::Front::Domain->open($clone_data->{id});
        wait_request();
        my $displays = $clone->info(user_admin)->{hardware}->{display};
        wait_request();
        for my $display (@$displays) {
            for my $port ($display->{port}, $display->{extra}->{tls_port}) {
                next if !defined $port;
                my $found = $port_display{$port};
                my $value = "$clone_data->{id} $display->{driver}:$port";
                ok(!$found,"Duplicated display $port on $clone_data->{name} $value and ".($found or "")) or exit;
                $port_display{$port} = $value;
            }
        }
    }
}

sub test_re_expose($base) {
    diag("Test re-expose");
    for my $clone ( $base->clones ) {
        my $req = Ravada::Request->shutdown_domain(
            id_domain => $clone->{id}
            , uid => user_admin->id
        )
    }
    wait_request(background => 1);
    Ravada::Request->expose(uid => user_admin->id, id_domain => $base->id, port => 23);
    wait_request(background => 1);

    for my $clone ( $base->clones ) {
        next if $clone->{is_base};
        my $req = Ravada::Request->start_domain(
            id_domain => $clone->{id}
            , uid => user_admin->id
            , remote_ip => '1.2.3.4'
        );
    }
    wait_request(background => 1, check_error => 1);
}
sub _init_mojo_client {
    my $user_admin = user_admin();
    my $pass = "$$ $$";

    $USERNAME = $user_admin->name;
    $PASSWORD = $pass;

    login($user_admin->name, $pass);
    $t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);
}

sub test_login_non_admin($t, $base, $clone){
    mojo_check_login($t, $USERNAME, $PASSWORD);
    $t->get_ok("/machine/prepare/".$clone->id.".json")->status_is(200);
    for ( 1 .. 10 ) {
        my $clone2 = rvd_front->search_domain($clone->name);
        last if $clone2->is_base || !$clone2->list_requests;
        _wait_request(debug => 1, background => 1, check_error => 1);
        mojo_check_login($t, $USERNAME, $PASSWORD);
    }
    is($clone->is_base,1) or next;
    $clone->is_public(1);

    my $name = new_domain_name();
    my $pass = "$$ $$";
    my $user = Ravada::Auth::SQL->new(name => $name);
    $user->remove();
    $user = create_user($name, $pass);
    is($user->is_admin(),0);
    $base->is_public(0);

    login($name, $pass);
    $t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);


    $t->get_ok("/machine/clone/".$clone->id.".html")
    ->status_is(200);
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
    mojo_check_login($t, $name, $pass);

    my $clone_new_name = $base->name."-".$name;
    my $clone_new = rvd_front->search_domain($clone_new_name);
    ok(!$clone_new,"Expecting $clone_new_name does not exist") or exit;
    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(403);

    $clone_new = rvd_front->search_domain($clone_new_name);
    ok(!$clone_new,"Expecting $clone_new_name does not exist") or exit;

    $base->is_public(1);

    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(200);

    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
    $clone_new = rvd_front->search_domain($clone_new_name);
    ok($clone_new,"Expecting $clone_new_name does exist") or exit;

    mojo_check_login($t, $name, $pass);
    $base->is_public(0);

    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(200);
    exit if $t->tx->res->code() != 200;
}


sub test_login_fail {
    $t->post_ok('/login' => form => {login => "fail", password => 'bigtime'});
    is($t->tx->res->code(),403);
    $t->get_ok("/admin/machines")->status_is(401);
    like($t->tx->res->dom->at("button#submit")->text,qr'Login') or exit;

    login( user_admin->name, "$$ $$");

    $t->post_ok('/login' => form => {login => "fail", password => 'bigtime'});
    is($t->tx->res->code(),403);

    $t->get_ok("/admin/machines")->status_is(401);
    like($t->tx->res->dom->at("button#submit")->text,qr'Login') or exit;

    $t->get_ok("/admin/users")->status_is(401);
    like($t->tx->res->dom->at("button#submit")->text,qr'Login') or exit;
}

sub test_copy_without_prepare($clone) {
    login();
    is ($clone->is_base,0) or die "Clone ".$clone->name." is supposed to be non-base";

    my $base = Ravada::Front::Domain->open($clone->_data('id_base'));
    my $n_clones_clone= scalar($clone->clones());

    my $n_clones = 3;
    mojo_request($t, "clone", { id_domain => $clone->id, number => $n_clones });
    wait_request(debug => 0, check_error => 1, background => 1, timeout => 120);

    mojo_check_login($t);

    my @clones = $clone->clones();
    is(scalar @clones, $n_clones_clone+$n_clones,"Expecting clones from ".$clone->name) or exit;

    mojo_request($t, "spinoff", { id_domain => $clone->id  });
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
    # is($clone->id_base,0 );
    mojo_check_login($t);
    mojo_request($t, "clone", { id_domain => $clone->id, number => $n_clones });
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
    is($clone->is_base, 1 );
    my @n_clones_clone_2= $clone->clones();
    is(scalar @n_clones_clone_2, $n_clones_clone+$n_clones*2) or exit;

    remove_machines($clone);
}

sub test_validate_html($url) {
    mojo_check_login($t);
    $t->get_ok($url)->status_is(200);
    my $content = $t->tx->res->body();
    _check_html_lint($url,$content);
}


sub _check_count_divs($url, $content) {
    my $n = 0;
    my $open = 0;
    for my $line (split /\n/,$content) {
        $n++;
        die "Error: too many divs" if $line =~ m{<div.*<div.*<div};

        next if $line =~ m{<div.*<div.*/div>.*/div>};

        $open++ if $line =~ /<div/;
        $open-- if $line =~ m{</div};

        last if $open<0;
    }
    ok(!$open,"$open open divs in $url line $n") ;
}

sub _remove_embedded_perl($content) {
    my $return = '';
    my $changed = 0;
    for my $line (split /\n/,$$content) {
        if ($line =~ /<%=/) {
            $line =~ s/(.*)<%=.*?%>(.*)/$1$2/;
            $changed++;
        }
        $return .= "$line\n";
    }
    $$content = $return if $changed;
}

sub _check_html_lint($url, $content, $option = {}) {
    _remove_embedded_perl(\$content);
    _check_count_divs($url, $content);

    my $lint = HTML::Lint->new;
    #    $lint->only_types( HTML::Lint::Error::STRUCTURE );
    $lint->parse( $content );
    $lint->eof();

    my @errors;
    my @warnings;

    for my $error ( $lint->errors() ) {
        next if $error->errtext =~ /Entity .*is unknown/;
        next if $option->{internal} && $error->errtext =~ /(body|head|html|title).*required/;
        if ( $error->errtext =~ /Unknown element <(footer|header|nav|ldap-groups)/
            || $error->errtext =~ /Entity && is unknown/
            || $error->errtext =~ /should be written as/
            || $error->errtext =~ /Unknown attribute.*%/
            || $error->errtext =~ /Unknown attribute "ng-/
            || $error->errtext =~ /Unknown attribute "(aria|align|autofocus|data-|href|novalidate|placeholder|required|tabindex|role|uib-alert)/
            || $error->errtext =~ /img.*(has no.*attributes|does not have ALT)/
            || $error->errtext =~ /Unknown attribute "(min|max).*input/ # Check this one
            || $error->errtext =~ /Unknown attribute "(charset|crossorigin|integrity)/
            || $error->errtext =~ /Unknown attribute "image.* for tag <div/
            || $error->errtext =~ /Unknown attribute "ipaddress"/
            || $error->errtext =~ /Unknown attribute "sizes" for tag .link/
         ) {
             next;
         }
        if ($error->errtext =~ /attribute.*is repeated/
            || $error->errtext =~ /Unknown attribute/
            # TODO next one
            #|| $error->errtext =~ /img.*(has no.*attributes|does not have ALT)/
            || $error->errtext =~ /attribute.*is repeated/
        ) {
            push @warnings, ($error);
            next;
        }
        push @errors, ($error)
    }
    ok(!@errors, $url) or do {
        my $file_out = $url;
        $url =~ s{^/}{};
        $file_out =~ s{/}{_}g;
        $file_out = "/var/tmp/$file_out";
        open my $out, ">", $file_out or die "$! $file_out";
        print $out $content;
        close $out;
        die "Stored in $file_out\n".Dumper([ map { [$_->where,$_->errtext] } @errors ]);
    };
    ok(!@warnings,$url) or warn Dumper([ map { [$_->where,$_->errtext] } @warnings]);


}

sub test_logout_ldap {
    my ($username, $password) = ( new_domain_name(),$$);
    my $user = create_ldap_user( $username, $password);

    $t->post_ok('/login' => form => {login => $username, password => $password});
    is($t->tx->res->code(),302);

    $t->ua->get($URL_LOGOUT);

    $t->post_ok('/login' => form => {login => $username, password => 'bigtime'});
    is($t->tx->res->code(),403);

    $t->post_ok('/login' => form => {login => $username, password => $password});
    is($t->tx->res->code(),302);
}

sub _add_displays($t, $domain) {
    #    mojo_request($t, "add_hardware", { id_domain => $base->id, name => 'network' });
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
    wait_request(background => 1);

}

sub _clone_and_base($vm_name, $t, $base0) {
    mojo_check_login($t);
    my $base1 = $base0;
    if ($vm_name eq 'KVM') {
        my $base = rvd_front->search_domain($BASE_NAME);
        die "Error: test base $BASE_NAME not found" if !$base;
        my $name = new_domain_name()."-".$vm_name."-$$";
        mojo_request_url_post($t,"/machine/copy",{id_base => $base->id, new_name => $name, copy_ram => 0.128, copy_number => 1});
        $base1 = rvd_front->search_domain($name);
        ok($base1, "Expecting domain $name create") or exit;
    }

    mojo_check_login($t);
    _add_displays($t, $base1);
    mojo_check_login($t);
    mojo_request_url($t , "/machine/prepare/".$base1->id.".json");
    return $base1;
}

sub test_clone($base1) {
    $t->get_ok("/machine/clone/".$base1->id.".html")->status_is(200);
    my $body = $t->tx->res->body;
    my ($id_req) = $body =~ m{subscribe',(\d+)};

    my $req = Ravada::Request->open($id_req);
    ok($req, "Expecting request on /machine/clone") or return;
    for ( ;; ) {
        last if $req->status eq 'done' && $req->error !~ /Retry.?$/;
        warn $req->error if $req->status eq 'done';
        sleep 1;
    }
    ok($req->status,'done');
    is($req->error, '') or return;

    my $id_domain = $req->id_domain;
    my $clone = Ravada::Front::Domain->open($id_domain);

    my $clone_name  = $base1->name."-".user_admin->name;
    is($clone->name, $clone_name);
    ok($clone->name);
    is($clone->is_volatile,0) or exit;
    is(scalar($clone->list_ports),2);
    return $clone;
}

sub test_admin_can_do_anything($t, $base) {

    my $pass = "$$ $$";
    my $user = create_user(new_domain_name()."-$$", $pass, 1);

    login( $user->name, $pass );

    $t->get_ok("/machine/info/".$base->id.".json");
    is($t->tx->res->code(),200);

    my $response = $t->tx->res->json();
    for my $field( keys %$response) {
        next if $field !~ /^can_/;
        is($response->{$field},1,"Admin user ".$user->name
            ." should be able to $field ".$base->name)
    }

    login($USERNAME, $PASSWORD);

    $user->remove();
}

sub test_create_base($t, $vm_name, $name) {
    $t->post_ok('/new_machine.html' => form => {
            backend => $vm_name
            ,id_iso => search_id_iso('Alpine%')
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,submit => 1
        }
    )->status_is(302);

    _wait_request(debug => 1, background => 1, check_error => 1);
    my $base;
    for ( 1 .. 10 ) {
        $base = rvd_front->search_domain($name);
        last if $base;
        sleep 1;
    }
    ok($base, "Expecting domain $name create") or exit;
    return $base;
>>>>>>> e742c24c... test: do not clone private bases
}

########################################################################################

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
my @bases;
my @clones;

test_logout_ldap();

test_login_fail();

test_validate_html("/login");

remove_old_domains_req();

my $t0 = time;
diag("starting tests at ".localtime($t0));
for my $vm_name ( @{rvd_front->list_vm_types} ) {

    diag("Testing new machine in $vm_name");

    my $name = new_domain_name()."-".$vm_name;
    remove_machines($name,"$name-".user_admin->name);

    $name .= "-".$$;

    _init_mojo_client();

    my $base0 = test_create_base($t, $vm_name, $name);
    push @bases,($base0->name);
    test_admin_can_do_anything($t, $base0);

    my $base2 =test_create_base($t, $vm_name, new_domain_name()."-$vm_name");
    push @bases,($base2->name);

    mojo_request($t, "add_hardware", { id_domain => $base0->id, name => 'network' });
    wait_request(debug => 0, check_error => 1, background => 1, timeout => 120);
    mojo_check_login($t, $USERNAME, $PASSWORD);

    test_validate_html("/machine/manage/".$base0->id.".html");

    my $base1 = _clone_and_base($vm_name, $t, $base0);

    push @bases,($base1->name);
    is($base1->is_base,1) or next;

    is(scalar($base1->list_ports),2);
    mojo_check_login($t);

    my $clone = test_clone($base1);
    mojo_check_login($t);
    if ($clone) {
        push @bases, ( $clone->name );
        is($clone->is_volatile,0) or exit;
        is(scalar($clone->list_ports),0);
    }
    test_login_non_admin($t, $base, $base2);

    push @bases, ( $clone );
    mojo_check_login($t, $USERNAME, $PASSWORD);
    test_copy_without_prepare($clone);
    mojo_check_login($t, $USERNAME, $PASSWORD);
    test_many_clones($base);

    test_login_non_admin($t, $base, $base2);
    remove_old_domains_req(0); # 0=do not wait for them
    test_many_clones($base1);
    remove_machines(reverse @bases);
}
ok(@bases,"Expecting some machines created");
remove_machines(reverse @bases);
_wait_request(background => 1);
remove_old_domains_req(0); # 0=do not wait for them

done_testing();
