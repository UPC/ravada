use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

##############################################################
clean();

for my $vm_name ( vm_names() ) {
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing vol spinoff for $vm_name");
        my $base = create_domain($vm);
        my $clone = $base->clone(name => new_domain_name, user => user_admin);
        mangle_volume($vm, "spinoff", $clone->list_volumes);
        $clone->spinoff_volumes();
        for my $vol ( $clone->list_volumes_info ) {
            is($vol->info->{backing_file}, undef);
            test_volume_contents($vm,"spinoff", $vol->file);
        }
    }
}

clean();

done_testing();
