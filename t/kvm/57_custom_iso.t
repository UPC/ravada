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

    my $vm = rvd_back->search_vm($vm_name);
    my $id_iso = search_id_iso("windows_7");

    my $name = new_domain_name();

    my $domain;
    eval {$domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , id_iso => $id_iso
                    , active => 0
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
           );
    };
    is($@,'');
    ok($domain,"Expecting domain created, got ".($domain or '<UNDEF>'));

    eval {   $domain->start($USER) if !$domain->is_active; };
    ok($@,'');

    unlink $iso_file if -e $iso_file;
}

#########################################################################

clean();

my $vm;
my $vm_name = 'KVM';
use_ok("Ravada::VM::$vm_name");

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

    test_custom_iso($vm_name);

};

clean();

done_testing();
