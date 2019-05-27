use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector() );

my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

my $DISPLAY_IP = '99.1.99.1';

#######################################################################33

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
                    , arg_create_dom($vm_name))
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
    my ($vm_name, $domain) = @_;

    $domain->is_public(1);
    my $clone = $domain->clone(name => new_domain_name(), user => user_admin );
    ok($clone);

    return $clone;
}

sub test_files_base {
    my ($domain, $n_expected) = @_;

    confess("Expecting a domain , got ".Dumper(\@_))
        if !ref $domain;
    my @files = $domain->list_files_base();

    ok(scalar @files == $n_expected,"Expecting $n_expected files base , got "
            .scalar @files);
    return;
}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;

    test_files_base($domain,0);

    eval { $domain->prepare_base( user_admin ) };
    ok(!$@, $@);
    ok($domain->is_base);

    eval { $domain->prepare_base( user_admin ) };
    ok($@ && $@ =~ /already/i,"[$vm_name] Don't prepare if already "
        ."prepared and file haven't changed "
        .". Error: ".($@ or '<UNDEF>'));
    ok($domain->is_base);

    test_files_base($domain,1);

#    is($domain->id_base,undef);
}

sub test_remove_base {
    my $vm_name = shift;
    my $domain = shift;
    my $domain_clone = shift;

    my @files = $domain->list_files_base();
    ok(scalar @files,"Expecting files base, got ".Dumper(\@files)) or return;

    eval { $domain->remove_base($USER) };
    is($@,'');

    ok(!$domain->is_base,"Domain ".$domain->name." should be base") or return;

    for my $file (@files) {
        ok(!-e $file,"Expecting file base '$file' removed" );
    }

    my $vm = rvd_back->search_vm($vm_name);
    my $domain_clone2 = $vm->search_domain($domain_clone->name);
    ok($domain_clone2,"Expecting clone still there");
}

sub test_remove_domain {
    my $vm_name = shift;
    my $domain = shift;
    my $domain_clone = shift;

    $domain->remove($USER);

    my $vm = rvd_back->search_vm($vm_name);
    my $domain2 = $vm->search_domain($domain->name);
    ok(!$domain2,"Expecting no domain after remove");

}

#######################################################################33


remove_old_domains();
remove_old_disks();

for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM");

    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok("Ravada::VM::$vm_name");
        my $domain = test_create_domain($vm_name);
        test_prepare_base($vm_name, $domain);
        my $domain_clone = test_clone($vm_name, $domain);
        test_prepare_base($vm_name, $domain_clone);
        test_remove_base($vm_name, $domain, $domain_clone);
        test_remove_domain($vm_name, $domain, $domain_clone);

    }
}

remove_old_domains();
remove_old_disks();

done_testing();
