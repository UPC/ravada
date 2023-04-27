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
    like($t->tx->res->code(),qr/^(200|302)$/)
    or die $t->tx->res->body;
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
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body;

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
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body;
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

    my ($port_display, $dupe) = _fetch_ports_display($base);
    if (!$dupe) {
        ok(1,"No duplicated ports found");
        return;
    }
    for my $port (keys %$port_display) {
        my @clone_id = @{$port_display->{$port}};
        next if scalar(@clone_id) <2;
        my %dup;
        for my $id (@clone_id) {
            my $clone = Ravada::Front::Domain->open($id);
            my $displays = $clone->info(user_admin)->{hardware}->{display};

            for my $display (@$displays) {
                for my $port ($display->{port}, $display->{extra}->{tls_port}) {
                    next if !defined $port;
                    if ($dup{$port}) {
                        my $m="Duplicated port $port in $dup{$port} && $id";
                        diag($m);
                        ok(0,$m);
                    }
                }
            }
        }
    }
}

sub _fetch_ports_display($base) {

    my $dupe = 0;
    my %port_display;
    for my $clone_data ( $base->clones ) {
        next if $clone_data->{is_base} || $clone_data->{status} ne 'active';
        my $clone = Ravada::Front::Domain->open($clone_data->{id});
        my $displays = $clone->info(user_admin)->{hardware}->{display};

        for my $display (@$displays) {
            for my $port ($display->{port}, $display->{extra}->{tls_port}) {
                next if !defined $port;
                if ($port_display{$port}) {
                    my %done;
                    for my $clone_id ($clone_data->{id}, @{$port_display{$port}} ) {
                        next if $done{$clone_id}++;
                        Ravada::Request->refresh_machine(
                            uid => user_admin->id
                            ,id_domain => $clone_id
                            ,_force => 1
                        );
                    }
                    $dupe++;
                }
                push @{$port_display{$port}},($clone->id);
            }
        }
    }
    if ($dupe) {
        Ravada::Request->refresh_vms(_force => 1);
        wait_request();
    }
    return (\%port_display,$dupe);
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
    if (! $clone->is_base) {
        $t->get_ok("/machine/prepare/".$clone->id.".json")->status_is(200);
        for ( 1 .. 10 ) {
            my $clone2 = rvd_front->search_domain($clone->name);
            last if $clone2->is_base || !$clone2->list_requests;
            _wait_request(debug => 1, background => 1, check_error => 1);
            mojo_check_login($t, $USERNAME, $PASSWORD);
        }
        is($clone->is_base,1) or next;
    }
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

    for ( 1 .. 60 ) {
        my ($req) = grep { $_->status ne 'done' } $user->list_requests();
        last if !$req;
        wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
        delete_request('open_exposed_ports');
    }
    my ($req) = reverse $user->list_requests();
    is($req->error, '');
    for ( 1 .. 20 ) {
        $clone_new = rvd_front->search_domain($clone_new_name);
        last if $clone_new;
        sleep 1;
    }
    ok($clone_new,"Expecting $clone_new_name does exist") or exit;

    mojo_check_login($t, $name, $pass);
    $base->is_public(0);

    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(200);
    exit if $t->tx->res->code() != 200;

    test_list_ldap_attributes($t, 403);
}

sub test_list_ldap_attributes($t, $expected_code=200) {
    $t->get_ok("/list_ldap_attributes/failuser.$$");

    is($t->tx->res->code(), $expected_code);

}

