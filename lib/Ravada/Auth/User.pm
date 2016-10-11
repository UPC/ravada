package Ravada::Auth::User;

use warnings;
use strict;

use Carp qw(confess croak);
use Data::Dumper;
use Moose::Role;

requires 'add_user';
requires 'is_admin';

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
    _init_connector();
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

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, subject, date_read, date_send FROM messages WHERE id_user=?"
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

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, subject FROM messages "
        ." WHERE id_user=? AND date_read IS NULL"
        ." LIMIT ?,?");
    $sth->execute($self->id, $skip, $count);
    
    my @rows;

    while (my $row = $sth->fetchrow_hashref ) {
        push @rows,($row);
    }
    $sth->finish;
    return @rows;

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
        ." SET date_read=now() "
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
        "UPDATE messages set date_read=now()"
    );
    $sth->execute();
    $sth->finish;
}

1;
