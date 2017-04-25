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

my $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG);
my $RVD_FRONT= rvd_front($test->connector, $FILE_CONFIG);

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my @VMS = reverse keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");

###############################################################################

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    if (!$ARG_CREATE_DOM{$vm_name}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}})
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
                my $clone1;
                my $name_clone = new_domain_name();
#                diag("[$vm_name] Cloning from base ".$base->name." to $name_clone");
                eval { $clone1 = $base->clone(name => $name_clone, user => $USER) };
                ok(!$@,"Expecting error='', got='".($@ or '')."'");
                ok($clone1,"Expecting new cloned domain from ".$base->name) or last;

                $clone1->shutdown_now($USER) if $clone1->is_active();
                eval { $clone1->start($USER) };
                is($@,'');
                ok($clone1->is_active);

                my $clone1b = $RVD_FRONT->search_domain($name_clone);
                ok($clone1b,"Expecting new cloned domain ".$name_clone);
                $clone1->shutdown_now($USER) if $clone1->is_active;
                ok(!$clone1->is_active);
    return $clone1;
}

sub test_mess_with_bases {
    my ($vm_name, $base, $clones) = @_;
    for my $clone (@$clones) {
        $clone->shutdown(user => $USER, timeout => 1)   if $clone->is_active;
        ok($clone->id_base,"Expecting clone has id_base , got "
                .($clone->id_base or '<UNDEF>'));
        $clone->prepare_base($USER);
    }

    $base->remove_base($USER);
    is($base->is_base,0);

    for my $clone (@$clones) {
        eval { $clone->start($USER); };
        ok(!$@,"Expecting error: '' , got: ".($@ or '')) or exit;

        ok($clone->is_active);
        $clone->shutdown(user => $USER, timeout => 1)   if $clone->is_active;

        $clone->remove_base($USER);
        eval { $clone->start($USER); };
        ok(!$@,"[$vm_name] Expecting error: '' , got '".($@ or '')."'");
        ok($clone->is_active);
        $clone->shutdown(user => $USER, timeout => 1);

    }
}
###############################################################################
remove_old_domains();
remove_old_disks();

for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM") if $vm_name !~ /Void/i;

    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS);
    my $vm;

    eval { $vm = $RVD_BACK->search_vm($vm_name) } if $RVD_BACK;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

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

remove_old_domains();
remove_old_disks();

done_testing();
