use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw(lock_hash);
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector() );

my $RVD_BACK;

eval { $RVD_BACK = rvd_back() };
ok($RVD_BACK,($@ or '')) or BAIL_OUT;

my $USER = create_user("foo","bar", 1);
ok($USER);

##########################################################

sub test_change_owner {
    my $vm_name = shift;
    my $USER2 = create_user("foo2","bar2", 1);
    my $name = new_domain_name();
    my $id_iso = search_id_iso('Debian');
    diag("Testing change owner");
    my $domain = rvd_back->search_vm($vm_name)->create_domain(
             name => $name
          ,id_iso => $id_iso
        ,id_owner => $USER->id
        ,iso_file => '<NONE>'
            ,disk => 1024 * 1024
    );
    is($USER->id, $domain->id_owner) or return;
    my $req = Ravada::Request->change_owner(uid => $USER2->id, id_domain => $domain->id);
    rvd_back->_process_requests_dont_fork();

    $domain = Ravada::Domain->open($domain->id);
    is($USER2->id, $domain->id_owner) or return;
    $USER2->remove();
}

sub test_start_clones {
    my $vm_name = shift;
    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;
    diag("Testing start clones");
    my $name = new_domain_name();
    my $user_name = $USER->id;
    my $domain = $vm->create_domain(name => $name
                    , id_owner => $user_name
                    , arg_create_dom($vm_name));
    my $clone1 = $domain->clone( user=>$USER, name=>new_domain_name() );
    my $clone2 = $domain->clone( user=>$USER, name=>new_domain_name() );
    my $clone3 = $domain->clone( user=>$USER, name=>new_domain_name() );
    is($clone1->is_active,0);
    is($clone2->is_active,0);
    is($clone3->is_active,0);
    my $req = Ravada::Request->start_clones(uid => $USER->id, id_domain => $domain->id, remote_ip => '127.0.0.1' );
    rvd_back->_process_all_requests_dont_fork(); #we make sure that the sql has updated.
    is($req->status,'done');
    is($req->error,'');

    # The first requests creates 3 more requests, process them
    rvd_back->_process_all_requests_dont_fork();
    is($clone1->is_active,1);
    is($clone2->is_active,1);
    is($clone3->is_active,1);

    $clone1->remove(user_admin);
    $clone2->remove(user_admin);
    $clone3->remove(user_admin);

    $domain->remove(user_admin);
}

sub test_vm_connect {
    my $vm_name = shift;
    my $host = (shift or 'localhost');
    my $conf = (shift or {} );

    my $class = "Ravada::VM::$vm_name";
    my $obj = {};

    bless $obj,$class;

    my %args;
    $args{host} = $host if $host;

    my $vm = $obj->new(host => $host, %$conf);
    ok($vm);
    is($vm->host, $host);
}

sub test_search_vm {
    my $vm_name = shift;
    my $host = ( shift or 'localhost');

    my $class = "Ravada::VM::$vm_name";

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name, $host);
    ok($vm,"I can't find a $vm_name virtual manager in host=".($host or '<UNDEF>')) or exit;
    ok(ref $vm eq $class,"Virtual Manager is of class ".(ref($vm) or '<NULL>')
        ." it should be $class");

    is($vm->host, $host);
}


sub test_create_domain {
    my $vm_name = shift;
    my $host = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name, $host);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    if ($vm_name eq 'KVM') {
        is($domain->internal_id, $domain->domain->get_id);
    } else {
        ok($domain->internal_id);
    }

    for my $dom2 ( $vm->list_domains ) {
        is(ref($dom2),ref($domain)) if $vm_name ne 'Void';
    }
    my ($cdrom) = grep { /iso/ } $domain->list_volumes;
    like($cdrom, qr/\.iso$/, "Expecting a CDROM ".Dumper([$domain->list_volumes]));

    return $domain;
}

sub test_open {
    my $vm_name = shift;
    my $domain = shift;

    my $domain2 = Ravada::Domain->open($domain->id);

    is($domain2->id, $domain->id);
    is($domain2->name, $domain->name);
    is($domain2->description, $domain->description);
    is($domain2->vm, $domain->vm);
}

