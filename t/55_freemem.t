use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use POSIX ":sys_wait_h";
use Test::More;
use Test::SQL::Data;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;
use Sys::Statistics::Linux;

my $BACKEND = 'KVM';

use_ok('Ravada');
use_ok("Ravada::Domain::$BACKEND");


my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
my $RAVADA = rvd_back( $test->connector , 't/etc/ravada.conf');

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";
$DOMAIN_NAME_SON =~ s/base_//;

my $USER = create_user('foo','bar');

sub test_vm_kvm {
    my $vm = $RAVADA->vm->[0];
    ok($vm,"No vm found") or exit;
    ok(ref($vm) =~ /KVM$/,"vm is no kvm ".ref($vm)) or exit;

    ok($vm->type, "Not defined $vm->type") or exit;
    ok($vm->host, "Not defined $vm->host") or exit;

}
sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $RAVADA->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        my @files_base = $domain->list_files_base;
        eval { $domain->remove(user_admin()) };
        ok(!$@ , "Error removing domain $name : $@") ;

        for my $file ( @files_base) {
            ok(! -e $file,"Image file $file should beremoved ");
        }

    }
    $domain = $RAVADA->search_domain($name,1);
    ok(!$domain, "I can't remove old domain $name") or exit;


}

sub test_new_domain_from_iso {
    my $name = $DOMAIN_NAME;

    test_remove_domain($name);

    diag("Creating domain $name from iso");
    my $domain;
    eval { $domain = $RAVADA->create_domain(name => $name
                                        , id_iso => 1
                                        ,vm => $BACKEND
                                        ,id_owner => $USER->id
            ) 
    };
    ok(!$@,"Domain $name not created: $@");

    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    $sth->finish;
    
    #Ckeck free memory
    my $freemem = _check_free_memory();
    print "FREEMEM: $freemem";
    
    #virsh setmaxmem $name xG --config
    #virsh setmem $name xG --config

    return $domain;
}
sub remove_old_volumes {

    my $name = "$DOMAIN_NAME_SON.qcow2";
    my $file = "/var/lib/libvirt/images/$name";
    remove_volume($file);

    remove_volume("/var/lib/libvirt/images/$DOMAIN_NAME.img");
}

sub remove_volume {
    my $file = shift;

    return if !-e $file;
    diag("removing old $file");
    $RAVADA->remove_volume($file);
    ok(! -e $file,"file $file not removed" );
}

sub _check_free_memory{
    my $lxs  = Sys::Statistics::Linux->new( memstats => 1 );
    my $stat = $lxs->get;
    my $freemem = $stat->memstats->{realfree};
    #die "No free memory" if ( $stat->memstats->{realfree} < 500000 );
    return $freemem;
}



################################################################
my $vm;

eval { $vm = $RAVADA->search_vm('kvm') } if $RAVADA;

SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

test_vm_kvm();
test_remove_domain($DOMAIN_NAME);
remove_old_volumes();
my $domain = test_new_domain_from_iso();
test_remove_domain($domain);

};

done_testing();
