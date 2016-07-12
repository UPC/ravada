package Ravada::Auth::SQL;

use warnings;
use strict;

use Ravada;
use Digest::SHA qw(sha1_hex);
use Hash::Util qw(lock_hash);
use Moose;

with 'Ravada::Auth::User';


our $CON = \$Ravada::CONNECTOR;

sub BUILD {
    my $self = shift;
    die "ERROR: Login failed ".$self->name
        if !$self->login();#$self->name, $self->password);
    return $self;
}

sub add_user {
    my ($login,$password, $is_admin ) = @_;
    my $sth = $$CON->dbh->prepare(
            "INSERT INTO users (name,password,is_admin) VALUES(?,?,?)");

    $sth->execute($login,sha1_hex($password),$is_admin);
    $sth->finish;
}

sub login {
    my $self = shift;

    my ($name, $password);

    if (ref $self) {
        $name = $self->name;
        $password = $self->password;
        $self->{_data} = {};
    } else { # old login API
        $name = $self;
        $password = shift;
    }


    my $sth = $$CON->dbh->prepare(
       "SELECT * FROM users WHERE name=? AND password=?");
    $sth->execute($name , sha1_hex($password));
    my ($found) = $sth->fetchrow_hashref;
    $sth->finish;

    if ($found) {
        lock_hash %$found;
        $self->{_data} = $found if ref $self && $found;
    }

    return 1 if $found;

    return;
}

sub is_admin {
    my $self = shift;
    return $self->{_data}->{is_admin};
}
1;