sub test_manage_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start($USER) if !$domain->is_active();
    ok(!$domain->is_locked,"Domain ".$domain->name." should not be locked");

    if ($vm_name eq 'KVM') {
        is($domain->internal_id, $domain->domain->get_id);
    } else {
        ok($domain->internal_id);
    }


    my $display;
    eval { $display = $domain->display($USER) };
    ok($display,"No display for ".$domain->name." $@");

    ok($domain->is_active(),"[$vm_name] domain should be active");
    $domain->shutdown(user => $USER, timeout => 1);
    ok(!$domain->is_active(),"[$vm_name] domain should not be active");
}

sub test_pause_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start($USER) if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    my $display;
    eval { $domain->pause($USER) };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->resume($USER) };
    ok(!$@,"[$vm_name] Resuming domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

}

sub test_shutdown {
    my $vm = shift;

    return if $vm->type eq 'Void';

    my $domain = create_domain($vm);
    $domain->start(user_admin);

    my $req = Ravada::Request->shutdown_domain(uid => user_admin->id
        , id_domain => $domain->id
    );
    rvd_back->_process_requests_dont_fork();

    my @reqs = $domain->list_requests(1);
    ok(scalar @reqs,$domain->name);

    $domain->shutdown_now(user_admin);

    ok(!$domain->is_active);
    rvd_back->_remove_unnecessary_downs($domain);
    @reqs = $domain->list_requests(1);
    # 1 request for refresh_machine
    my @req_refresh = grep { $_->command eq 'refresh_machine' } @reqs;
    is(scalar(@req_refresh),1);
    # no other requests
    my @req_other = grep { $_->command ne 'refresh_machine' } @reqs;
    is(scalar(@req_other),0);

    is(scalar @reqs,1,$domain->name) or exit;

    $domain->remove(user_admin);
}

sub test_shutdown_paused_domain {
    my $vm_name = shift;
    my $domain = shift;

    $domain->start($USER) if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    eval { $domain->pause($USER) };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->shutdown(user => $USER, timeout => 2) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_paused,"[$vm_name] Expecting domain not paused, got ".$domain->is_paused);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_active,"[$vm_name] Expecting domain not active, got ".$domain->is_active);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

}

sub test_shutdown_suspended_domain {
    my $vm_name = shift;
    my $domain = shift;

    return if ref($domain) !~ /KVM/i;

    $domain->start($USER) if !$domain->is_active();
    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active) or return;

    eval { $domain->domain->suspend() };
    ok(!$@,"[$vm_name] Pausing domain, expecting '', got '$@'");

    ok($domain->is_active,"[$vm_name] Expecting domain active, got ".$domain->is_active);

    ok($domain->is_paused,"[$vm_name] Expecting domain paused, got ".$domain->is_paused);

    eval { $domain->shutdown(user => $USER, timeout => 2) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_paused,"[$vm_name] Expecting domain not paused, got ".$domain->is_paused);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

    ok(!$domain->is_active,"[$vm_name] Expecting domain not active, got ".$domain->is_active);

    eval { $domain->shutdown_now($USER) };
    ok(!$@,"[$vm_name] Shutting down paused domain, expecting '', got '$@'");

}

sub test_remove_domain {
    my $vm_name = shift;
    my $domain = shift;
#    diag("Removing domain ".$domain->name);
    my $domain0 = rvd_back()->search_domain($domain->name);
    ok($domain0, "[$vm_name] Domain ".$domain->name." should be there in ".ref $domain);


    eval { $domain->remove( user_admin ) };
    ok(!$@ , "[$vm_name] Error removing domain ".$domain->name." ".ref($domain).": $@") or exit;

    my $domain2 = rvd_back()->search_domain($domain->name);
    ok(!$domain2, "Domain ".$domain->name." should be removed in ".ref $domain);

}

sub test_remove_domain_already_gone {
    my $vm_name = shift;
    my $domain = create_domain($vm_name);
    if ($vm_name eq 'KVM') {
        $domain->domain->undefine();
    } elsif ($vm_name eq 'Void') {
        unlink $domain->_config_file();
    }
    rvd_back->remove_domain( name => $domain->name, uid => user_admin->id);

    my $domain_b = rvd_back->search_domain($domain->name);
    ok(!$domain_b);

    my $domain_f;
    eval { $domain_f = rvd_front->search_domain($domain->name)};
    ok(!$domain_f,"[$vm_name] Expecting no domain ".$domain->name." in front") or exit;
}