sub test_login_non_admin_req($t, $base, $clone){
    mojo_check_login($t, $USERNAME, $PASSWORD);
    for ( 1 .. 3 ) {
        my $clone2;
        if (!$clone->is_base) {

            mojo_request($t,"shutdown", {id_domain => $clone->id, timeout => 1 });
            $t->get_ok("/machine/prepare/".$clone->id.".json")->status_is(200);
            die "Error preparing username='$USERNAME'\n"
            .$t->tx->res->body()
            if $t->tx->res->code() != 200;

            for ( 1 .. 10 ) {
                $clone2 = rvd_front->search_domain($clone->name);
                last if $clone2->is_base || !$clone2->list_requests;
                _wait_request(debug => 1, background => 1, check_error => 1);
                mojo_check_login($t, $USERNAME, $PASSWORD);
            }
            last if $clone2->is_base;
        }
        is($clone2->is_base,1) or exit;
    }
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

    my $clone_new_name = new_domain_name();
    $t->post_ok('/request/clone' => json =>
        {   id_domain => $base->id
            ,name => new_domain_name()
        }
    );

    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
    mojo_check_login($t, $name, $pass);

    my $clone_new = rvd_front->search_domain($clone_new_name);
    ok(!$clone_new,"Expecting $clone_new_name does not exist") or exit;
    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(403);

    $clone_new_name = new_domain_name();
    $base->is_public(1);
    $t->post_ok('/request/clone' => json =>
        {   id_domain => $base->id
            ,name => $clone_new_name
        }
    );


    for ( 1 .. 10 ) {
        wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);
        $clone_new = rvd_front->search_domain($clone_new_name);
        last if $clone_new;
    }
    ok($clone_new,"Expecting $clone_new_name does exist") or exit;

    mojo_check_login($t, $name, $pass);
    $base->is_public(0);

    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(200);
    die "Error cloning ".$base->id if $t->tx->res->code() != 200;
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
    delete_request('set_time','screenshot','refresh_machine_ports');
    mojo_request($t,"remove_base", {id_domain => $clone->id })
    if $clone->is_base;

    if ($clone->id_base) {
        mojo_request($t,"shutdown",{ id_domain => $clone->id });
        mojo_request($t,"spinoff",{ id_domain => $clone->id });
        wait_request();
    }

    is ($clone->is_base,0) or die "Clone ".$clone->name." is supposed to be non-base";

    my $n_clones_clone= scalar($clone->clones());

    my $n_clones = 3;
    delete_request('set_time','screenshot','refresh_machine_ports');

    diag("mojo clone");
    mojo_request($t, "clone", { id_domain => $clone->id, number => $n_clones });
    wait_request(debug => 0, check_error => 1, background => 1, timeout => 120);

    mojo_check_login($t);

    my @clones;
    for ( 1 .. 10 ) {
        @clones = $clone->clones();
        last if scalar(@clones)>= $n_clones_clone+$n_clones;
        sleep 1;
        wait_request();
    }
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
    for ( 1 .. 5 ) {
        my $base2 = Ravada::Front::Domain->open($base1->id);
        last if $base2->is_base;
        sleep 1;
        wait_request();
    }
    return $base1;
}

