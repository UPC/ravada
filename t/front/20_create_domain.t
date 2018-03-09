use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $CONFIG_FILE = 't/etc/ravada.conf';

my @rvd_args = (
       config => $CONFIG_FILE
   ,connector => $test->connector 
);

my $RVD_BACK  = rvd_back( $test->connector, $CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar');

my %CREATE_ARGS = (
    Void => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
    ,KVM => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
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
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;

}

sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $RVD_BACK->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        $domain->remove($USER);
    }
    $domain = $RVD_BACK->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

    ok(!search_domain_db($name),"Domain $name still in db");
}

sub test_list_bases {
    my $vm_name = shift;
    my $expected = shift;

    my $bases = $RVD_FRONT->list_bases();

    ok(scalar @$bases == $expected,"Expecting '$expected' bases, got ".scalar @$bases);
}

####################################################################
#

remove_old_domains()    if $RVD_BACK;
remove_old_disks();

$RVD_FRONT->fork(0);

ok(scalar $RVD_FRONT->list_vm_types(),"Expecting some in list_vm_types , got "
    .scalar $RVD_FRONT->list_vm_types());

SKIP: {
for my $vm_name ('Void','KVM','LXC') {

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
    );
    ok($req, "Request $name not created");

    $RVD_FRONT->wait_request($req);

    ok($req->status eq 'done',"Request for create $vm domain ".$req->status);
    ok(!$req->error,$req->error);

    test_list_bases($vm_name, 0);

    my $domain  = $RVD_FRONT->search_domain($name);

    ok($domain,"Domain $name not found") or exit;
    ok($domain && $domain->name && 
        $domain->name eq $name,"[$vm_name] Expecting domain name $name, got "
        .($domain->name or '<UNDEF>'));

    my $ip = '99.88.77.66';

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
    eval { $display = $RVD_FRONT->domdisplay($name ) };
    ok(!$display,"No display should b e returned with no user");

    ok($domain->internal_id,"[$vm_name] Expecting an internal id , got ".($domain->internal_id or ''));
    if ($domain->type =~ /kvm/i) {
        my $domain_back = rvd_back->search_domain($domain->name);
        is($domain->internal_id, $domain_back->domain->get_id);
    }


    test_remove_domain($name);
}
}

remove_old_domains();
remove_old_disks();

done_testing();