sub test_search_domain {
    my $domain = shift;
    my $domain0 = rvd_back()->search_domain($domain->name);
    ok($domain0, "Domain ".$domain->name." should be there in ".ref $domain);
};

sub test_json {
    my $vm_name = shift;
    my $domain_name = shift;

    my $domain = rvd_back()->search_domain($domain_name);

    my $dec_json = $domain->info(user_admin);
    ok($dec_json->{name} && $dec_json->{name} eq $domain->name
        ,"[$vm_name] expecting json->{name} = '".$domain->name."'"
        ." , got ".($dec_json->{name} or '<UNDEF>')." for json ".Dumper($dec_json)
    );

    my $vm = rvd_back()->search_vm($vm_name);
    my $domain2 = $vm->search_domain_by_id($domain->id);
    my $dec_json2 = $domain2->info(user_admin);
    ok($dec_json2->{name} && $dec_json2->{name} eq $domain2->name
        ,"[$vm_name] expecting json->{name} = '".$domain2->name."'"
        ." , got ".($dec_json2->{name} or '<UNDEF>')." for json ".Dumper($dec_json2)
    );

}

sub test_screenshot_db {
    my $vm_name = shift;
    my $domain= shift;
    return if !$domain->can_screenshot;
    $domain->start($USER)   if !$domain->is_active;
    sleep 2;
    $domain->screenshot();
    $domain->shutdown(user => $USER, timeout => 1);
    my $sth = connector->dbh->prepare("SELECT screenshot FROM domains WHERE id=?");
    $sth->execute($domain->id);
    my @fields = $sth->fetchrow;
    #ok($fields[0],"Expecting child node listen , got :'".substr( $fields[0], 0, 10 ) or ''));
    ok($fields[0]);
}

