package Ravada::Auth::User;

use warnings;
use strict;

=head1 NAME

Ravada::Auth::User - User management and tools library for Ravada

=cut

use Carp qw(confess croak);
use Data::Dumper;
use Mojo::JSON qw(decode_json);
use Moose::Role;

no warnings "experimental::signatures";
use feature qw(signatures);

requires 'add_user';
requires 'is_admin';
requires 'is_external';

has 'name' => (
           is => 'ro'
         ,isa => 'Str'
    ,required =>1
);

has 'password' => (
           is => 'ro'
         ,isa => 'Str'
    ,required => 0
);
#
#####################################################

our $CONNECTOR;

sub _init_connector {
    $CONNECTOR= \$Ravada::CONNECTOR;
    $CONNECTOR= \$Ravada::Front::CONNECTOR   if !$$CONNECTOR;
}

_init_connector();

=head2 BUILD

Internal OO builder

=cut

sub BUILD {
    my $self = shift;
    _init_connector();
    $self->_load_allowed();

}

#####################################################

=head2 messages

List of messages for this user


    my @messages = $user->messages();


=cut

sub messages {
    my $self = shift;

    _init_connector() if !$$CONNECTOR;

    my $skip  = ( shift or 0);
    my $count = shift;
    $count = 50 if !defined $count;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, subject, date_read, date_send, message FROM messages WHERE id_user=?"
        ." ORDER BY date_send DESC"
        ." LIMIT ?,?");
    $sth->execute($self->id, $skip, $count);

    my @rows;

    while (my $row = $sth->fetchrow_hashref ) {
        push @rows,($row);
    }
    $sth->finish;
    return @rows;
}

=head2 unread_messages

List of unread messages for this user

    my @unread = $user->unread_messages();

=cut

sub unread_messages {
    my $self = shift;

    _init_connector() if !$$CONNECTOR;

    my $skip  = ( shift or 0);
    my $count = shift;
    $count = 50 if !defined $count;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, subject, message FROM messages "
        ." WHERE id_user=? AND date_read IS NULL"
        ."    ORDER BY date_send DESC "
        ." LIMIT ?,?");
    $sth->execute($self->id, $skip, $count);

    my @rows;

    while (my $row = $sth->fetchrow_hashref ) {
        push @rows,($row);
        $self->mark_message_shown($row->{id})   if $row->{id};
    }
    $sth->finish;

    return @rows;

}

=head2 unshown_messages

List of unshown messages for this user

    my @unshown = $user->unshown_messages();

=cut

sub unshown_messages {
    my $self = shift;

    _init_connector() if !$$CONNECTOR;

    my $skip  = ( shift or 0);
    my $count = shift;
    $count = 50 if !defined $count;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, subject, message FROM messages "
        ." WHERE id_user=? AND date_shown IS NULL"
        ."    ORDER BY date_send DESC "
        ." LIMIT ?,?");
    $sth->execute($self->id, $skip, $count);

    my @rows;

    while (my $row = $sth->fetchrow_hashref ) {
        push @rows,($row);
        $self->mark_message_shown($row->{id})   if $row->{id};
    }
    $sth->finish;

    return @rows;

}

=head2 send_message

Send a message to this user

    $user->send_message($subject, $message)

=cut

sub send_message($self, $subject, $message='') {
    _init_connector() if !$$CONNECTOR;

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO messages (id_user, subject, message) "
        ." VALUES(?, ? , ? )");

    $subject = substr($subject,0,120) if length($subject)>120;
    $sth->execute($self->id, $subject, $message);
}


=head2 show_message

Returns a message by id

    my $message = $user->show_message($id);

The data is returned as h hash ref.

=cut


sub show_message {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM messages "
        ." WHERE id_user=? AND id=?");

    $sth->execute($self->id, $id);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $self->mark_message_read($id)   if $row->{id};

    return $row;

}

=head2 mark_message_read

Marks a message as read

    $user->mark_message_read($id);

Returns nothing

=cut


sub mark_message_read {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("UPDATE messages "
        ." SET date_read=? "
        ." WHERE id_user=? AND id=?");

    $sth->execute(_now(), $self->id, $id);
    $sth->finish;

}

=head2 mark_message_shown

Marks a message as shown

    $user->mark_message_shown($id);

Returns nothing

=cut


sub mark_message_shown {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("UPDATE messages "
        ." SET date_shown=? "
        ." WHERE id_user=? AND id=?");

    $sth->execute(_now(), $self->id, $id);
    $sth->finish;

}


