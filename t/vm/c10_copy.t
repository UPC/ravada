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

sub add_volumes {
    my ($base, $volumes) = @_;
    $base->add_volume_swap(name => "vol_swap", size => 512 * 1024);
    for my $n ( 1 .. $volumes ) {
        $base->add_volume(name => "vol_$n", size => 512 * 1024);
    }
}

sub test_copy_clone {
    my $vm_name = shift;
    my $volumes = shift;

    my $base = create_domain($vm_name);

    add_volumes($base, $volumes)  if $volumes;

    my $name_clone = new_domain_name();

    my $clone = $base->clone(
        name => $name_clone
        ,user => user_admin
    );

    is($clone->is_base,0);
    for ( $clone->list_volumes ) {
        open my $out,'>',$_ or die $!;
        print $out "hola $_\n";
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

    my @copy_volumes = $copy->list_volumes_target();
    my %copy_volumes = map { $_->[1] => $_->[0] } @copy_volumes;
    my @clone_volumes = $clone->list_volumes_target();
    my %clone_volumes = map { $_->[1] => $_->[0] } @clone_volumes;

    for my $target ( keys %copy_volumes ) {
        isnt($copy_volumes{$target}, $clone_volumes{$target});
        my @stat_copy = stat($copy_volumes{$target});
        my @stat_clone = stat($clone_volumes{$target});
        is($stat_copy[7],$stat_clone[7],"[$vm_name] size different "
                ."\n$copy_volumes{$target} ".($stat_copy[7])
                ."\n$clone_volumes{$target} ".($stat_clone[7])
        ) or exit;

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
        test_copy_clone($vm_name,1);
        test_copy_clone($vm_name,2);
        test_copy_clone($vm_name,10);
    }

}

clean();

done_testing();

