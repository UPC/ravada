use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $FILE_CONFIG = 't/etc/ravada.conf';

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, $FILE_CONFIG);

my $USER = create_user('foo','bar');

#########################################################################
#
# test a new domain withou an ISO file
#

sub test_custom_iso {
    my $vm_name = shift;
    my $swap = shift;

    my %args_create = ();
    $args_create{swap} = 1000000  if $swap;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"Expecting a vm of type $vm_name") or return;

    my $id_iso = search_id_iso("windows_7");

    my $name = new_domain_name();

    my $domain;
    eval {$domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , id_iso => $id_iso
                    , active => 0
                    , %args_create
           );
    };
    like($@,qr'Template .* has no URL'i);
    ok(!$domain,"Expecting no domain created, got ".($domain or '<UNDEF>'));

    $domain->remove($USER)  if $domain;

    my $iso_file = $vm->dir_img."/".new_domain_name().".iso";
    open my $out, ">",$iso_file or die $!;
    print $out "hola\n";
    close $out;

    eval {$domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , id_iso => $id_iso
                    , active => 0
                    , iso_file => $iso_file
                    , %args_create
		    , remove_cpu => 1
           );
    };
    is($@,'');
    ok($domain,"Expecting domain created, got ".($domain or '<UNDEF>'));

    eval {   $domain->start($USER) if !$domain->is_active; };
    ok(!$@,"Expecting no error, got ".($@ or ''));

    unlink $iso_file if -e $iso_file;
}

sub test_custom_iso_swap {
    test_custom_iso(@_,'swap');
}

#########################################################################

clean();

my $vm;
my $vm_name = 'KVM';

eval { $vm = rvd_back->search_vm('KVM') };
diag($@) if $@;
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    if ($vm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    use_ok("Ravada::VM::$vm_name");
    test_custom_iso($vm_name);
    test_custom_iso_swap($vm_name);

};

clean();

done_testing();
