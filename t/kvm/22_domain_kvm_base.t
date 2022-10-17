use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use POSIX ":sys_wait_h";
use Test::More;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

my $BACKEND = 'KVM';

use_ok('Ravada');

my $RAVADA = rvd_back('t/etc/ravada_kvm.conf');

my ($DOMAIN_NAME) = new_domain_name();
my $DOMAIN_NAME_SON= new_domain_name();

my $USER = create_user('foo','bar', 1);

sub test_vm_kvm {
    my $vm = $RAVADA->search_vm('KVM');
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
#        diag("Removing domain $name");
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

#    diag("Creating domain $name from iso");
    my $domain;
    eval { $domain = $RAVADA->create_domain(name => $name
                                        , id_iso => search_id_iso('alpine')
                                        ,vm => $BACKEND
                                        ,id_owner => $USER->id
                                        ,disk => 1024 * 1024
            ) 
    };
    is(''.$@,'') or return;
    ok(!$@,"Domain $name not created: $@");

    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    $sth->finish;

    test_usb($domain);

    return $domain;
}

sub test_usb {
    my $domain = shift;

    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description());

    my ($devices)= $xml->findnodes('/domain/devices');

    my @redir = $devices->findnodes('redirdev');
    my $expect = 3;
    ok(scalar @redir == $expect,"Expecting $expect redirdev, got ".scalar(@redir));

    for my $model ( 'xhci') {
        my @usb = $devices->findnodes('controller');
        my @usb_found;

        for my $dev (@usb) {
            next if $dev->getAttribute('type') ne 'usb';
            next if ! $dev->getAttribute('model') 
                    || $dev->getAttribute('model') !~ qr/$model/;

            push @usb_found,($dev);
        }
        ok(scalar @usb_found == 1,"Expecting 1 USB model $model , got ".scalar(@usb_found)
            ."\n"
            .join("\n" , map { $_->toString } @usb_found));
    }
}

sub test_prepare_base {
    my $domain = shift;

    my @list = $RAVADA->list_bases();
    my $name = $domain->name;

    ok(!grep(/^$name$/,map { $_->name } @list),"$name shouldn't be a base ");

    eval { $domain->prepare_base(user_admin) };
    is($@,'') or exit;

    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{is_base});
    $sth->finish;

    is($domain->is_base,1);
    is($domain->is_public,0);
    $domain->is_public(1);
    is($domain->is_public,1);

    my @list2 = $RAVADA->list_bases();
    ok(scalar @list2 == scalar @list + 1 ,"Expecting ".(scalar(@list)+1)." bases"
            ." , got ".scalar(@list2));

    ok(grep(/^$name$/, map { $_->name } @list2),"$name should be a base ");

}

sub test_new_domain_from_base {
    my $base = shift;

    is($base->is_base,1) or return;
    is($base->is_public,1) or return;

    my $name = $DOMAIN_NAME_SON;
    test_remove_domain($name);

#    diag("Creating domain $name from ".$base->name);
    my $domain;
    eval { $domain = $RAVADA->create_domain(
                name => $name
            ,id_base => $base->id
           ,id_owner => $USER->id
            ,vm => $BACKEND
    );
    };
    is(''.$@,'',"Expecting no error creating $name");
    ok($domain,"Domain not created") or return;
    my $exp_ref= 'Ravada::Domain::KVM';
    ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
        if $domain;

    my @cmd = ('virsh','desc',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    my $sth = connector->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($domain->name);
    my $row =  $sth->fetchrow_hashref;
    ok($row->{name} && $row->{name} eq $domain->name,"I can't find the domain at the db");
    $sth->finish;

    SKIP: {
        #TODO: that could be done
        skip("No remote-viewer",1) if 1 || ! -e "/usr/bin/remote-viewer";
        test_spawn_viewer($domain);
    }

    test_domain_not_cdrom($domain);
    test_usb($domain);
    return $domain;

}

sub test_domain_not_cdrom {
    my $domain = shift;
    my $doc = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);

    my $cdrom = 0;
    for my $disk ($doc->findnodes('/domain/devices/disk')) {
        if ($disk->getAttribute('device') eq 'cdrom') {

            my ($source) = $disk->findnodes('./source');
            $cdrom++    if $source;

            ok(!$source
                ,$domain->name." shouldn't have a CDROM source\n".$disk->toString())
                    or exit;

        }
    }
    ok(!$cdrom,"No cdroms sources should have been found.");


}

sub test_spawn_viewer {
    my $domain = shift;

    my $pid = fork();
    die "Cannot fork"   if !defined $pid;

    if ($pid == 0) {

        my $uri = $domain->display;

        my @cmd = ('remote-viewer',$uri);
        my ($in,$out,$err);
        run3(\@cmd,\$in,\$out,\$err);
        ok(!$?,"Error $? running @cmd");
    } else {
        sleep 5;
        $domain->domain->shutdown;
        sleep 5;
        $domain->domain->destroy;
        exit;
    }
    waitpid(-1, WNOHANG);
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
#    diag("removing old $file");
    $RAVADA->remove_volume($file);
    ok(! -e $file,"file $file not removed" );
}

sub test_dont_allow_remove_base_before_sons {
    #TODO
    # create a base
    # create a son
    # try to remove the base and be denied
    # remove the son
    # try to remove the base and succeed
    # profit !
}

################################################################
my $vm;

clean();
eval { $vm = $RAVADA->search_vm('KVM') } if $RAVADA;

SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    if ($vm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok("Ravada::Domain::$BACKEND");

    clean();
test_vm_kvm();
test_remove_domain($DOMAIN_NAME);
test_remove_domain($DOMAIN_NAME_SON);
remove_old_volumes();
my $domain = test_new_domain_from_iso();


if (ok($domain,"test domain not created")) {
    test_prepare_base($domain);

    my $domain_son = test_new_domain_from_base($domain);
    test_remove_domain($domain_son->name);
    test_remove_domain($domain->name);

    test_dont_allow_remove_base_before_sons();
}

};
end();
done_testing();
