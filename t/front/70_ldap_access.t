use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

use Ravada::Auth::LDAP;

sub test_external_auth {
    my ($name, $password) = (new_domain_name().'.jimmy','jameson');
    create_ldap_user($name, $password);
    my $login_ok;
    eval { $login_ok = Ravada::Auth::login($name, $password) };
    is($@, '');
    ok($login_ok,"Expecting login with $name") or return;
    ok($login_ok->ldap_entry,"Expecting a LDAP entry for user $name in object ".ref($login_ok));

    my $user = Ravada::Auth::SQL->new(name => $name);
    is($user->external_auth, 'ldap') or exit;
    ok($user->ldap_entry,"Expecting a LDAP entry for user $name in object ".ref($user));

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

sub _create_users_2($multiple=0) {
    my $data = {
        student => { name => new_domain_name().".student".new_domain_name(), password => 'aaaaaaa' }
        ,teacher => { name => new_domain_name().".teacher".new_domain_name(), password => 'bbbbbbb' }
    };
    return _create_users($data, $multiple);
}

sub _delete_old_entries($name) {
    my @entries = _search_user( cn => $name );
    push @entries,(_search_user( givenName => $name ));
    my ($given_name) = $name =~ m{(.*)\.};
    push @entries,( _search_user( givenName => $given_name ) ) if $given_name;
    my $ldap = _init_ldap();
    for my $entry ( @entries ) {
        $ldap->delete($entry->dn);
    }
}

sub _create_users($data=undef, $multiple=0) {
    $data = {
        student => { name => "student", password => 'aaaaaaa' }
        ,teacher => { name => "teacher", password => 'bbbbbbb' }
    } if !$data;

    for my $type ( keys %$data) {
        _delete_old_entries($data->{$type}->{name});
        my $user = create_ldap_user($data->{$type}->{name}, $data->{$type}->{password});
        die "Error: not defined givenName ".$user->dn if !defined $user->get_value('givenName');
        if ($multiple) {
            my $ldap = _init_ldap();
            my $mesg = $ldap->modify($user->dn,
                add => { givenName => new_domain_name()}
            );
            die $mesg->error if $mesg->code;
            $user = _search($ldap, cn => $user->get_value('cn'));
        }

        my $login_ok;
        eval { $login_ok = Ravada::Auth::login(
                $data->{$type}->{name}
                , $data->{$type}->{password}) 
        };
        is($@, '');
        ok($login_ok,"Expecting login with $data->{$type}->{name}") or return;
        $data->{$type}->{user} = Ravada::Auth::SQL->new(name => $data->{$type}->{name});
    }
    my $other = { name => new_domain_name().".other", password => 'ccccccc' };
    create_user($other->{name}, $other->{password});
    $other->{user} = Ravada::Auth::SQL->new(name => $other->{name});
    $data->{other} = $other;

    ok($data->{other}->{user}->id);

    _refresh_users($data);
    lock_hash(%$data);
    return $data;
}

sub _refresh_users($data) {
    for my $key (keys %$data) {
        delete $data->{$key}->{user}->{_ldap_entry};
        delete $data->{$key}->{user}->{_load_allowed};
    }
}

sub _do_clones($data, $base, $do_clones) {

    return if !$do_clones;

    my $clone_student = $base->clone(
        name => new_domain_name
        ,user => $data->{student}->{user}
    );
    my $clone_teacher= $base->clone(
        name => new_domain_name
        ,user => $data->{teacher}->{user}
    );

    return ($clone_student, $clone_teacher);
}

sub test_access_by_attribute_deny($vm, $do_clones=0, $with_multiple=0) {
    my $data = _create_users_2();

    for my $given_name ($data->{student}->{user}->ldap_entry->get_value('givenName')) {
        diag("Testing deny given_name=$given_name");
        my $base = create_domain($vm->type);
        $base->prepare_base(user_admin);
        $base->is_public(1);

        is($data->{student}->{user}->allowed_access( $base->id ), 1);
        is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
        is($data->{other}->{user}->allowed_access( $base->id ), 1);

        my ($clone_student, $clone_teacher) = _do_clones($data, $base, $do_clones);

        $base->deny_ldap_access( givenName => $given_name);
        _refresh_users($data);
        is($data->{student}->{user}->allowed_access( $base->id ), 0) or exit;
        is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
        is($data->{other}->{user}->allowed_access( $base->id ), 1);

        $clone_student->remove(user_admin) if $clone_student;
        my $list_bases = rvd_front->list_machines_user($data->{student}->{user});
        is(scalar (@$list_bases), 0);

        $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
        is(scalar (@$list_bases), 1);

        # other has no external_auth, access denied
        $list_bases = rvd_front->list_machines_user($data->{other}->{user});
        is(scalar (@$list_bases), 1);

        $list_bases = rvd_front->list_machines_user(user_admin);
        is(scalar (@$list_bases), 1);

        _remove_bases($base);
    }
    _remove_users($data);
}

sub test_access_by_attribute_several($vm, $do_clones=0) {
    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $data = _create_users_2();
    is($data->{student}->{user}->allowed_access( $base->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
    is($data->{other}->{user}->allowed_access( $base->id ), 1);

    _do_clones($data, $base, $do_clones);

    $base->deny_ldap_access( givenName => $data->{student}->{user}->ldap_entry->get_value('givenName'));
    $base->allow_ldap_access( givenName => $data->{teacher}->{user}->ldap_entry->get_value('givenName'));
    $base->deny_ldap_access( givenName => '*'); #default policy
    _refresh_users($data);
    is($data->{student}->{user}->allowed_access( $base->id ), 0);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 1)
            or die Dumper($data->{teacher}->{user}->{_allowed});
    is($data->{other}->{user}->allowed_access( $base->id ), 0);

    my $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 0);

    $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
    is(scalar (@$list_bases), 1);

    # other has no external_auth, access denied
    $list_bases = rvd_front->list_machines_user($data->{other}->{user});
    is(scalar (@$list_bases), 0);

    $list_bases = rvd_front->list_machines_user(user_admin);
    is(scalar (@$list_bases), 1);

    _remove_bases($base);
    _remove_users($data);
}
sub test_access_by_attribute_several2($vm) {
    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $data = _create_users_2();
    is($data->{student}->{user}->allowed_access( $base->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
    is($data->{other}->{user}->allowed_access( $base->id ), 1);

    my $st_given_name = $data->{student}->{user}->ldap_entry->get_value('givenName');
    my $te_given_name = $data->{teacher}->{user}->ldap_entry->get_value('givenName');
    $base->allow_ldap_access( givenName => $st_given_name);
    $base->deny_ldap_access( sn => $data->{student}->{user}->ldap_entry->get_value('sn'));
    $base->allow_ldap_access( givenName => $te_given_name);
    $base->deny_ldap_access( givenName => '*'); #default policy
    _refresh_users($data);
    is($data->{student}->{user}->allowed_access( $base->id ), 0);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 1)
            or die Dumper($data->{teacher}->{user}->{_allowed});
    is($data->{other}->{user}->allowed_access( $base->id ), 0);

    _remove_bases($base);
    _remove_users($data);
}

sub test_access_by_attribute_move($vm, $do_clones=0) {
    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $data = _create_users_2();
    is($data->{student}->{user}->allowed_access( $base->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
    is($data->{other}->{user}->allowed_access( $base->id ), 1);

    _do_clones($data, $base, $do_clones);

    $base->allow_ldap_access( givenName => $data->{teacher}->{user}->{name});
    $base->deny_ldap_access( givenName => '*'); #default policy

    my @list_ldap_attribute = $base->list_ldap_access();

    $base->move_ldap_access($list_ldap_attribute[1]->{id}, -1);

    my @list_ldap_attribute2 = $base->list_ldap_access();

    is($list_ldap_attribute[0]->{id}, $list_ldap_attribute2[1]->{id}) or exit;

    _refresh_users($data);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 0)
            or die Dumper($data->{teacher}->{user}->{_allowed});
    is($data->{other}->{user}->allowed_access( $base->id ), 0);

    my $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 0);

    $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
    is(scalar (@$list_bases), 0);

    # other has no external_auth, access denied
    $list_bases = rvd_front->list_machines_user($data->{other}->{user});
    is(scalar (@$list_bases), 0);

    $list_bases = rvd_front->list_machines_user(user_admin);
    is(scalar (@$list_bases), 1);

    _remove_bases($base);
    _remove_users($data);
}

sub test_access_by_attribute_move_removed($vm) {
    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my $data = _create_users();

    $base->allow_ldap_access( givenName => $data->{teacher}->{user}->{name});
    $base->allow_ldap_access( givenName => $data->{student}->{user}->{name});
    $base->deny_ldap_access( givenName => '*'); #default policy

    my @list_ldap_attribute = $base->list_ldap_access();

    # remove the access #1
    $base->delete_ldap_access($list_ldap_attribute[1]->{id});
    $base->move_ldap_access($list_ldap_attribute[2]->{id}, -1);

    my @list_ldap_attribute2 = $base->list_ldap_access();

    is($list_ldap_attribute[2]->{id}, $list_ldap_attribute2[0]->{id}) or exit;

    _remove_bases($base);
    _remove_users($data);
}


sub test_2_checks($vm, $multiple=0) {
    my $data = _create_users_2($multiple);

    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    $base->allow_ldap_access( givenName => $data->{student}->{name});
    $base->deny_ldap_access( givenName => $data->{teacher}->{name});

    my $sth = connector->dbh->prepare(
        "SELECT id,n_order from access_ldap_attribute "
        ." WHERE id_domain=?"
        ." ORDER BY n_order"
    );
    $sth->execute($base->id);
    my $n_order_old;
    while (my ($id, $n_order) = $sth->fetchrow ) {
        isnt($n_order,$n_order_old,"Expecting new order for access id: $id");
        $n_order_old = $n_order;
    }

    _refresh_users($data);

    _remove_bases($base);
    _remove_users($data);
}

sub _search($ldap, $field, $value) {
    my $search = $ldap->search( filter => "$field=$value" );
    is($search->code,0) or die $search->error;
    my @entries = $search->entries();
    is(scalar(@entries),1, ) or die Dumper(\@entries);
    my ($first) = @entries;
    my @found_values = $first->get_value($field);
    ok( grep /^$value$/ , @found_values)
        or die Dumper( \@found_values, $first->dn,$first);

    return $first;
}

sub _search_user($field, $value) {
    confess if !defined $value;
    my $ldap = _init_ldap();
    my $search = $ldap->search( filter => "$field=$value" );
    is($search->code,0) or die $search->error;
    return $search->entries();
}


sub _init_ldap {
    Ravada::Auth::LDAP::init();
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    return $ldap;
}

sub test_access_by_attribute_multiple_values($vm, $do_clones=0) {

    my $data = _create_users_2();
    my ($given_name1) = $data->{teacher}->{name} =~ m{(.*)\.};
    my $ldap = _init_ldap();
    my $first = _search($ldap, givenName => $given_name1);

    my $given_name2 = new_domain_name();
    my $mesg = $ldap->modify($first->dn,
        add => { givenName => $given_name2 }
    );
    my $first2 = _search($ldap, givenName => $given_name2);

    my @bases;

    for my $given_name ( $given_name1, $given_name2 ) {
        my $base = create_domain($vm->type);
        push @bases,($base);
        $base->prepare_base(user_admin);
        $base->is_public(1);

        $base->allow_ldap_access( givenName => $given_name);
        $base->deny_ldap_access( givenName => '*'); #default policy
        _refresh_users($data);
        is($data->{student}->{user}->allowed_access( $base->id ), 0);
        is($data->{teacher}->{user}->allowed_access( $base->id ), 1, "Expecting allowed with given_name $given_name");
        is($data->{other}->{user}->allowed_access( $base->id ), 0);
    }

    _remove_bases(@bases);
    _remove_users($data);

}

sub test_access_by_attribute($vm, $do_clones=0, $with_multiple=0) {

    diag("test by attribute with_clones=$do_clones, with_multiple=$with_multiple");

    my $data = _create_users_2($with_multiple);
    my @given_name = $data->{student}->{user}->ldap_entry->get_value('givenName');
    my @entries = _search_user(
            'givenName' => $given_name[0]
    );
    is(scalar(@entries),1,"Expecting one givenName $given_name[0]") or die Dumper([map {$_->dn } @entries]);

    @entries = Ravada::Auth::LDAP::search_user(
            field => 'givenName'
            ,name => " ".$given_name[0]
            ,typesonly => 1
    );
    is(scalar(@entries),0) or exit;

    my $base = create_domain($vm->type);
    $base->prepare_base(user_admin);
    $base->is_public(1);

    my ($clone_student, $clone_teacher) = _do_clones($data, $base, $do_clones);

    my $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 1);

    #################################################################
    #
    #  all should be allowed now
    is($data->{student}->{user}->allowed_access( $base->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
    is($data->{other}->{user}->allowed_access( $base->id ), 1);
    is(user_admin->allowed_access( $base->id ), 1);

    for my $given_name ($data->{student}->{user}->ldap_entry->get_value('givenName')) {
        $base->allow_ldap_access( givenName => $given_name );
        _refresh_users($data);

        #################################################################
        #
        #  only students and admin should be allowed
        is($data->{student}->{user}->allowed_access( $base->id ), 1) or exit;
        is($data->{teacher}->{user}->allowed_access( $base->id ), 0
            , Dumper($data->{teacher}->{user}->{_allowed})) or exit;
        is($data->{other}->{user}->allowed_access( $base->id ), 0);
        is(user_admin->allowed_access( $base->id ), 1);

        $list_bases = rvd_front->list_machines_user($data->{student}->{user});
        is(scalar (@$list_bases), 1);

        $clone_teacher->remove(user_admin) if $clone_teacher;

        $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
        is(scalar (@$list_bases), 0) or confess Dumper($list_bases,$base->id);

        # other has no external_auth, access denied
        $list_bases = rvd_front->list_machines_user($data->{other}->{user});
        is(scalar (@$list_bases), 0);

        $list_bases = rvd_front->list_machines_user(user_admin);
        is(scalar (@$list_bases), 1);

        $base->delete_ldap_access($base->list_ldap_access);
    }

    _remove_bases($base);
    _remove_users($data);
}

sub _create_bases($vm, $n=1) {

    my @bases;
    for (1 .. $n ) {
        my $base = create_domain($vm->type);
        $base->prepare_base(user_admin);
        $base->is_public(1);

        push @bases,($base);
    }

    return @bases;

}

sub _remove_bases(@bases) {
    for my $base (@bases) {
        for my $clone_data ($base->clones) {
            my $clone = Ravada::Domain->open($clone_data->{id});
            $clone->remove(user_admin);
        }
        my $id_domain = $base->id;
        $base->remove(user_admin);

        my $sth = connector->dbh->prepare(
            "SELECT * from access_ldap_attribute "
            ." WHERE id_domain=?"
        );
        $sth->execute($id_domain);

        my $row = $sth->fetchrow_hashref;
        ok(!$row,"Expecting removed access_ldap_attribute for remove domain : ".$id_domain
        ." ".Dumper($row));
        $sth->finish;
    }
}

sub _remove_users($data) {
    for my $key (keys %$data) {
        my $entry = $data->{$key};

        my $user = $entry->{user};
        my $name = $entry->{name};

        if ( Ravada::Auth::LDAP::search_user($name) ) {
            Ravada::Auth::LDAP::remove_user($name)  
        }
        $user->remove();
    }
}

sub test_access_by_attribute_2bases($vm, $do_clones=0, $with_multiple=0) {

    my $data = _create_users_2($with_multiple);

    my @bases  = _create_bases($vm,2);

    my($clone_student, $clone_teacher) = _do_clones($data, $bases[0], $do_clones);
    _do_clones($data, $bases[1], $do_clones);

    my $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 2);

    #################################################################
    #
    #  all should be allowed now
    for my $base ( @bases ) {
        is($data->{student}->{user}->allowed_access( $base->id ), 1);
        is($data->{teacher}->{user}->allowed_access( $base->id ), 1);
        is(user_admin->allowed_access( $base->id ), 1);
    }

    my (@given_name) = $data->{student}->{user}->ldap_entry->get_value('givenName');
    my ($given_name) = @given_name;

    $bases[0]->allow_ldap_access( givenName => $given_name);

    _refresh_users($data);
    #################################################################
    #
    #  only students and admin should be allowed
    is($data->{student}->{user}->allowed_access( $bases[0]->id ), 1);
    is($data->{teacher}->{user}->allowed_access( $bases[0]->id ), 0) or exit;
    is(user_admin->allowed_access( $bases[0]->id ), 1);

    $list_bases = rvd_front->list_machines_user($data->{student}->{user});
    is(scalar (@$list_bases), 2);

    if ($do_clones) {
        $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
        is(scalar (@$list_bases), 2) or die Dumper($do_clones,$list_bases);

        $clone_teacher->remove(user_admin) if $clone_teacher;
    }
    $list_bases = rvd_front->list_machines_user($data->{teacher}->{user});
    is(scalar (@$list_bases), 1) or die Dumper($list_bases, $bases[0]->id);

    $list_bases = rvd_front->list_machines_user($data->{other}->{user});
    is(scalar (@$list_bases), 1);

    $list_bases = rvd_front->list_machines_user(user_admin);
    is(scalar (@$list_bases), 2);

    _remove_bases(@bases);
    _remove_users($data);
}

################################################################################

init();
clean();

for my $vm_name ( vm_names() ) {
    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {
        my $fly_config;

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        } else {
            $fly_config = init_ldap_config();
            init($fly_config);
        }
        my $ldap;

        $Ravada::Auth::LDAP_OK = undef;
        eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() } if $vm;

        if ($@ =~ /Bad credentials/) {
            $msg = "$@\nFix admin credentials in t/etc/ravada_ldap.conf";
        } elsif ($vm) {
            $msg = "Skipped LDAP tests ".($@ or '');
        }

        skip($msg,10)   if !$ldap;
        diag("Testing LDAP access for $vm_name");

        test_access_by_attribute_multiple_values($vm);

        test_external_auth();

        for my $with_multiple ( 0,1) {

        test_2_checks($vm, $with_multiple);

        test_access_by_attribute($vm,0,$with_multiple);
        test_access_by_attribute($vm,1,$with_multiple); # with clones
        test_access_by_attribute_2bases($vm,0, $with_multiple);
        test_access_by_attribute_2bases($vm,1, $with_multiple); # with clones

        test_access_by_attribute_deny($vm,0, $with_multiple);
        test_access_by_attribute_deny($vm,1, $with_multiple); # with clones

        }

        test_access_by_attribute_several2($vm);
        test_access_by_attribute_several($vm);

        test_access_by_attribute_move($vm);
        test_access_by_attribute_move_removed($vm);


        unlink $fly_config;
    }

}

end();
done_testing();
