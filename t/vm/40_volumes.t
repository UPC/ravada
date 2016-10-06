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

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my @VMS = keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");
#######################################################################33

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

sub test_add_volume {
    my $domain = shift;

    $domain->add_volume(1);

    my @volumes = $domain->list_volumes();

    ok(scalar @volumes == 2,"Expecting 2 volumes, got ".scalar(@volumes));
}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;

    eval { $domain->prepare_base( $USER) };
    ok(!$@, $@);
    ok($domain->is_base);

    my @files_base= $domain->list_files_base();

    ok(scalar @files_base == 2, "Expecting 2 files base, got ".scalar(@files_base));

    my $name_clone = new_domain_name();
    my $domain_clone = $RVD_BACK->create_domain(
        name => $name_clone
        ,id_owner => $USER->id
        ,id_base => $domain->id
        ,vm => $vm_name
    );
    ok($domain_clone);
    ok(! $domain_clone->is_base,"Clone domain should not be base");

    my @volumes = $domain_clone->list_volumes();

    ok(scalar @volumes == 2,"Expecting 2 volumes, got ".scalar(@volumes));


}

#######################################################################33

remove_old_domains();
remove_old_disks();

for my $vm_name (@VMS) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS);

    my $vm;
    eval { $vm = $RVD_BACK->search_vm($vm_name) } if $RVD_BACK;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        my $domain = test_create_domain($vm_name);
        test_add_volume($domain);
        test_prepare_base($vm_name, $domain);
    }
}

remove_old_domains();
remove_old_disks();

done_testing();