=head2 mark_message_unread

Marks a message as unread

    $user->mark_message_unread($id);

Returns nothing

=cut

sub mark_message_unread {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("UPDATE messages "
        ." SET date_read=null "
        ." WHERE id_user=? AND id=?");

    $sth->execute($self->id, $id);
    $sth->finish;

}

=head2 mark_all_messages_read

Marks all message as read

    $user->mark_all_messages_read();

Returns nothing

=cut


sub mark_all_messages_read {
    my $self = shift;

    _init_connector() if !$$CONNECTOR;

    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE messages set date_read=?, date_shown=?"
    );
    $sth->execute(_now(), _now());
    $sth->finish;
}

sub _now {
     my @now = localtime(time);
    $now[5]+=1900;
    $now[4]++;
    for ( 0 .. 4 ) {
        $now[$_] = "0".$now[$_] if length($now[$_])<2;
    }

    return "$now[5]-$now[4]-$now[3] $now[2]:$now[1]:$now[0].0";
}

=head2 allowed_access

Return true if the user has access to clone a virtual machine

=cut

sub allowed_access($self,$id_domain) {
    return 1 if $self->is_admin;

    $self->_load_allowed();

    # this domain has not access checks defined
    return 1 if ! exists $self->{_allowed}->{$id_domain};

    # return true if this user is allowed
    return 1 if $self->{_allowed}->{$id_domain};

    return 0;
}

sub _list_domains_access($self) {

    my @domains;
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT distinct(id_domain) FROM access_ldap_attribute"
    );
    $sth->execute();
    while (my ($id_domain) = $sth->fetchrow) {
        push @domains, ($id_domain);
    }
    $sth->finish;

    return @domains;
}

sub _load_allowed {
    my $self = shift;
    my $refresh = shift;

    return if !$refresh && $self->{_load_allowed}++;

    if (ref($self) !~ /SQL$/) {
        $self = Ravada::Auth::SQL->new(name => $self->name);
    }

    my $ldap_entry;
    $ldap_entry = $self->ldap_entry if $self->external_auth && $self->external_auth eq 'ldap';

    my @domains = $self->_list_domains_access();

    for my $id_domain ( @domains ) {
        my $sth = $$CONNECTOR->dbh->prepare(
            "SELECT attribute, value, allowed, last "
            ." FROM access_ldap_attribute"
            ." WHERE id_domain=?"
            ." ORDER BY n_order "
        );
        $sth->execute($id_domain);

        my ($n_allowed, $n_denied) = ( 0,0 );
        while ( my ($attribute, $value, $allowed, $last) = $sth->fetchrow) {

            $n_allowed++ if $allowed;
            $n_denied++ if !$allowed;

            if ( $value eq '*' ) {
                $self->{_allowed}->{$id_domain} = $allowed
                    if !exists $self->{_allowed}->{$id_domain};
                last;
            } elsif ( $ldap_entry && defined $ldap_entry->get_value($attribute)
                    && $ldap_entry->get_value($attribute) eq $value ) {

                $self->{_allowed}->{$id_domain} = $allowed;

                last if !$allowed || $last;
            }
        }
        $sth->finish;
        next if defined $self->{_allowed}->{$id_domain};
        if ($n_allowed && $n_denied) {
            warn "WARNING: No default access attribute for domain $id_domain";
            next;
        }
        if ($n_allowed && !$n_denied) {
            $self->{_allowed}->{$id_domain} = 0;
        } else {
            $self->{_allowed}->{$id_domain} = 1;
        }
    }
}

=head2 list_requests

List the requests for this user. It returns requests from the last hour
by default.

Arguments: optionally pass the date to start search for requests.


=cut

sub list_requests($self, $date_req=Ravada::Utils::date_now(3600)) {
    my $sth = $$CONNECTOR->dbh
    ->prepare("SELECT id,args FROM requests WHERE date_req > ?"
    ." ORDER BY date_req DESC");

    my ($id, $args_json);

    $sth->execute($date_req);
    $sth->bind_columns(\($id, $args_json));

    my @req;
    while ( $sth->fetch ) {
        my $args = decode_json($args_json);
        next if !length $args;
        my $uid = ($args->{uid} or $args->{id_owner}) or next;
        next if $uid != $self->id;

        my $req = Ravada::Request->open($id);
        push @req, ( $req );
    }
    return @req;
}

1;
