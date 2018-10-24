use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw(lock_hash);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

use Ravada::Auth::LDAP;
my $CONFIG_FILE = 't/etc/ravada_ldap.conf';

init( $CONFIG_FILE );
delete $Ravada::CONFIG->{ldap}->{ravada_posix_group};

sub test_external_auth {
    my ($name, $password) = ('jimmy','jameson');
    create_ldap_user($name, $password);
    my $login_ok;
    eval { $login_ok = Ravada::Auth::login($name, $password) };
    is($@, '');
    ok($login_ok,"Expecting login with $name") or return;

    my $user = Ravada::Auth::SQL->new(name => $name);
    is($user->external_auth, 'ldap') or exit;

    my $sth = connector->dbh->prepare(
        "UPDATE users set external_auth = '' "
        ." WHERE id=?"
    );
    $sth->execute($user->id);

    $user = Ravada::Auth::SQL->new(name => $name);
    is($user->external_auth, '') or exit;

    eval { $login_ok = Ravada::Auth::login($name, $password) };
    is($@, '');
    ok($login_ok,"Expecting login with $name") or return;

    $user = Ravada::Auth::SQL->new(name => $name);
    is($user->external_auth, 'ldap') or exit;
}

sub test_access_by_attribute($vm) {

    my $data = {
        student => { name => 'student', password => 'aaaaaaa' }
        ,teacher => { name => 'teacher', password => 'bbbbbbb' }
    };
    lock_hash(%$data);
    for my $type ( keys %$data) {
        create_ldap_user($data->{$type}->{name}, $data->{$type}->{password});

        my $login_ok;
        eval { $login_ok = Ravada::Auth::login($data->{$type}->{name}, $data->{$type}->{password}) };
        is($@, '');
        ok($login_ok,"Expecting login with $data->{$type}->{name}") or return;
        $data->{$type}->{user} = Ravada::Auth::SQL->new(name => $data->{$type}->{name});
    }
    lock_hash(%$data);

    my $base_student = create_domain($vm->type);
    $base_student->prepare_base(user_admin);
    $base_student->is_public(1);

    my $base_teacher= create_domain($vm->type);
    $base_teacher->prepare_base(user_admin);
    $base_teacher->is_public(1);

    my $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 2);

    #################################################################
    #
    # check access to bases
    #
    #  all should be allowed now
    is($data->{student}->{user}->allowed_access( $base_student->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base_student->id ), 1);
    is(user_admin->allowed_access( $base_student->id ), 1);

    is($data->{student}->{user}->allowed_access( $base_teacher->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base_teacher->id ), 1);
    is(user_admin->allowed_access( $base_teacher->id ), 1);

    my ($entry) = Ravada::Auth::LDAP::search_user(name => $data->{student}->{name});
    ok($entry) or return;
    $entry->add( tipology => 'student');

    $base_student->allow_ldap_attribute( tipology => 'student');

    #################################################################
    #
    # check access to bases
    #
    #  only students and admin should be allowed now
    is($data->{student}->{user}->allowed_access( $base_student->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base_student->id ), 0);
    is(user_admin->allowed_access( $base_student->id ), 1);


    $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 1);

    $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
    is(scalar (@$list_bases), 0);

    $list_bases = rvd_front->list_machines_user(user_admin);
    is(scalar (@$list_bases), 2);

    $base_student->remove(user_admin);
    $base_teacher->remove(user_admin);
}
################################################################################

clean();


for my $vm_name ('KVM', 'Void') {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        diag("Testing LDAP access for $vm_name");

        test_external_auth();
        test_access_by_attribute($vm);
    }

}

clean();

done_testing();

