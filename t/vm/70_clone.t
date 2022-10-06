use warnings;
use strict;

use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector() );

my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

###############################################################################

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name));
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}
sub test_clone {
    my ($vm_name, $base) = @_;
    my $description = "The description for base ".$base->name." text $$";
    $base->description($description);
    is($base->description,$description);

                my $clone1;

                my $name_clone = new_domain_name();
#                diag("[$vm_name] Cloning from base ".$base->name." to $name_clone");
                $base->is_public(1);
                eval { $clone1 = $base->clone(name => $name_clone, user => user_admin ) };
                ok(!$@,"Expecting error='', got='".($@ or '')."'")
                        or die Dumper($base->list_requests);
                ok($clone1,"Expecting new cloned domain from ".$base->name) or return;

    is($clone1->description,undef);
                $clone1->shutdown_now( user_admin ) if $clone1->is_active();
                eval { $clone1->start( user_admin ) };
                is($@,'');
                ok($clone1->is_active);

                my $clone1b = $RVD_FRONT->search_domain($name_clone);
                ok($clone1b,"Expecting new cloned domain ".$name_clone);
                $clone1->shutdown_now( user_admin ) if $clone1->is_active;
                ok(!$clone1->is_active);
    is($clone1b->description,undef,"[$vm_name] description for "
            .$clone1b->name);
    return $clone1;
}

sub test_mess_with_bases {
    my ($vm_name, $base, $clones) = @_;
    for my $clone (@$clones) {
        $clone->force_shutdown( user_admin )   if $clone->is_active;
        ok($clone->id_base,"Expecting clone has id_base , got "
                .($clone->id_base or '<UNDEF>'));
        $clone->prepare_base( user_admin );
    }

    for my $clone (@$clones) {
        next if $clone->is_base;
        eval { $clone->start($USER); };
        ok(!$@,"Expecting error: '' , got: ".($@ or '')) or exit;

        ok($clone->is_active);
        $clone->force_shutdown($USER)   if $clone->is_active;

        $clone->remove_base($USER);
        eval { $clone->start($USER); };
        ok(!$@,"[$vm_name] Expecting error: '' , got '".($@ or '')."'");
        ok($clone->is_active);
        $clone->force_shutdown($USER);
    }
}

sub test_description {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name) or return;

    my $domain = test_create_domain($vm_name);
    $domain->prepare_base(user_admin);
    $domain->is_public(1);
    my $clone = $vm->create_domain(
             name => new_domain_name()
         ,id_base => $domain->id
        ,id_owner => $USER->id
    );
    is($clone->description, undef);
    $clone->prepare_base( user_admin );
    is($clone->description, $domain->description);
    $clone->remove($USER);
}

sub test_clone_default_name($vm) {
    my $base = create_domain($vm);
    $base->prepare_base(user_admin);
    $base->is_public(1);
    my $user = create_user(new_domain_name(),$$);
    my $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
    );
    wait_request( check_error => 0);
    ok($req->status,'done');
    is($req->error,'');
    my @clones = $base->clones;
    is($clones[0]->{name},$base->name."-".$user->name) or exit;

    $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
    );
    wait_request( check_error => 0);
    ok($req->status,'done');
    is($req->error,'');
    my @clones2 = $base->clones;
    is(scalar(@clones2),2);

}

sub test_clone_private($vm) {
    my $base = create_domain($vm);
    my $user = create_user(new_domain_name(),$$);
    my $name = new_domain_name();
    my $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
        ,name => $name
    );
    wait_request( check_error => 0);
    ok($req->status,'done');
    like($req->error,qr(.));
    my $clone = $vm->search_domain($name);
    ok(!$clone);

    $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
        ,name => $name
        ,id_owner => $user->id
    );
    wait_request( check_error => 0);
    ok($req->status,'done');
    like($req->error,qr(.));
    $clone = $vm->search_domain($name);
    ok(!$clone);

    my $bases = rvd_front->list_machines_user($user);
    ok(! grep { $_->{name} eq $base->name } @$bases);

    $req = Ravada::Request->clone(
        uid => user_admin->id
        ,id_domain => $base->id
        ,name => $name
        ,id_owner => $user->id
    );
    wait_request( check_error => 0);
    ok($req->status,'done');
    is($req->error, '');
    $clone = $vm->search_domain($name);
    ok($clone);

    my $bases2 = rvd_front->list_machines_user($user);
    my ($base_user) = grep { $_->{name} eq $base->name } @$bases2;
    ok($base_user);
    is($base_user->{name_clone},$name);

    $clone->remove(user_admin);
    $base->remove(user_admin);
}

###############################################################################
remove_old_domains();
remove_old_disks();

for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM") if $vm_name !~ /Void/i;

    my $vm;
    eval { $vm = $RVD_BACK->search_vm($vm_name) } if $RVD_BACK;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok("Ravada::VM::$vm_name");
        test_description($vm_name);
        test_clone_private($vm);
        test_clone_default_name($vm);

        my $domain = test_create_domain($vm_name);

        eval { $domain->start($USER) if !$domain->is_active() };
        is($@,'');
        ok($domain->is_active);
        $domain->shutdown_now($USER);

        my @domains = ( $domain);
        my $n = 1;
        for my $depth ( 1 .. 3 ) {

            my @bases = @domains;

            for my $base(@bases) {

                my @clones;
                for my $n_clones ( 1 .. 2 ) {
                    my $clone = test_clone($vm_name,$base);
                    ok($clone->id_base,"Expecting clone has id_base , got "
                        .($clone->id_base or '<UNDEF>'));

                    push @clones,($clone) if $clone;
                }
                test_mess_with_bases($vm_name, $base, \@clones);
                push @domains,(@clones);
             }
        }
    }
}

end();
done_testing();
