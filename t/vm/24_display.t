use warnings;
use strict;

use Carp qw(confess cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

###############################################################################

sub test_rdp_default($vm) {

    my $settings = rvd_front->settings_global();
    ok(exists $settings->{display}) or die;
    ok(exists $settings->{display}->{rdp}) or die;

    my $expected_bpp = 16;

    rvd_back->setting("/display/rdp/session bpp" => $expected_bpp);

    my $domain = create_domain($vm);
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display' 
        ,data => { driver => 'rdp' }
    );
    wait_request();

    my $display = $domain->_get_display('rdp' );
    ok($display) or return;
    my $file_rdp = $domain->_display_file_rdp($display);

    my ($bpp) = $file_rdp =~ m{^session bpp:i:(\d+)}ms;
    is($bpp, $expected_bpp);

}

sub test_rdp_custom($vm) {

    my $domain = create_domain($vm);
    my $expected_bpp = 24;
    Ravada::Request->add_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,name => 'display' 
        ,data => { driver => 'rdp' ,  'session bpp' => $expected_bpp
        }
    );
    wait_request();

    my $display = $domain->_get_display('rdp' );
    my $file_rdp = $domain->_display_file_rdp($display);

    my ($bpp) = $file_rdp =~ m{^session bpp:i:(\d+)}ms;
    is($bpp, $expected_bpp);

}
###############################################################################

init();

for my $vm_name ( vm_names() ) {

    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        test_rdp_default($vm);
        test_rdp_custom($vm);
    }
}

end();
done_testing();
