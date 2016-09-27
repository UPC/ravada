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
    kvm => { id_iso => 1,       id_owner => $USER->id }
    ,lxc => { id_template => 1, id_owner => $USER->id }
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

####################################################################
#

remove_old_domains()    if $RVD_BACK;
remove_old_disks();

$RVD_FRONT->fork(0);

for my $vm_name ('kvm','lxc') {

    my $vm = $RVD_BACK->search_vm($vm_name);
    if (!$vm) {
        diag("Skipping VM $vm_name in this system");
        next;
    }

    my $name = new_domain_name();
    my $req = $RVD_FRONT->create_domain( name => $name 
        , vm => $vm_name
        , create_args($vm_name)
    );
    ok($req, "Request $name not created");

    $RVD_FRONT->wait_request($req);

    ok($req->status eq 'done',"Request for create $vm domain ".$req->status);
    ok(!$req->error,$req->error);

    my $domain  = $RVD_FRONT->search_domain($name);

    ok($domain,"Domain $name not found") or exit;
    ok($domain && $domain->{name} && 
        $domain->{name} eq $name,"Expecting domain name $name, got "
        .($domain->{name} or '<UNDEF>'));

    $RVD_FRONT->start_domain($name);
    $RVD_FRONT->wait_request($req,10);
    ok($req->status('done'),"Request ".$req->status);

    my $display = $RVD_FRONT->domdisplay($name, $USER);
    ok($display,"No display for domain $name found. Is it active ?");
    ok($display && $display =~ m{\w+://.*?:\d+},"Expecting display a URL, it is '"
                .($display or '<UNDEF>')
                ."'");

    $display = undef;
    eval { $display = $RVD_FRONT->domdisplay($name ) };
    ok(!$display,"No display should b e returned with no user");

    test_remove_domain($name);
}
done_testing();
