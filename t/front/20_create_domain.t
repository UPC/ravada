use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada::Front');

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.t};
$DOMAIN_NAME = 'front_'.$DOMAIN_NAME;
my $CONT= 0;

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my @rvd_args = (
       config => 't/etc/ravada.conf' 
   ,connector => $test->connector 
);

my $RVD_BACK  = Ravada->new( @rvd_args );
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

my %CREATE_ARGS = (
    kvm => { id_iso => 1 }
    ,lxc => { id_template => 1 }
);

###################################################################

sub _new_name {
    return $DOMAIN_NAME."_".$CONT++;
}

sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}
sub remove_old_disks {
    my $name = $DOMAIN_NAME;

    my $vm = $RVD_BACK->search_vm('kvm');
    ok($vm,"I can't find a KVM virtual manager") or return;

    my $dir_img = $vm->dir_img();
    ok($dir_img," I cant find a dir_img in the KVM virtual manager") or return;

    for my $count ( 0 .. 10 ) {
        my $disk = $dir_img."/$name"."_$count.img";
        if ( -e $disk ) {
            unlink $disk or die "I can't remove $disk";
        }
    }
    $vm->storage_pool->refresh();
}

sub remove_old_domains {
    for ( 0 .. 10 ) {
        my $dom_name = $DOMAIN_NAME."_$_";
        my $domain = $RVD_BACK->search_domain($dom_name);
        $domain->shutdown_now() if $domain;
        test_remove_domain($dom_name);
    }
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
        $domain->remove();
    }
    $domain = $RVD_BACK->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

    ok(!search_domain_db($name),"Domain $name still in db");
}

####################################################################
#

remove_old_domains();
remove_old_disks();


for my $vm_name ('kvm','lxc') {

    my $vm = $RVD_BACK->search_vm($vm_name);
    if (!$vm) {
        diag("Skipping VM $vm_name in this system");
        next;
    }

    my $name = _new_name();
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

    my $display = $RVD_FRONT->domdisplay($name);
    ok($display,"No display for domain $name found. Is it active ?");
    ok($display =~ m{\w+://.*?:\d+},"Expecting display a URL, it is '$display'");
}
done_testing();
