use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
init($test->connector);

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

##########################################################################3

sub test_copy_clone {
    my $vm_name = shift;

    my $base = create_domain($vm_name);

    my $name_clone = new_domain_name();

    my $clone = $base->clone(
        name => $name_clone
        ,user => user_admin
    );

    is($clone->is_base,0);
    for ( $clone->list_volumes ) {
        open my $out,'>',$_ or die $!;
        print $out "hola\n";
        close $out;
    }

    my $name_copy = new_domain_name();
    my $copy = $clone->clone(
        name => $name_copy
        ,user => user_admin
    );
    is($clone->is_base,0);
    is($copy->is_base,0);

    is($copy->id_base, $base->id);

    is(scalar($copy->list_volumes),scalar($clone->list_volumes));

    my @copy_volumes = $copy->list_volumes();
    my @clone_volumes = $clone->list_volumes();

    for ( 0 .. $#copy_volumes ) {
        isnt($copy_volumes[$_], $clone_volumes[$_]);
        is(-s $copy_volumes[$_], -s $clone_volumes[$_],"[$vm_name] size of $copy_volumes[$_]");

    }
}

##########################################################################3

clean();


for my $vm_name ('Void', 'KVM') {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        test_copy_clone($vm_name);
    }

}

clean();

done_testing();