sub test_change_interface {
    my ($vm_name) = @_;
    return if $vm_name !~ /kvm/i;

    my $domain = test_create_domain($vm_name);

    set_bogus_ip($domain);
    eval { $domain->start($USER) };
    ok(!$@,"Expecting error='' after starting domain, got ='".($@ or '')."'") or return;

    my $display = $domain->display($USER);
    like($display,qr{spice://\d+.\d+.});
}

sub set_bogus_ip {
    my $domain = shift;
    my $doc = XML::LibXML->load_xml(string
                            => $domain->domain->get_xml_description) ;
    my @graphics = $doc->findnodes('/domain/devices/graphics');
    is(scalar @graphics,1) or return;

    my $bogus_ip = '999.999.999.999';
    $graphics[0]->setAttribute('listen' => $bogus_ip);

    my $listen;
    for my $child ( $graphics[0]->childNodes()) {
        $listen = $child if $child->getName() eq 'listen';
    }
    ok($listen,"Expecting child node listen , got :'".($listen or ''))
        or return;

    $listen->setAttribute('address' => $bogus_ip);

    $domain->domain->update_device($graphics[0]);
}

sub test_description {
    my ($vm_name, $domain) = @_;

    my $description = "Description bla bla bla $$";

    $domain->description($description);
    is($domain->description, $description);

    my $domain2 = rvd_back->search_domain($domain->name);
    is($domain2->description, $description) or exit;
}

sub test_create_domain_nocd {
    my $vm_name = shift;
    my $host = (shift or 'localhost');

    my $vm = rvd_back->search_vm($vm_name, $host);
    my $name = new_domain_name();

    my $id_iso = search_id_iso('Debian');

    my $sth = connector->dbh->prepare(
        "UPDATE iso_images set device=NULL WHERE id=?"
    );
    $sth->execute($id_iso);
    $sth->finish;

    my $iso;
    eval { $iso = $vm->_search_iso($id_iso,'<NONE>')};
    return if $@ && $@ =~ /Can't locate object method/;
    is($@,'');

    my $domain;
    eval { $domain = rvd_back->search_vm($vm_name)->create_domain(
             name => $name
            ,disk => 1024 * 1024
          ,id_iso => $id_iso
        ,id_owner => $USER->id
        ,iso_file => '<NONE>'
    );};
    is($@,'');
    ok($domain,"Expecting a domain");

    my ($cdrom) = grep { /iso/ } $domain->list_volumes;
    is($cdrom, undef, "Expecting a CDROM ".Dumper([$domain->list_volumes]));
}

sub select_iso {
    my $id = shift;
    my $sth = connector->dbh->prepare("SELECT * FROM iso_images"
        ." WHERE id=?");
    $sth->execute($id);
    return $sth->fetchrow_hashref;
}

sub test_vm_in_db {
    my $vm_name = shift;
    my $conf = shift;

    my $vm;
    eval { $vm = Ravada::VM->open(type => $vm_name, %$conf)};
    is(''.$@,'') or return;

    ok($vm);
    ok($vm->id);

    my $vm2;
    eval { $vm2 = Ravada::VM->open($vm->id) };
    is(''.$@,'') or exit;

    is($vm2->id, $vm->id);
    is($vm2->name, $vm->name);
    is($vm2->host, $vm->host);

    my $vm3;
    eval { $vm3 = rvd_back->search_vm($vm_name, $vm2->host,1) };
    is(''.$@,'') or return;

    ok($vm3,"Expecting a VM ".$vm_name." ".$vm2->host) or exit;
    is($vm3->id, $vm->id);
    is($vm3->name, $vm->name);
    is($vm3->host, $vm->host);
}

#######################################################

remove_old_domains();
remove_old_disks();

for my $vm_name ( vm_names() ) {

  my $remote_conf = remote_config ($vm_name);
  my @conf = (undef, { host => 'localhost' });

  for my $conf ( @conf ) {

    lock_hash(%$conf);

    my $host;
    $host = $conf->{host} if $conf && exists $conf->{host};

    diag("Testing VM $vm_name in host ".($host or '<UNDEF>'));
    my $CLASS= "Ravada::VM::$vm_name";

    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };
    $RAVADA->_upgrade_tables() if $RAVADA;

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok($CLASS) or next;
        test_vm_in_db($vm_name, $conf)    if $conf;

        test_shutdown($vm);

        test_vm_connect($vm_name, $host, $conf);
        test_search_vm($vm_name, $host, $conf);
        test_change_owner($vm_name);

        test_start_clones($vm_name);
        test_vm_connect($vm_name);
        test_search_vm($vm_name);

        test_remove_domain_already_gone($vm_name);

        test_create_domain_nocd($vm_name, $host);

        my $domain = test_create_domain($vm_name, $host);
        test_open($vm_name, $domain);

        test_description($vm_name, $domain);
        test_change_interface($vm_name,$domain);
        ok($domain->has_clones==0,"[$vm_name] has_clones expecting 0, got ".$domain->has_clones);
        $domain->is_public(1);
        my $clone1 = $domain->clone( user=>user_admin, name=>new_domain_name );
        ok($clone1, "Expecting clone ");
        ok($domain->has_clones==1,"[$vm_name] has_clones expecting 1, got ".$domain->has_clones);
        $clone1->shutdown_now($USER);

        my $clone2 = $domain->clone(user=>$USER,name=>new_domain_name);
        ok($clone2, "Expecting clone ");
        ok($domain->has_clones==2,"[$vm_name] has_clones expecting 2, got ".$domain->has_clones);
        $clone2->shutdown_now($USER);

        test_json($vm_name, $domain->name);
        test_search_domain($domain);

        test_remove_domain($vm_name, $clone1);
        test_remove_domain($vm_name, $clone2);

        $domain->remove_base($USER);
        test_manage_domain($vm_name, $domain);
        test_screenshot_db($vm_name, $domain);

        test_shutdown_suspended_domain($vm_name, $domain);
        test_pause_domain($vm_name, $domain);
        test_shutdown_paused_domain($vm_name, $domain);

        test_remove_domain($vm_name, $domain);

    };
}
}
remove_old_domains();
remove_old_disks();

done_testing();
