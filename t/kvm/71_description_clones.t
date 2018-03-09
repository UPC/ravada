use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
my $FILE_CONFIG = 't/etc/ravada.conf';

my @VMS = vm_names();
init($test->connector);
my $USER = create_user("foo","bar");
my $DISPLAY_IP = '99.1.99.1';

our $TIMEOUT_SHUTDOWN = 10;

################################################################
sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();
    diag("Test create domain $name");

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub test_files_base {
    my $domain = shift;
    my $n_expected = shift;

    my @files = $domain->list_files_base();

    ok(scalar @files == $n_expected,"Expecting $n_expected files base , got "
            .scalar @files);
    return;
}

sub test_prepare_base_active {
    my $vm_name = shift;
    diag("Test prepare base active $vm_name");

    my $domain = test_create_domain($vm_name);

    ok(!$domain->is_base,"Domain ".$domain->name." should not be base") or return;
    eval { $domain->start($USER) if !$domain->is_active() };
    ok(!$@,$@) or exit;
    eval { $domain->resume($USER)  if $domain->is_paused()  };
    ok(!$@,$@);

    ok($domain->is_active,"[$vm_name] Domain ".$domain->name." should be active") or return;
    ok(!$domain->is_paused,"[$vm_name] Domain ".$domain->name." should not be paused") or return;

    eval{ $domain->prepare_base($USER) };
    ok(!$@,"[$vm_name] Prepare base, expecting error='', got '$@'") or exit;

    ok(!$domain->is_active,"[$vm_name] Domain ".$domain->name." should not be active")
        or return;
}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;
    diag("Test prepare base $vm_name");

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    test_files_base($domain,0);
    $domain->shutdown_now($USER)    if $domain->is_active();

    eval { $domain->prepare_base( $USER) };
    is(''.$@, '', "[$vm_name] expecting no error preparing ".$domain->name);
    ok($domain->is_base);
    is($domain->is_active(),0);

    my $description = "This is a description test";
    add_description($domain, $description);

    eval { $domain->prepare_base( $USER) };
    $@ = '' if !defined $@;
    like($@, qr/already/i,"[$vm_name] Don't prepare if already base");
    ok($domain->is_base);

    test_files_base($domain,1);

    my @disk = $domain->disk_device();
    $domain->shutdown(user => $USER)    if $domain->is_active;


    eval {
        $domain->remove_base( $USER);
        $domain->prepare_base( $USER);
    };
    is($@,'');
    ok($domain->is_base);

    my $name_clone = new_domain_name();

    my $domain_clone;

    $domain->is_public(1);
    eval { $domain_clone = $vm->create_domain(
        name => $name_clone
        ,id_owner => $USER->id
        ,id_base => $domain->id
        ,vm => $vm_name
        ,description => $domain->description
        );
    };
    ok(!$@,"Clone domain, expecting error='' , got='".($@ or '')."'") or exit;
    ok($domain_clone,"Trying to clone from ".$domain->name." to $name_clone");

    ok($domain_clone->id_base && $domain_clone->id_base == $domain->id
          ,"[$vm_name] Expecting id_base=".$domain->id." got ".($domain_clone->id_base or '<UNDEF>')) or exit;

    my $domain_clone2 = rvd_front->search_clone(
         id_base => $domain->id,
        id_owner => $USER->id
    );
    #ok($domain_clone2,"Searching for clone id_base=".$domain->id." user=".$USER->id
    #    ." expecting domain , got nothing "
    #    ." ".Dumper($domain_clone)) or exit;

    if ($domain_clone2) {
        ok( $domain_clone2->name eq $domain_clone->name
        ,"Expecting clone name ".$domain_clone->name." , got:".$domain_clone2->name
        );

        ok($domain_clone2->id eq $domain_clone->id
        ,"Expecting clone id ".$domain_clone->id." , got:".$domain_clone2->id
        );
    }

    eval { $domain->prepare_base($USER) };
    ok($@ && $@ =~ /has \d+ clones|already a base/i
        ,"[$vm_name] Don't prepare if there are clones ".($@ or '<UNDEF>'));
    ok($domain->is_base);

    $domain_clone->remove($USER);

    eval {
        $domain->remove_base($USER);
        $domain->prepare_base($USER)
    };

    ok(!$@,"[$vm_name] Error preparing base after clone removed :'".($@ or '')."'");
    ok($domain->is_base,"[$vm_name] Expecting domain is_base=1 , got :".$domain->is_base);

    $domain->is_base(0);
    ok(!$domain->is_base,"[$vm_name] Expecting domain is_base=0 , got :".$domain->is_base);

    $domain->is_base(1);
    ok($domain->is_base,"[$vm_name] Expecting domain is_base=1 , got :".$domain->is_base);

}

sub add_description {
    my $domain = shift;
    my $description = shift;
    my $name = $domain->name;
    diag("Add description $name");

    $domain->description($description);
}

sub test_description {
    my $vm_name = shift;

    diag("Testing description $vm_name");
    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    test_prepare_base($vm_name, $domain);
    test_prepare_base_active($vm_name);

    my $description = "This is a description test";
    my $domain2 = rvd_back->search_domain($domain->name);
    ok ($domain2->description eq $description, "I can't find description");
}

sub test_remove_base {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);
    ok($domain,"Expecting domain, got NONE") or return;

    my @files0 = $domain->list_files_base();
    ok(!scalar @files0,"Expecting no files base, got ".Dumper(\@files0)) or return;

    $domain->prepare_base($USER);
    ok($domain->is_base,"Domain ".$domain->name." should be base") or return;

    my @files = $domain->list_files_base();
    ok(scalar @files,"Expecting files base, got ".Dumper(\@files)) or return;

    $domain->remove_base($USER);
    ok(!$domain->is_base,"Domain ".$domain->name." should be base") or return;

    for my $file (@files) {
        ok(!-e $file,"Expecting file base '$file' removed" );
    }

    my @files_deleted = $domain->list_files_base();
    is(scalar @files_deleted,0);

    my $sth = $test->dbh->prepare(
        "SELECT count(*) FROM file_base_images"
        ." WHERE id_domain = ?"
    );
    $sth->execute($domain->id);
    my ($count) = $sth->fetchrow;
    $sth->finish;

    is($count,0,"[$vm_name] Count files base after remove base domain");

}

#######################################################

#######################################################

clean();

my $vm_name = 'KVM';
my $vm = rvd_back->search_vm($vm_name);
my $description = 'This is a description test';

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }
    skip($msg,10)   if !$vm;

    test_description($vm_name);
    test_remove_base($vm_name);
}

clean();

done_testing();
