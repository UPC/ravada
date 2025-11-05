use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user("foo","bar");

###################################################################

sub test_request {
    my $vm_name = shift;
    my $id_vm = shift;

    my $file = new_domain_name().".iso";

    my $vm = rvd_back->search_vm($vm_name);

    # clean old files
    my @files = $vm->search_volume_path($file);
    for my $old_file (@files) {
        unlink $old_file or die "$! $old_file"
            if -e $old_file;
    }
    $vm->refresh_storage_pools();

    # check there are no files
    @files = $vm->search_volume_path($file);
    ok(!scalar @files) or return;

    my $file_out = $vm->dir_img."/$file";
    unlink $file_out or die "$! $file_out"
        if -e $file_out;

    open my $out,'>',$file_out or die "$! $file_out";
    print $out "rosa d'abril\n";
    close $out;
    ok(-e $file_out,"Expecting a file $file_out");

    my $request;

    eval {
        my @args = ( uid => user_admin->id, _force => 1 );
        push @args,( id_vm => $id_vm ) if $id_vm;
        $request = Ravada::Request->refresh_storage(@args);
    };
    is($@,'');
    ok($request,"Expecting a request") or next;
    wait_request(debug => 0);

    is($request->status,'done');
    is($request->error,'');

    for (1 .. 3 ) {
        @files = $vm->search_volume_path($file);
        last if scalar(@files);
        $request->status('requested');
        wait_request(debug => 0);
    }
    ok(scalar @files,"Expecting $file exists on storage pool") or exit;
    $vm->remove_file($file);
}

#########################################################

clean();

for my $vm_name ( vm_names() ) {
   my $vm;
   my $msg = "SKIPPED: virtual manager $vm_name not found";
    eval {
        $vm= rvd_back->search_vm($vm_name)  if rvd_back();

        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm= undef;
        }

    };

    SKIP: {
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing requests with $vm_name");

        test_request($vm_name, $vm->id);
        test_request($vm_name);
    }


}

end();
done_testing();
