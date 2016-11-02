use warnings;
use strict;

use Carp qw(confess);
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
    my $vm = shift;
    my $domain = shift;
    my $volume_name = shift or confess "Missing volume name";

    my @volumes = $domain->list_volumes();

#    diag("[".$domain->vm."] adding volume $volume_name to domain ".$domain->name);

    $domain->add_volume(name => $domain->name.".$volume_name", size => 512*1024 , vm => $vm);

    my @volumes2 = $domain->list_volumes();

    ok(scalar @volumes2 == scalar @volumes + 1,
        "[".$domain->vm."] Expecting ".(scalar @volumes+1)." volumes, got ".scalar(@volumes2))
        or exit;
}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;

    my @volumes = $domain->list_volumes();
#    diag("[$vm_name] preparing base for domain ".$domain->name);
    my @img;
    eval {@img = $domain->prepare_base( $USER) };
    ok(!$@, $@);
    ok($domain->is_base,"[$vm_name] Domain ".$domain->name." sould be base");
#    diag("[$vm_name] ".Dumper(\@img));


    my @files_base= $domain->list_files_base();
    ok(scalar @files_base == scalar @volumes, "[$vm_name] Domain ".$domain->name
        ." expecting ".scalar @volumes." files base, got ".scalar(@files_base)) or exit;

}

sub test_clone {
    my $vm_name = shift;
    my $domain = shift;

    my @volumes = $domain->list_volumes();

    my $name_clone = new_domain_name();
#    diag("[$vm_name] going to clone from ".$domain->name);
    my $domain_clone = $RVD_BACK->create_domain(
        name => $name_clone
        ,id_owner => $USER->id
        ,id_base => $domain->id
        ,vm => $vm_name
    );
    ok($domain_clone);
    ok(! $domain_clone->is_base,"Clone domain should not be base");

    my @volumes_clone = $domain_clone->list_volumes();

    ok(scalar @volumes_clone == scalar @volumes
        ,"[$vm_name] Expecting ".scalar @volumes." volumes, got ".scalar(@volumes));

    my %volumes_clone = map { $_ => 1 } @volumes_clone ;

    ok(scalar keys %volumes_clone == scalar @volumes_clone
        ,"check duplicate files cloned ".join(",",sort keys %volumes_clone)." <-> "
        .join(",",sort @volumes_clone));

    return $domain_clone;
}

sub test_files_base {
    my ($vm_name, $domain, $volumes) = @_;
    my @files_base= $domain->list_files_base();
    ok(scalar @files_base == scalar @$volumes, "[$vm_name] Domain ".$domain->name
            ." expecting ".scalar @$volumes." files base, got ".scalar(@files_base)) or exit;

    my %files_base = map { $_ => 1 } @files_base;

    ok(scalar keys %files_base == scalar @files_base
        ,"check duplicate files base ".join(",",sort keys %files_base)." <-> "
        .join(",",sort @files_base));

}

#######################################################################33

remove_old_domains();
remove_old_disks();

for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS);

    my $vm;
    eval { $vm = $RVD_BACK->search_vm($vm_name) } if $RVD_BACK;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        ################################################################
        #
        # Domain with 1 volume
        #
        my $domain = test_create_domain($vm_name);
        test_prepare_base($vm_name, $domain);
        my $domain_clone = test_clone($vm_name, $domain);
        $domain = undef;
        $domain_clone = undef;

        ################################################################
        #
        # Domain with more than 1 volume
        #

        my $domain2 = test_create_domain($vm_name);
        test_add_volume($vm, $domain2, 'vdb');

        my @volumes = $domain2->list_volumes;
        ok(scalar @volumes == 2
            ,"[$vm_name] Expecting 2 volumes, got ".scalar(@volumes));

        test_prepare_base($vm_name, $domain2);
        test_files_base($vm_name, $domain2, \@volumes);

        my $domain2_clone = test_clone($vm_name, $domain2);
        
        test_add_volume($vm, $domain2, 'vdc');

        @volumes = $domain2->list_volumes;
        ok(scalar @volumes == 3
            ,"[$vm_name] Expecting 3 volumes, got ".scalar(@volumes));


        $domain2 = undef;
        $domain_clone = undef;
    }
}

remove_old_domains();
remove_old_disks();

done_testing();

