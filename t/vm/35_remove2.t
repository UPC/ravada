#!perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';
use Test::Ravada;

# init ravada for testing
init();
my $USER = create_user("foo","bar", 1);

##############################################################################

sub test_remove_domain {
    my $vm = shift;

    my $domain = create_domain($vm->type);
    $domain->shutdown( user => user_admin )  if $domain->is_active();
    
    if ($vm->type eq 'KVM') {
        $domain->domain->undefine();
    } elsif ($vm->type eq 'Void') {
        unlink $domain->_config_file() or die "$! ".$domain->_config_file;
    }

    my $removed = $domain->is_removed;

    ok($removed, "Domain deleted: $removed");
    
    eval{ $domain->remove(user_admin) };
    
    is($@,"");

    my $list = rvd_front->list_domains();
    is(scalar @$list , 0);

}

sub test_remove_domain_volumes_already_gone {
    my $vm = shift;
    my $domain = create_domain($vm->type);
    for my $file ($domain->list_disks) {
        next if $file =~ /iso/;
        unlink $file or die "$! $file";
    }
    $domain->storage_refresh() if $vm->type ne 'Void';
    my @volumes = $domain->list_volumes_info();
    for my $vol (@volumes) {
        next if $vol->file =~ /\.iso$/;
        ok(!-e $vol->file);
    }
    eval { $domain->remove(user_admin) };
    is(''.$@,'',$vm->type);
}

##############################################################################

clean();

use_ok('Ravada');

for my $vm_name ( vm_names() ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing remove on $vm_name");

		test_remove_domain($vm);        
        test_remove_domain_volumes_already_gone($vm);

    }
}

end();

done_testing();
