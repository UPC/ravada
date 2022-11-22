use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();

####################################################################

sub _downgrade_base($base) {
    for my $file ($base->list_files_base) {
        next if $file !~ /SWAP|TMP/;
        unlink $file or die "$! $file";
        $base->_vm->storage_pool->refresh();

        my ($volume_name)= $file =~ m{.*/(.*)};

        confess "Error_ no volumename from $file" if !$volume_name;
        my $file_xml = "etc/xml/alpine381_64-volume.xml";
        open my $fh,'<', $file_xml or confess "$! $file_xml";

        my $doc_vol = XML::LibXML->load_xml( IO => $fh );
        $doc_vol->findnodes('/volume/name/text()')->[0]->setData($volume_name);
        $doc_vol->findnodes('/volume/key/text()')->[0]->setData($volume_name);
        my ($format_doc) = $doc_vol->findnodes('/volume/target/format');
        $format_doc->setAttribute(type => 'raw');
        $doc_vol->findnodes('/volume/target/path/text()')->[0]->setData($file);

        my $vol = $base->_vm->storage_pool->create_volume($doc_vol->toString)
        or die "volume $file does not exists after creating volume on ".$base->_vm->name
            ." ".$doc_vol->toString();

    }
}

sub test_domain_with_swap_raw($vm) {
    return if $vm->type ne 'KVM';
    my $domain = create_domain($vm);
    $domain->add_volume_swap( size => 1000 * 1024, format => 'raw');
    $domain->add_volume( type => 'swap', size => 1000 * 1024, format => 'raw');
    my $found = 0;
    for my $vol ( $domain->list_volumes_info ) {
        next if $vol->file !~ /(SWAP|TMP)/;
        delete $vol->{domain};
        delete $vol->{vm};
        is($vol->info()->{driver}->{type},'raw') or die warn Dumper($vol);
        $found++;
    }
    is($found,2) or exit;
    $domain->prepare_base(user_admin);
    _downgrade_base($domain);

    #check base swap volumes are raw
    $found = 0;
    for my $file ($domain->list_files_base) {
        next if $file !~ /(SWAP|TMP)/;
        my ($out, $err) = $vm->run_command("file",$file);
        unlike($out,qr(QEMU));
        $found++;
    }
    is($found,2) or exit;

    test_clone_raw($domain);

    $domain->remove(user_admin);
}

sub test_clone_raw($domain ) {
    my $clone = $domain->clone(name => new_domain_name, user => user_admin);
    my $found = 0;
    for my $vol ( $clone->list_volumes_info ) {
        next if !$vol->file || $vol->file !~ /(SWAP|TMP)/;
        $found++;
        delete $vol->{domain};
        delete $vol->{vm};
        is($vol->info()->{driver}->{type},'qcow2') or die warn Dumper($vol);
        my ($out, $err) = $domain->_vm->run_command("file",$vol->file);
        like($out,qr(QEMU)) or next;
        my $backing = $vol->info->{backing};
        my $doc = XML::LibXML->load_xml( string => $backing );
        my ($format) = $doc->findnodes('/backingStore/format');
        ok($format,"Expecing <format.. > in backing: ".$doc->toString) or next;
        is($format->getAttribute('type'),'qcow2',"Expecting format ".$format->toString)
            or exit;
    }
    is($found,2);

    eval { $clone->start(user_admin) };
    is(''.$@,'',"starting ".$clone->name) or exit;
    is($clone->is_active,1);
    $clone->remove(user_admin);
}

sub test_domain_with_swap {
    my $vm_name = shift;

    my $domain = create_domain($vm_name);
    $domain->add_volume_swap( size => 1000 * 1024);

    my @vol = $domain->list_volumes();
    is(scalar(@vol),3);

    my $clone = $domain->clone(
         name => new_domain_name
        ,user => user_admin
    );
    is($domain->is_base,1);
    is(scalar($clone->list_volumes),2);

    $clone->start(user_admin);
    $clone->shutdown_now(user_admin);

    is(scalar($clone->list_volumes),2);

    my $clone2 = $clone->clone(
        name => new_domain_name
        ,user => user_admin
    );
    is($clone->is_base,0);

    $clone2->start(user_admin);
    $clone2->shutdown_now(user_admin);

    is(scalar($clone2->list_volumes),2);

    # add extra volumes and test down
    $clone2->add_volume(type => 'swap');
    is(scalar($clone2->list_volumes),3);
    $clone2->start(user_admin);
    $clone2->shutdown(user => user_admin);

    $clone2->remove(user_admin);
    $clone->remove(user_admin);
    $domain->remove(user_admin);
}
####################################################################

clean();
for my $vm_name ( vm_names() ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_domain_with_swap_raw($vm);
        test_domain_with_swap($vm_name);
    }
}

end();
done_testing();
