#!perl

use strict;
use warnings;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use Ravada;

use Ravada::Domain;
use Data::Dumper;
# create the mock database
my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

# init ravada for testing
init();

##############################################################################
# full test
##############################################################################

sub test_rename {
    my ($vm_name, $vm_hash, $domain_name, $domain_hash, $user) = @_;
    my $new_domain_name = new_domain_name();    
    {
        my $rvd_back = rvd_back();
        ok($domain_hash,"[$vm_name] Expecting found $domain_name") 
            or return;

        eval { $domain_hash->rename(name => $new_domain_name, user => $user) };
        ok(!$@,"Expecting error='' , got ='".($@ or '')."'") or return;
    }

    my $domain_hash_0 = $vm_hash->search_domain($domain_name);
    ok(!$domain_hash_0,"[$vm_name] Expecting not found $domain_name");

    my $domain_hash_1 = $vm_hash->search_domain($new_domain_name);
    ok($domain_hash_1,"[$vm_name] Expecting renamed domain $new_domain_name") 
        or return;

    return $new_domain_name;
}

sub test_can_list_all {
    my ($vm_hash, $vm_name, $user) = @_;
    my ($domain_hash_0, $domain_name_0) = create_simple_domain($vm_hash, $vm_name, user_admin);
    my ($domain_hash_1, $domain_name_1) = create_simple_domain($vm_hash, $vm_name, $user);
    
    my $list = rvd_front->list_machines($user);
    ok(grep { $_->{'name'} eq $domain_name_0 } @$list );
    ok(grep { $_->{'name'} eq $domain_name_1 } @$list );
    
    $domain_hash_1->remove(user_admin);
    $domain_hash_0->remove(user_admin);
}

sub test_list_clones_from_own_base {
    my ($vm_hash, $vm_name, $user) = @_;
    
    my ($domain_hash_0, $domain_name_0) = create_simple_domain($vm_hash, $vm_name, user_admin);
    my ($domain_hash_1, $domain_name_1) = create_simple_domain($vm_hash, $vm_name, $user);
    my ($domain_hash_2, $domain_name_2) = create_simple_clone($domain_hash_1, user_admin);
    
    my $list = rvd_front->list_machines($user);
    ok(grep { $_->{'name'} eq $domain_name_1} @$list );
    ok(grep { $_->{'name'} eq $domain_name_2 } @$list );
    is(scalar @$list, 2);
    
    $domain_hash_2->remove(user_admin);
    $domain_hash_1->remove(user_admin);
    $domain_hash_0->remove(user_admin);
}

sub create_simple_domain {
    my ($vm_hash, $vm_name, $user) = @_;
    my $domain_name = new_domain_name();
    my $domain_hash = $vm_hash->create_domain(name => $domain_name
                    , id_owner => $user->id
                    , arg_create_dom($vm_name));
    $domain_hash->stop() if $domain_hash->is_active();
    
    return ($domain_hash, $domain_name);
}

sub create_simple_clone {
    my ($domain_hash, $user) = @_;
    $domain_hash->prepare_base( $user );
    $domain_hash->is_public(1);
    my $clone_name = new_domain_name;
    my $clone_hash = $domain_hash->clone(
          name => $clone_name
        , user => $user
    );
    $clone_hash->stop() if $clone_hash->is_active();
    return ($clone_hash, $clone_name);
}

##############################################################################
# environment
##############################################################################

sub test_admin_grant {
    my ($vm_hash, $vm_name) = @_;
    my ($domain_hash, $domain_name) = create_simple_domain($vm_hash, $vm_name, user_admin);
    test_rename($vm_name, $vm_hash, $domain_name, $domain_hash, user_admin);
    
    $domain_hash->remove(user_admin);
}

sub test_own_grant {
    my ($vm_hash, $vm_name) = @_;
    my $user_own = create_user("kevin.garvey","sleepwalk");
    user_admin->grant($user_own,'create_machine');
    user_admin->grant($user_own,'rename');
    
    my ($domain_hash, $domain_name) = create_simple_domain($vm_hash, $vm_name, $user_own);
    test_rename($vm_name, $vm_hash, $domain_name, $domain_hash, $user_own);
    
    $domain_hash->remove(user_admin);
    $user_own->remove();
}

sub test_all_grant {
    my ($vm_hash, $vm_name) = @_;
    my $user_all = create_user("kevin.garvey2","sleepwalk");
    user_admin->grant($user_all,'create_machine');
    user_admin->grant($user_all,'rename_all');
    
    test_can_list_all($vm_hash, $vm_name, $user_all);
    
    my ($domain_hash, $domain_name) = create_simple_domain($vm_hash, $vm_name, user_admin);
    test_rename($vm_name, $vm_hash, $domain_name, $domain_hash, $user_all);
    
    
    $domain_hash->remove(user_admin);
    $user_all->remove();
}

sub test_clones_grant {
    my ($vm_hash, $vm_name) = @_;
    my $user_clones = create_user("kevin.garvey3","sleepwalk");
    user_admin->grant($user_clones,'create_machine');
    user_admin->grant($user_clones,'rename_clones');
    
    test_list_clones_from_own_base($vm_hash, $vm_name, $user_clones);
    
    my ($domain_hash, $domain_name) = create_simple_domain($vm_hash, $vm_name, $user_clones);
    my ($clone_hash, $clone_name) = create_simple_clone($domain_hash, user_admin);
    test_rename($vm_name, $vm_hash, $clone_name, $clone_hash, $user_clones);

    $clone_hash->remove(user_admin);
    $domain_hash->remove(user_admin);
    $user_clones->remove();
}

##############################################################################
# main
##############################################################################

clean();
use_ok('Ravada');

for my $vm_name ( vm_names() ) {

    my $vm_hash;
    eval { $vm_hash = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm_hash && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm_hash = undef;
        }

        diag($msg)      if !$vm_hash;
        skip $msg,10    if !$vm_hash;
        
        diag("Testing rename on $vm_name");
        
        test_admin_grant($vm_hash, $vm_name);
        test_own_grant($vm_hash, $vm_name);
        test_all_grant($vm_hash, $vm_name);
        test_clones_grant($vm_hash, $vm_name);
    }
}

clean();
done_testing();
