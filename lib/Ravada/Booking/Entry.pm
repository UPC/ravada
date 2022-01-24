package Ravada::Booking::Entry;

use warnings;
use strict;

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
    my $bases = delete $args->{bases};

    _fix_time($args,'time_start');
    _fix_time($args,'time_end');

    $self->_insert_db($args);
    $self->_add_ldap_groups($ldap_groups);
    $self->_add_users($users);
    $self->_add_bases($bases);

    return $self;
}

sub _fix_time($args,$field) {
    my @items = map { $a=$_; $a ="0".$a if length($a)<2 ; $a } split /:/,$args->{$field};
    my $fixed = join(":",@items);
    $args->{$field} = $fixed;
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

sub _change_ldap_groups($self, $ldap_groups) {
    $self->_add_ldap_groups($ldap_groups);
    $self->_purge_table('booking_entry_ldap_groups','ldap_group',$ldap_groups,[ $self->ldap_groups ]);
}

sub _add_ldap_groups($self, $ldap_groups) {
    return if !$ldap_groups;
    my $id = $self->_data('id');
    my %already_added = map { $_ => 1 } $self->ldap_groups();
    $ldap_groups = [ $ldap_groups ] if !ref($ldap_groups);

    my $sth = $self->_dbh->prepare("INSERT INTO booking_entry_ldap_groups "
            ."(  id_booking_entry, ldap_group )"
            ."values( ?,? ) "
    );
    for my $current_group (@$ldap_groups) {
        next if $already_added{$current_group}++;
        $sth->execute($id, $current_group);
    }

}

# removes item not in list
sub _purge_table($self, $table, $field, $entries, $old_entries, $sub_search_id = undef ) {
    my $sth = $self->_dbh->prepare("DELETE FROM $table"
        ." WHERE $field=? "
        ." AND id_booking_entry=? "
    );
    my %keep;
    for my $current ( @$entries ) {

        my $current_id = $current;
        $current_id = $sub_search_id->($self, $current)
        if $sub_search_id;

        $keep{$current_id}++;
    }
    for my $current( @$old_entries ) {

        my $current_id = $current;
        $current_id = $sub_search_id->($self, $current)
        if $sub_search_id;

        next if $keep{$current_id};
        $sth->execute($current_id, $self->id);
    }
}

sub _change_users($self, $users) {
    $self->_add_users($users);
    my @current_users = $self->users;
    $self->_purge_table('booking_entry_users','id_user',$users, \@current_users
        ,\&_search_user_id);
}

sub _change_bases($self, $bases) {
    $self->_add_bases($bases);
    my @current_bases = $self->bases;
    $self->_purge_table('booking_entry_bases','id_base',$bases, \@current_bases
        ,\&_search_base_id);
}



sub _add_users ($self, $users) {
    return if !defined $users;
    my $id = $self->_data('id');
    $users = [ $users] if !ref($users);
    my %already_added = map { $_ => 1 } $self->users();

    my $sth = $self->_dbh->prepare("INSERT INTO booking_entry_users"
            ."(  id_booking_entry, id_user)"
            ."values( ?,? ) "
    );
    for my $current_user (@$users) {
        next if $already_added{$current_user};
        my $current_user_id = $self->_search_user_id($current_user);
        $sth->execute($id, $current_user_id);
    }
}

sub _add_bases ($self, $bases) {
    return if !defined $bases;
    my $id = $self->_data('id');
    $bases = [ $bases] if !ref($bases);
    my %already_added = map { $_ => 1 } $self->bases();

    my $sth = $self->_dbh->prepare("INSERT INTO booking_entry_bases"
            ."(  id_booking_entry, id_base)"
            ."values( ?,? ) "
    );
    for my $current_base (@$bases) {
        my $current_base_id = $self->_search_base_id($current_base);
        next if $already_added{$current_base};
        eval { $sth->execute($id, $current_base_id) };
        confess $@." $id, $current_base_id" if $@;
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

sub _search_base_id($self, $base) {
    return $base if $base =~ /^\d+$/;
    my $sth = $self->_dbh->prepare("SELECT id FROM domains WHERE name=? ");
    $sth->execute($base);
    my ($id) = $sth->fetchrow;
    return $id;
}

sub _open($self, $id) {
    confess if !ref($self);
    my $sth = $self->_dbh->prepare("SELECT * FROM booking_entries WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;
    confess "Error: Booking entry $id not found " if !keys %$row;
    $self->{_data} = $row;

    return $self;
}

sub _data($self, $field) {
    confess "Error: field '$field' doesn't exist in ".Dumper($self->{_data}, $self)
        if !exists $self->{_data}->{$field};

    return $self->{_data}->{$field};

}

sub change($self, %fields) {
    for my $field (keys %fields ) {

        if ($field eq 'ldap_groups') {
            $self->_change_ldap_groups($fields{$field});
            next;
        } elsif ($field eq 'users') {
            $self->_change_users($fields{$field});
            next;
        } elsif ($field eq 'bases') {
            $self->_change_bases($fields{$field});
            next;
        }
        next if !exists $self->{_data}->{$field};
        my $old_value = $self->_data($field);
        my $value = $fields{$field};
        if ($field eq 'date_booking') {
            # not change date_booking for all entries
            $value = $old_value unless $self->_data('id') == $fields{id};
            $value =~ s/(^\d{4}-\d\d-\d\d).*/$1/;
        }


        next if defined $old_value && defined $value && $value eq $old_value;
        $self->{_data}->{$field} = $value;

        my $sth = $self->_dbh->prepare("UPDATE booking_entries SET $field=? WHERE id=? ");
        $sth->execute($value,$self->id);
    }
}

sub change_next($self, %fields) {
    my $sth = $self->_dbh->prepare(
            "SELECT id FROM booking_entries "
            ." WHERE id_booking=? "
            ." AND date_booking>=? "
        );
    $sth->execute($self->_data('id_booking'), $self->_data('date_booking'));
    while (my ($id) = $sth->fetchrow) {
        Ravada::Booking::Entry->new(id => $id)->change(%fields);
    }
}


sub change_all($self, %fields) {
    my $sth = $self->_dbh->prepare(
        "SELECT id FROM booking_entries "
            ." WHERE id_booking=? "
    );
    $sth->execute($self->_data('id_booking'));
    while (my ($id) = $sth->fetchrow) {
        Ravada::Booking::Entry->new(id => $id)->change(%fields);
    }
}

sub change_next_dow($self, %fields) {
    my $date_booking = $self->_data('date_booking');
    my $dow = DateTime::Format::DateParse
    ->parse_datetime($self->_data('date_booking'))->day_of_week;
    my $sth = $self->_dbh->prepare("SELECT id,date_booking "
        ." FROM booking_entries WHERE id_booking=? "
        ." AND date_booking  >= ? ");

    $sth->execute($self->_data('id_booking'), $date_booking);
    while (my ($id, $date) = $sth->fetchrow ) {
        my $curr_dow = DateTime::Format::DateParse
        ->parse_datetime($date)->day_of_week;
        if ($dow == $curr_dow) {
            Ravada::Booking::Entry->new(id => $id)->change(%fields);
        }
    }
}


sub id($self) { return $self->_data('id') }

sub ldap_groups($self) {
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

sub bases ($self) {
    my $sth = $self->_dbh->prepare("SELECT b.id_base,d.name "
        ." FROM booking_entry_bases b,domains d"
        ." WHERE id_booking_entry=?"
        ." AND b.id_base=d.id "
    );
    $sth->execute($self->id);
    my @bases;
    while ( my ($id_base, $base_name) = $sth->fetchrow ) {
        push @bases,($base_name);
    }
    return @bases;
}

sub bases_id ($self) {
    my $sth = $self->_dbh->prepare("SELECT b.id_base,d.name "
        ." FROM booking_entry_bases b,domains d"
        ." WHERE id_booking_entry=?"
        ." AND b.id_base=d.id "
    );
    $sth->execute($self->id);
    my @bases;
    while ( my ($id_base, $base_name) = $sth->fetchrow ) {
        push @bases,($id_base);
    }
    return @bases;
}

sub _user_is_admin($self, $user_name) {

    my $user_id = $self->_search_user_id($user_name);
    my $sth =$self->_dbh->prepare("SELECT is_admin FROM users WHERE id=? ");
    $sth->execute($user_id);
    my ($is_admin) = $sth->fetchrow;
    return $is_admin;

}

sub user_allowed($entry, $user_name) {
    return 1 if $entry->_user_is_admin($user_name);

    for my $allowed_user_name ( $entry->users ) {
        return 1 if $user_name eq $allowed_user_name;
    }
    for my $group_name ($entry->ldap_groups) {
        return 1 if Ravada::Auth::LDAP::is_member($user_name, $group_name);
    }
    return 0;
}

sub _remove_users($self) {
    my $sth =$self->_dbh->prepare("DELETE FROM booking_entry_users WHERE id_booking_entry=? ");
    $sth->execute($self->id);
}
sub _remove_groups($self) {
    my $sth =$self->_dbh->prepare("DELETE FROM booking_entry_ldap_groups "
        ." WHERE id_booking_entry=? ");
    $sth->execute($self->id);
}
sub _remove_bases($self) {
    my $sth =$self->_dbh->prepare("DELETE FROM booking_entry_bases WHERE id_booking_entry=? ");
    $sth->execute($self->id);
}



sub remove($self) {
    $self->_remove_users();
    $self->_remove_groups();
    $self->_remove_bases();

    my $sth = $self->_dbh->prepare("DELETE FROM booking_entries "
        ." WHERE id=? "
    );
    $sth->execute($self->id);
}

sub remove_next($self) {
    my $date_booking = $self->_data('date_booking');
    my $sth = $self->_dbh->prepare(
        "SELECT id FROM booking_entries"
        ." WHERE id_booking=? "
        ." AND date_booking>=? "
    );
    $sth->execute($self->_data('id_booking'), $date_booking);
    while ( my ($id) = $sth->fetchrow ) {
        Ravada::Booking::Entry->new( id => $id )->remove();
    }
}

sub remove_next_dow($self) {

    my $dow = DateTime::Format::DateParse
        ->parse_datetime($self->_data('date_booking'))->day_of_week;
    my $sth = $self->_dbh->prepare("SELECT id,date_booking "
        ." FROM booking_entries WHERE id_booking=? "
        ." AND date_booking  >= ? ");

    $sth->execute($self->_data('id_booking'), $self->_data('date_booking'));
    while (my ($id, $date) = $sth->fetchrow ) {
        my $curr_dow = DateTime::Format::DateParse
        ->parse_datetime($date)->day_of_week;
        if ($dow == $curr_dow) {
            Ravada::Booking::Entry->new( id => $id )->remove();
        }
    }
}

1;