sub test_clone($base1) {
    mojo_request($t,"prepare_base", {id_domain => $base1->id })
    if !$base1->is_base();

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
    isnt($id_domain, $base1->id);
    my $clone = Ravada::Front::Domain->open($id_domain);

    my $clone_name  = $base1->name."-".user_admin->name;
    like($clone->name, qr/^$clone_name/);
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

sub test_new_machine($t) {
    $t->get_ok("/new_machine.html")->status_is(200) or return;
    my $dom = Mojo::DOM->new( $t->tx->res->body );
    my $form_name = 'new_machineForm';
    my $form = $dom->find('form')->grep( sub {$_->attr('name') eq $form_name});
    ok($form->[0], "Expecting form name=$form_name") or return;
    for my $name ('id_iso', 'name', 'iso_file' ) {
        my $inputs = $form->[0]->find("input")
        ->grep( sub { $_->attr('name') eq $name } );
        ok($inputs->[0],"Expecting input name='$name'");
    }
}

sub test_new_machine_empty($t, $vm_name) {
    for my $iso_file ( '', '<NONE>') {
        for my $iso_name ( 'Empty%32', 'Empty%64') {
            my $name = new_domain_name();

            mojo_check_login($t);
            $t->post_ok('/new_machine.html' => form => {
                    backend => $vm_name
                    ,id_iso => search_id_iso($iso_name)
                    ,iso_file => $iso_file
                    ,name => $name
                    ,disk => 1
                    ,ram => 1
                    ,swap => 1
                    ,submit => 1
                }
            )->status_is(302);

            wait_request();

            my $domain = rvd_front->search_domain($name);
            ok($domain);

            remove_domain_and_clones_req($domain) if $domain;
        }
    }
}

sub test_new_machine_default($t, $vm_name, $empty_iso_file=undef) {
    my $name = new_domain_name();

    my $iso_name = 'Alpine%64 bits';
    my $id_iso = search_id_iso($iso_name);
    my $args = {
            backend => $vm_name
            ,id_iso => $id_iso
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,submit => 1
    };
    $args->{iso_file} = '' if $empty_iso_file;

    mojo_check_login($t);
    $t->post_ok('/new_machine.html' => form => $args)->status_is(302);

    wait_request();

    my $domain = rvd_front->search_domain($name);

    my $disks = $domain->info(user_admin)->{hardware}->{disk};

    my ($swap ) = grep { $_->{file} =~ /SWAP/ } @$disks;
    ok($swap,"Expecting a swap disk volume");

    my ($data) = grep { $_->{file} =~ /DATA/ } @$disks;
    ok($data,"Expecting a data disk volume");

    my ($iso) = grep { $_->{file} =~ /iso$/ } @$disks;
    ok($iso,"Expecting an ISO cdrom disk volume");
}

sub test_new_machine_advanced_options($t, $vm_name, $swap=undef ,$data=undef) {
    mojo_check_login($t);
    my $name = new_domain_name();

    my $iso_name = 'Alpine%64 bits';
    my $id_iso = search_id_iso($iso_name);
    my @args = (
        backend => $vm_name
        ,id_iso => $id_iso
        ,name => $name
        ,disk => 1
        ,ram => 1
        ,submit => 1
        ,_advanced_options => 1
    );
    push @args,(swap => 1) if $swap;
    push @args,(data => 1) if $data;

    $t->post_ok('/new_machine.html' => form => {
            @args
        }
    )->status_is(302);

    wait_request();

    my $domain = rvd_front->search_domain($name);

    my $disks = $domain->info(user_admin)->{hardware}->{disk};

    my ($d_swap ) = grep { $_->{file} =~ /SWAP/ } @$disks;
    if ($swap) {
        ok($d_swap,"Expecting swap disk volume");
    } else {
        ok(!$d_swap,"Expecting no swap disk volume");
    }

    my ($d_data) = grep { $_->{file} =~ /DATA/ } @$disks;
    if ($data) {
        ok($d_data,"Expecting data disk volume");
    } else {
        ok(!$d_data,"Expecting no data disk volume");
    }

    my ($iso) = grep { $_->{file} =~ /iso$/ } @$disks;
    ok($iso,"Expecting an ISO cdrom disk volume") or warn Dumper($disks);
}


sub test_new_machine_change_iso($t, $vm_name) {
    my $iso_name = 'Alpine%32 bits';
    _download_iso($iso_name);
    my $iso_name2 = 'Alpine%64 bits';
    _download_iso($iso_name2);

    my $isos = rvd_front->list_iso_images();
    my $id_iso = search_id_iso($iso_name);
    my $id_iso2 = search_id_iso($iso_name2);

    my ($iso2) = grep { $_->{id} == $id_iso2 } @$isos;

    my $name = new_domain_name();

    mojo_check_login($t);
    $t->post_ok('/new_machine.html' => form => {
            backend => $vm_name
            ,id_iso => $id_iso
            ,iso_file => $iso2->{device}
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,submit => 1
        }
    )->status_is(302);

    wait_request();

    my $domain = rvd_front->search_domain($name);

    my $xml = XML::LibXML->load_xml(string => $domain->_data_extra('xml'));
    my @sources = $xml->findnodes("/domain/devices/disk/source");
    my ($cd) = grep { $_->getAttribute('file') eq $iso2->{device} }
        @sources;

    ok($cd,"Expecting a disk device with source file=$iso2->{device}"
        ." in $name")
        or exit;

    remove_domain_and_clones_req($domain); #remove and wait
}


sub test_create_base($t, $vm_name, $name) {
    my $iso_name = 'Alpine%';
    _download_iso($iso_name);
    mojo_check_login($t);
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

    my $user = Ravada::Auth::SQL->new(name => $USERNAME);
    my @requests = $user->list_requests();
    my ($req_create) = grep { $_->command eq 'create' } @requests;

    _wait_request(debug => 1, background => 1, check_error => 1);
    my $base;
    for ( 1 .. 120 ) {
        $base = rvd_front->search_domain($name);
        last if $base || $req_create->status eq 'done';
        sleep 1;
        diag("waiting for $name");
    }
    is($req_create->status,'done');
    is($req_create->error,'');

    ok($base, "Expecting domain $name create") or exit;
    return $base;
}

sub test_frontend_non_admin($t) {
    $t->ua->get($URL_LOGOUT);
    test_list_ldap_attributes($t, 401);

    my $name = new_domain_name();
    my $pass = "$$ $$";
    my $user = Ravada::Auth::SQL->new(name => $name);
    $user->remove();
    $user = create_user($name, $pass);
    is($user->is_admin(),0);

    login($name, $pass);

    test_list_ldap_attributes($t, 403);
}

sub test_frontend_admin($t) {
    test_list_ldap_attributes($t, 200);
}


sub test_username_case($t) {

    my $user = uc($USERNAME);
    my $pass = "$$ $$";

    $t->post_ok("/users/register" =>
    form => {username => $user, password => $pass});

    is($t->tx->res->code(),200);
    like ($t->tx->res->body, qr/Username already exists/);

}

sub test_network_case($t) {

    $t->post_ok("/v1/exists/networks",json => { name => 'default' } );
    is($t->tx->res->code(),200);
    my $body = $t->tx->res->body;
    my $json;
    eval { $json = decode_json($body) };
    is($@, '') or return;

    ok($json->{id},"Expecting an id in ".Dumper($json));

    $t->post_ok("/v1/exists/networks",json => { name => 'Default' } );
    is($t->tx->res->code(),200);
    my $body2 = $t->tx->res->body;
    my $json2;
    eval { $json2 = decode_json($body2) };
    is($@, '') or return;

    is($json2->{id}, $json->{id},"Expecting an id in ".Dumper($json2));

}

sub test_clone_same_name($t, $base) {
    mojo_check_login($t);
    wait_request();

    my @clones = $base->clones();
    my @clones2;
    for ( 1 .. 2 ) {
        $t->get_ok("/machine/clone/".$base->id.".html")
        ->status_is(200);

        wait_request();
        for ( 1 .. 10 ) {
            wait_request(debug => 1);
            @clones2 = $base->clones();
            last if scalar(@clones2)>scalar(@clones);
            sleep 1;
        }
        last if scalar(@clones2)>scalar(@clones);
    }

    @clones2 = $base->clones();
    my $clone = $clones2[-1];
    is(scalar(@clones2) , scalar(@clones)+1, "Expecting a clone from ".$base->name." ".$base->id);

    die Dumper(\@clones2) if !$clone;

    mojo_request($t,"prepare_base", {id_domain => $clone->{id} });
    sleep 1;
    wait_request();
    for ( 1 .. 10 ) {
        my $cloneb = Ravada::Front::Domain->open($clone->{id});
        last if $cloneb->is_base;
        sleep 1;
    }

    diag("clone again with /machine/clone/".$base->id.".html");
    $t->get_ok("/machine/clone/".$base->id.".html")
    ->status_is(200);

    wait_request();

    my @clones3;
    for ( 1 .. 20 ) {
        @clones3 = $base->clones;
        last if scalar(@clones3)>scalar(@clones2);
        sleep 1;
        wait_request( background=>1);
    }
    @clones3 = $base->clones();
    is(scalar(@clones3) , scalar(@clones2)+1) or exit;

    for my $c ($base->clones) {
        mojo_request($t,"remove_domain", {name => $c->{name} });
    }

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
test_frontend_non_admin($t);

test_validate_html("/login");

remove_old_domains_req();

my $t0 = time;
diag("starting tests at ".localtime($t0));

_init_mojo_client();

test_frontend_admin($t);
test_username_case($t);
test_network_case($t);

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {

    diag("Testing new machine in $vm_name");

    my $name = new_domain_name()."-".$vm_name;
    remove_machines($name,"$name-".user_admin->name);

    $name .= "-".$$;

    _init_mojo_client();

    test_new_machine($t);
    my $base0 = test_create_base($t, $vm_name, $name);
    push @bases,($base0->name);

    test_clone_same_name($t, $base0);

    if ($vm_name eq 'KVM') {
        test_new_machine_default($t, $vm_name);
        test_new_machine_default($t, $vm_name, 1); # with empty iso file
        test_new_machine_advanced_options($t, $vm_name);
        test_new_machine_advanced_options($t, $vm_name,1);
        test_new_machine_advanced_options($t, $vm_name,0,1);
        test_new_machine_advanced_options($t, $vm_name,1,1);
        test_new_machine_change_iso($t, $vm_name);
        test_new_machine_empty($t, $vm_name);
    }
    test_admin_can_do_anything($t, $base0);

    my $base2 =test_create_base($t, $vm_name, new_domain_name()."-$vm_name-$$");
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
    }
    push @bases, ( $clone );
    mojo_check_login($t, $USERNAME, $PASSWORD);
    test_copy_without_prepare($clone);
    mojo_check_login($t, $USERNAME, $PASSWORD);
    test_many_clones($base1);

    test_login_non_admin_req($t, $base1, $base2);
    test_login_non_admin($t, $base1, $base2);
    delete_request('set_time','screenshot','refresh_machine_ports');
    remove_machines(reverse @bases);
    remove_old_domains_req(1); # 0=do not wait for them
}
ok(@bases,"Expecting some machines created");
delete_request('set_time','screenshot','refresh_machine_ports');
remove_machines(reverse @bases);
_wait_request(background => 1);
remove_old_domains_req(0); # 0=do not wait for them
remove_old_users();

done_testing();
