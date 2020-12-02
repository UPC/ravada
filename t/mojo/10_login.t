use warnings;
use strict;

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

########################################################################################

sub remove_machines(@machines) {
    my $t0 = time;
    for my $name ( @machines ) {
        my $domain = rvd_front->search_domain($name) or next;
        remove_domain_and_clones_req($domain,1); #remove and wait
    }
    _wait_request(debug => 1, background => 1, timeout => 120);
}

sub _wait_request(@args) {
    my $t0 = time;
    wait_request(@args);

    if ( time - $t0 > $SECONDS_TIMEOUT ) {
        login();
    }

}


sub login( $user=$USERNAME, $pass=$PASSWORD ) {
    $t->ua->get($URL_LOGOUT);

    $t->post_ok('/login' => form => {login => $user, password => $pass});
    like($t->tx->res->code(),qr/^(200|302)$/);
    #    ->status_is(302);

    exit if !$t->success;
}

sub test_many_clones($base) {
    login();

    my $n_clones = 30;
    $n_clones = 100 if $base->type =~ /Void/i;

    $n_clones = 10 if !$ENV{TEST_STRESS} && ! $ENV{TEST_LONG};

    $t->post_ok('/machine/copy' => json => {id_base => $base->id, copy_number => $n_clones});
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;

    my $response = $t->tx->res->json();
    ok(exists $response->{request}) or return;
    wait_request(request => $response->{request}, background => 1);

    login();
    $t->post_ok('/request/start_clones' => json =>
        {   id_domain => $base->id
        }
    );
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;
    $response = $t->tx->res->json();
    ok(exists $response->{request}) and do {
        wait_request(request => $response->{request}, background => 1);
    };

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

sub test_re_expose($base) {
    diag("Test re-expose");
    for my $clone ( $base->clones ) {
        my $req = Ravada::Request->force_shutdown_domain(
            id_domain => $clone->{id}
            , uid => user_admin->id
        )
    }
    wait_request(background => 1);
    Ravada::Request->expose(uid => user_admin->id, id_domain => $base->id, port => 22);
    wait_request(background => 1);

    for my $clone ( $base->clones ) {
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

sub test_login_fail {
    $t->post_ok('/login' => form => {login => "fail", password => 'bigtime'});
    is($t->tx->res->code(),403);
    $t->get_ok("/admin/machines")->status_is(401);
    is($t->tx->res->dom->at("button#submit")->text,'Login') or exit;

    login();

    $t->post_ok('/login' => form => {login => "fail", password => 'bigtime'});
    is($t->tx->res->code(),403);

    $t->get_ok("/admin/machines")->status_is(401);
    is($t->tx->res->dom->at("button#submit")->text,'Login') or exit;
}

sub test_copy_without_prepare($clone) {
    is ($clone->is_base,0) or die "Clone ".$clone->name." is supposed to be non-base";

    my $n_clones = 3;
    mojo_request($t, "clone", { id_domain => $clone->id, number => $n_clones });
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);

    my @clones = $clone->clones();
    is(scalar @clones, $n_clones) or exit;

    remove_machines($clone);
}

sub test_validate_html($url) {
    $t->get_ok($url)->status_is(200);
    my $content = $t->tx->res->body();
    _check_html_lint($url,$content);
}

sub test_validate_html_local($dir) {
    opendir my $ls,$dir or die "$! $dir";
    while (my $file = readdir $ls) {
        next unless $file =~ /html$/ || $file =~ /.html.ep$/;
        my $path = "$dir/$file";
        open my $in,"<", $path or die "$path";
        my $content = join ("",<$in>);
        close $in;
        _check_html_lint($path,$content, {internal => 1});
    }
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
        if ( $error->errtext =~ /Unknown element <(footer|header|nav)/
            || $error->errtext =~ /Entity && is unknown/
            || $error->errtext =~ /should be written as/
            || $error->errtext =~ /Unknown attribute.*%/
            || $error->errtext =~ /Unknown attribute "ng-/
            || $error->errtext =~ /Unknown attribute "(aria|align|autofocus|data-|href|novalidate|placeholder|required|tabindex|role|uib-alert)/
            || $error->errtext =~ /img.*(has no.*attributes|does not have ALT)/
            || $error->errtext =~ /Unknown attribute "(min|max).*input/ # Check this one
            || $error->errtext =~ /Unknown attribute "(charset|crossorigin|integrity)/
            || $error->errtext =~ /Unknown attribute "image.* for tag <div/
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

########################################################################################

$ENV{MOJO_MODE} = 'devel';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

test_validate_html_local("templates/bootstrap");
test_validate_html_local("templates/main");
test_validate_html_local("templates/ng-templates");

if (!rvd_front->ping_backend) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}

remove_old_domains_req();

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);
my @bases;
my @clones;

test_login_fail();

test_validate_html("/login");

for my $vm_name (@{rvd_front->list_vm_types} ) {

    diag("Testing new machine in $vm_name");

    my $name = new_domain_name()."-".$vm_name;
    remove_machines($name,"$name-".user_admin->name);

    _init_mojo_client();

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
    push @bases,($base->name);

    mojo_request($t, "add_hardware", { id_domain => $base->id, name => 'network' });
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);

    test_validate_html("/machine/manage/".$base->id.".html");

    $t->get_ok("/machine/prepare/".$base->id.".json")->status_is(200);
    for ( 1 .. 10 ) {
        $base = rvd_front->search_domain($name);
        last if $base->is_base || !$base->list_requests;
        _wait_request(debug => 1, background => 1, check_error => 1);
    }
    is($base->is_base,1) or next;

    is(scalar($base->list_ports),0);
    mojo_check_login($t);
    $t->get_ok("/machine/clone/".$base->id.".json")->status_is(200);
    _wait_request(debug => 0, background => 1, check_error => 1);
    my $clone = rvd_front->search_domain($name."-".user_admin->name);
    ok($clone,"Expecting clone created") or next;
    ok($clone->name);
    if ($clone) {
        is($clone->is_volatile,0) or exit;
        is(scalar($clone->list_ports),0);
    }

    push @bases, ( $clone );
    mojo_check_login($t);
    test_copy_without_prepare($clone);
    mojo_check_login($t);
    test_many_clones($base);
}
ok(@bases,"Expecting some machines created");
remove_machines(@bases);
_wait_request(background => 1);
remove_old_domains_req(0); # 0=do not wait for them

done_testing();
