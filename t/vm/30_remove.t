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

sub test_remove_domain {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);
    $domain->remove($USER);

    my $domain_missing = rvd_back()->search_domain($domain->name);
    ok(!$domain_missing,"Domain ".$domain->name." should be missing");
}

sub test_remove_domain_base {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);
    $domain->prepare_base($USER);
    eval { $domain->remove($USER) };
    ok(!$@,$@);

    my $domain_missing = rvd_back()->search_domain($domain->name);
    ok(!$domain_missing,"Domain ".$domain->name." should be missing");

}


sub test_dont_remove_father {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);
    $domain->prepare_base($USER);

    my $name_clone = new_domain_name();

    my $clone = rvd_back()->create_domain( name => $name_clone
            ,id_owner => $USER->id
            ,id_base => $domain->id
            ,vm => $vm_name
    );
    eval { $domain->remove($USER) };
    ok($@ && $@ =~ /has.*clone/i , "Domain with clones should not be removed ".($@ or ''));

    my $domain_found = rvd_back()->search_domain($domain->name);
    ok($domain_found," domain ".$domain->name." should not be removed");

}

sub test_prepare_base {
    my $vm_name = shift;
    my $domain = shift;

    eval { $domain->prepare_base( $USER) };
    ok(!$@, $@);
    ok($domain->is_base);

    eval { $domain->prepare_base( $USER) };
    ok($@ && $@ =~ /already/i,"[$vm_name] Don't prepare if already prepared and file haven't changed "
        .". Error: ".($@ or '<UNDEF>'));
    ok($domain->is_base);

    my $disk = $domain->disk_device();
    $domain->shutdown;

    touch_mtime($disk);

    eval { $domain->prepare_base( $USER) };
    ok(!$@,"Trying to prepare base again failed, it should have worked. ");
    ok($domain->is_base);

    my $name_clone = new_domain_name();

    my $domain_clone = $RVD_BACK->create_domain(
        name => $name_clone
        ,id_owner => $USER->id
        ,id_base => $domain->id
        ,vm => $vm_name
    );
    ok($domain_clone);
    touch_mtime($disk);
    eval { $domain->prepare_base($USER) };
    ok($@ && $@ =~ /has \d+ clones/i
        ,"[$vm_name] Don't prepare if there are clones ".($@ or '<UNDEF>'));
    ok($domain->is_base);

    $domain_clone->remove($USER);

    eval { $domain->prepare_base($USER) };
    ok(!$@,"[$vm_name] Error preparing base after clone removed :'".($@ or '')."'");
    ok($domain->is_base);
}

sub touch_mtime {
    my $disk = shift;

    my @stat0 = stat($disk);

    sleep 2;
    open my $touch,'>>',$disk or die "$! $disk";
    print $touch " ";
    close $touch;
    my @stat1 = stat($disk);

    die "$stat0[9] not before $stat1[9] for $disk" if $stat0[9] >= $stat1[9];

}

#######################################################################33


remove_old_domains();
remove_old_disks();

for my $vm_name (@VMS) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";

    use_ok($CLASS);

    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_remove_domain($vm_name);
        test_remove_domain_base($vm_name);
        test_dont_remove_father($vm_name);
    }
}

remove_old_domains();
remove_old_disks();

done_testing();
