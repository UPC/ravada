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

sub test_spinoff($base) {
    my $clone = $base->clone(name => new_domain_name, user => user_admin);
    is($clone->id_base,$base->id);
    for my $vol ( $clone->list_volumes_info ) {
        next if ref($vol) =~ /ISO/;
        like($vol->backing_file, qr(.),$vol->file) or exit;
    }
    mangle_volume($base->_vm, "spinoff", $clone->list_volumes);
    $clone->spinoff();

    $clone = Ravada::Domain->open($clone->id);
    is($clone->id_base,undef) or exit;

    for my $vol ( $clone->list_volumes_info ) {
        next if ref($vol) =~ /ISO/;

        my $backing_file;
        eval { $backing_file = $vol->backing_file };
        is($backing_file,undef, $vol->file);
        like($@,qr/No backing file/) if $@;

        test_volume_contents($base->_vm,"spinoff", $vol->file);
    }

    $clone->remove(user_admin);
    for my $file ($base->list_files_base) {
        ok(-e $file,$file) or exit;
    }
    for my $file ($base->list_volumes) {
        ok(-e $file,$file) or exit;
    }
}

sub test_remove_base($base) {
    $base->prepare_base(user_admin);
    for my $vol ($base->list_volumes_info) {
        my $file = $vol->file;
        next if $file =~ /\.iso$/;
        like($vol->backing_file,qr'.', $file) or exit;
        mangle_volume($base->_vm, "base", $file);
    }
    my @files_base = $base->list_files_base();
    $base->remove_base(user_admin);
    for my $file (@files_base) {
        ok(! -e $file,"Expecting no file base $file");
    }
    for my $file ($base->list_volumes) {
        ok(-e $file,"Expecting file $file");
        my $vol = Ravada::Volume->new(file => $file, vm => $base->_vm);
        is($vol->backing_file, undef);
        test_volume_contents($base->_vm,"base", $file);
    }
    is($base->is_base,0);
    is(scalar($base->list_files_base),0);
}
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

        test_remove_base($base);
        test_spinoff($base);
        $base->remove(user_admin);
    }
}

end();
done_testing();
