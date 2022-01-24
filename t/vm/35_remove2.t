#!perl

use strict;
use warnings;
use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

# init ravada for testing
init();
my $USER = create_user("foo","bar", 1);

##############################################################################

sub test_remove_domain {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    $domain->shutdown( user => user_admin )  if $domain->is_active();
    
    if ($vm->type eq 'KVM') {
        $domain->domain->undefine();
    } elsif ($vm->type eq 'Void') {
        unlink $domain->_config_file() or die "$! ".$domain->_config_file;
    }

    my $removed = $domain->is_removed;

    ok($removed, "Domain deleted: $removed");
    
    eval{ $domain->remove(user_admin) };
    
    is($@,"");

    my $list = rvd_front->list_domains();
    is(scalar @$list , 0);

    Ravada::Domain::_remove_domain_data_db($domain->id, $domain->type);
    Test::Ravada::_check_leftovers_domains();
}

sub test_remove_domain_volumes_already_gone {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    for my $file ($domain->list_disks) {
        next if $file =~ /iso/;
        unlink $file or die "$! $file";
    }
    $domain->storage_refresh() if $vm->type ne 'Void';
    my @volumes = $domain->list_volumes_info();
    for my $vol (@volumes) {
        next if $vol->file =~ /\.iso$/;
        ok(!-e $vol->file);
    }
    eval { $domain->remove(user_admin) };
    is(''.$@,'',$vm->type);
    Ravada::Domain::_remove_domain_data_db($domain->id, $domain->type);
    Test::Ravada::_check_leftovers_domains();
}

sub _clone($base, $name=new_domain_name) {
    return $base->clone(
        name => $name
        ,user => user_admin
    );
}

sub test_remove_rename($vm) {
    Test::Ravada::_check_leftovers_domains();
    my $base= create_domain($vm->type);
    my $name = new_domain_name();
    my $base2 = _clone($base, $name);
    $base2->prepare_base(user_admin);
    my @volumes_base = $base->list_files_base();
    my $clone = _clone($base);

    $base2->remove_base(user_admin);
    $base2->rename(name => new_domain_name, user => user_admin);

    my $clone2;
    eval { $clone2 = _clone($base, $name); };
    is($@,'') or exit;
    $clone2 = rvd_back->search_domain($name);
    ok($clone2);
    $clone2->remove(user_admin);

    for my $vol (@volumes_base, $base2->list_volumes) {
        ok( -e $vol,$vol);
    }

    my $clone3 = _clone($base);
    $clone3->start(user_admin);

    _remove_domain($base, $base2);
    Test::Ravada::_check_leftovers_domains();
}

sub _remove_domain(@domain) {
    for my $domain (@domain) {
        for my $clone_data ($domain->clones) {
            my $clone = Ravada::Domain->open($clone_data->{id});
            $clone->remove(user_admin);
        }
        my $domain2;
        eval {
            $domain2 = Ravada::Domain->open($domain->id);
            $domain2->remove(user_admin);
        };
        die $@ if $@ && $@!~ /Domain not found/;
    }
}

sub test_remove_parent_already_removed($vm){
    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    my $name = new_domain_name();
    Ravada::Request->clone(
        id_owner => user_admin->id
        ,uid => user_admin->id
        ,name => $name
        ,id_domain=> $base->id
    );
    wait_request();
    my $clone = rvd_back->search_domain($name);
    remove_domain_internal($base);
    my $req = Ravada::Request->remove_domain(
        uid => user_admin->id
        ,name => $clone->name
    );
    wait_request();
    is($req->status,'done');
    is($req->error, '');
    my $clone2 = rvd_back->search_domain($name);
    ok(!$clone2);
    remove_domain($base);
}

##############################################################################

clean();

use_ok('Ravada');

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

        diag("Testing remove on $vm_name");

        test_remove_parent_already_removed($vm);
        test_remove_rename($vm);
		test_remove_domain($vm);        
        test_remove_domain_volumes_already_gone($vm);

    }
}

end();

done_testing();
