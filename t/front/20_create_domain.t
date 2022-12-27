use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $CONFIG_FILE = 't/etc/ravada.conf';

my @rvd_args = (
       config => $CONFIG_FILE
   ,connector => connector 
);

my $RVD_BACK  = rvd_back( );
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar', 1);

add_ubuntu_minimal_iso();

my %CREATE_ARGS = (
    Void => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
    ,KVM => { id_iso => search_id_iso('Ubuntu % Minimal'),       id_owner => $USER->id }
    ,LXC => { id_template => 1, id_owner => $USER->id }
);


###################################################################

sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}

sub search_domain_db
 {
    my $name = shift;
    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_remove_domain {
    my $name = shift;

    my $domain_f = $RVD_FRONT->search_domain($name);
    ok($domain_f,"Expecting domain $name in front");

    my $domain;
    $domain = $RVD_BACK->search_domain($name,1);

    if ($domain) {
#        diag("Removing domain $name");
        $domain->remove($USER);
    }
    $domain = $RVD_BACK->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

    ok(!search_domain_db($name),"Domain $name still in db");

    $domain_f = undef;
    eval { $domain_f = $RVD_FRONT->search_domain($name) };
    ok(!$domain_f,"Expecting no domain $name in front ".Dumper($domain_f));

    my $list_domains = $RVD_FRONT->list_domains;
    is(scalar@$list_domains,0, Dumper($list_domains));
}

sub test_list_bases {
    my $vm_name = shift;
    my $expected = shift;

    my $bases = $RVD_FRONT->list_bases();

    ok(scalar @$bases == $expected,"Expecting '$expected' bases, got ".scalar @$bases);
}

sub test_domain_name {
    my $vm_name = shift;

    my $id = 9999;

    eval {
        my $domain = Ravada::Front::Domain->open($id);
        $domain->name();
    };
    like($@,qr'Unknown domain');

}

sub test_domain_info {
    my $domain = shift;

    my $domain_b = Ravada::Domain->open($domain->id);
    $domain_b->start(user => user_admin, remote_ip => '127.0.0.1')  if !$domain_b->is_active;
    $domain_b->open_iptables(user => user_admin, remote_ip => '127.0.0.1');
    for ( 1 .. 30 ) {
        last if $domain_b->ip;
        sleep 1;
    }
    my $internal_info = $domain_b->get_info;
    ok(exists $internal_info->{ip}, "Expecting IP in internal info ".Dumper($internal_info))
        or exit;
    ok(exists $domain->info(user_admin)->{ip}
        ,"Expecting ip field in domain info ") or exit;

    my $domain_f = Ravada::Front::Domain->open($domain_b->id);
    my $info_f = $domain_f->info(user_admin);
    ok(exists $info_f->{ip},"Expecting ip in front domain info");
    is($info_f->{ip}, $domain_b->ip);

    $domain_b->shutdown_now(user_admin);

    my $info = $domain_b->info(user_admin);
    ok(!exists $info->{ip} || !defined $info->{ip},"Expecting no IP after shutdown");
}

####################################################################
#

remove_old_domains()    if $RVD_BACK;
remove_old_disks();

$RVD_FRONT->fork(0);

ok(scalar $RVD_FRONT->list_vm_types(),"Expecting some in list_vm_types , got "
    .scalar $RVD_FRONT->list_vm_types());

SKIP: {
for my $vm_name ( vm_names() ) {

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $msg = "Skipping VM $vm_name in this system";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    if (!$vm) {
        diag($msg);
        skip($msg,10);
    }

    my $name = new_domain_name();
    my $req = $RVD_FRONT->create_domain( name => $name 
        , create_args($vm_name)
        , vm => $vm_name
        , disk => 1024 * 1024
    );
    ok($req, "Request $name not created");

    $RVD_FRONT->wait_request($req);
    $RVD_FRONT->wait_request($req);
    $RVD_FRONT->wait_request($req);

    ok($req->status eq 'done',"Request for create $vm domain ".$req->status);
    ok(!$req->error,$req->error);

    test_list_bases($vm_name, 0);

    my $domain  = $RVD_FRONT->search_domain($name);

    ok($domain,"Domain $name not found") or exit;
    ok($domain && $domain->name && 
        $domain->name eq $name,"[$vm_name] Expecting domain name $name, got "
        .($domain->name or '<UNDEF>'));

    my $ip = '127.0.0.1';

    $req = $RVD_FRONT->start_domain(name => $name, user =>  $USER, remote_ip => $ip);
    $RVD_FRONT->wait_request($req,10);
    ok($req->status('done'),"Request ".$req->status);
    ok(!$req->error,"[$vm_name] Request start domain expecting no error, got '".$req->error
        ."'") or exit;

    $domain  = $RVD_FRONT->search_domain($name);
    is($domain->_data('status'),'active',$domain->name." status");
    ok($domain->is_active,"[$vm_name] Expecting domain $name active, got ".$domain->is_active)
        or exit;

    my $display = $domain->display($USER);
    ok($display,"[$vm_name] No display for domain $name found. Is it active ?");
    ok($display && $display =~ m{\w+://.*?:\d+},"[$vm_name] Expecting display a URL, it is '"
                .($display or '<UNDEF>')
                ."'");

    $display = undef;

    my $domain_front2 = Ravada::Front::Domain->open($domain->id);
    is($domain_front2->id, $domain->id);
    is($domain_front2->{_vm}, undef);

    my $domain_front3 = Ravada::Front::Domain->new( id => $domain->id);
    is($domain_front3->id, $domain->id);
    is($domain_front3->{_vm}, undef);
    ok($domain->internal_id,"[$vm_name] Expecting an internal id , got ".($domain->internal_id or ''));
    if ($domain->type =~ /kvm/i) {
        my $domain_back = rvd_back->search_domain($domain->name);
        is($domain->internal_id, $domain_back->domain->get_id);
    }

    test_domain_info($domain);

    test_remove_domain($name);

    test_domain_name($vm_name);
}
}

Test::Ravada::_check_leftovers();
end();
done_testing();
