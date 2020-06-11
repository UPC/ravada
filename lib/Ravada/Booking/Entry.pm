package Ravada::Booking::Entry;

use Carp qw(carp croak);
use Data::Dumper;
use Ravada::Utils;

use Moose;

no warnings "experimental::signatures";
use feature qw(signatures);

our $CONNECTOR = \$Ravada::CONNECTOR;

sub BUILD($self, $args) {
    return $self->_open($args->{id}) if $args->{id};

    my $ldap_groups = delete $args->{ldap_groups};
    my $users = delete $args->{users};

    $self->_insert_db($args);
    $self->_add_group($ldap_groups);
    $self->_add_users($users);

    return $self;
}

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

sub _dbh($self) {
    _init_connector();
    return $$CONNECTOR->dbh;
}

sub _insert_db($self, $field) {

    my $query = "INSERT INTO booking_entries "
            ."(" . join(",",sort keys %$field )." )"
            ." VALUES (". join(",", map { '?' } keys %$field )." ) "
    ;
    my $sth = $self->_dbh->prepare($query);
    eval { $sth->execute( map { $field->{$_} } sort keys %$field ) };
    if ($@) {
        warn "$query\n".Dumper($field);
        confess $@;
    }
    $sth->finish;

    my $id= Ravada::Utils::last_insert_id($self->_dbh);
    return $self->_open($id);

}

sub _add_group($self, $ldap_groups) {
    my $id = $self->_data('id');
    $ldap_groups = [ $ldap_groups ] if !ref($ldap_groups);

    my $sth = $self->_dbh->prepare("INSERT INTO booking_entry_ldap_groups "
            ."(  id_booking_entry, ldap_group )"
            ."values( ?,? ) "
    );
    for my $current_group(@$ldap_groups) {
        $sth->execute($id, $current_group);
    }
}

sub _add_users ($self, $users) {
    return if !defined $users;
    my $id = $self->_data('id');
    $users = [ $users] if !ref($users);

    my $sth = $self->_dbh->prepare("INSERT INTO booking_entry_users"
            ."(  id_booking_entry, id_user)"
            ."values( ?,? ) "
    );
    for my $current_user (@$users) {
        $current_user = $self->_search_user_id($current_user);
        $sth->execute($id, $current_user);
    }
}

sub _search_user_id($self, $user) {
    confess if !defined $user;
    return $user if $user =~ /^\d+$/;

    my $sth = $self->_dbh->prepare("SELECT id FROM users WHERE name=? ");
    $sth->execute($user);
    my ($id) = $sth->fetchrow;
    return $id if $id;

    my $user_ldap = Ravada::Auth::LDAP::search_user(name => $user);
    confess"Error: user '$user' not in database nor LDAP" if !$user_ldap;

    my $user_new = Ravada::Auth::SQL::add_user(
        name => $user
        ,is_admin => 0
        ,is_external => 1
        ,external_auth => 'LDAP'
    );
    return $user_new->id;
}

sub _open($self, $id) {
    my $sth = $self->_dbh->prepare("SELECT * FROM booking_entries WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    return if !keys %$row;
    $self->{_data} = $row;

    return $self;
}

sub _data($self, $field) {
    confess "Error: field '$field' doesn't exist in ".Dumper($self->{_data}, $self)
        if !exists $self->{_data}->{$field};

    return $self->{_data}->{$field};

}

sub id($self) { return $self->_data('id') }

sub groups($self) {
    my $sth = $self->_dbh->prepare("SELECT ldap_group FROM booking_entry_ldap_groups"
        ." WHERE id_booking_entry=?");
    $sth->execute($self->id);
    my @groups;
    while ( my ($group) = $sth->fetchrow ) {
        push @groups,($group);
    }
    return @groups;
}

sub users ($self) {
    my $sth = $self->_dbh->prepare("SELECT id_user,u.name "
        ." FROM booking_entry_users b,users u"
        ." WHERE id_booking_entry=?"
        ." AND b.id_user=u.id "
    );
    $sth->execute($self->id);
    my @users;
    while ( my ($id_user, $user_name) = $sth->fetchrow ) {
        push @users,($user_name);
    }
    return @users;
}

sub user_allowed($entry, $user_name) {
    for my $allowed_user_name ( $entry->users ) {
        return 1 if $user_name eq $allowed_user_name;
    }
    for my $group_name ($entry->groups) {
        my $group = Ravada::Auth::LDAP->_search_posix_group($group_name);
        my @member = $group->get_value('memberUid');
        my ($found) = grep /^$user_name$/,@member;
        return 1 if $found;
    }
    return 0;
}

1;
