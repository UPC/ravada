package Ravada::DB;

use warnings;
use strict;

use base 'Class::Singleton';
use DBIx::Connector;

sub _new_instance {
    my $class = shift;

    my %args = @_;

    my $self  = bless { }, $class;

    my $connector = $args{connector};
    if ($connector) {
        $self->{connector} = $connector;
        return $self;
    }
    my $config = $args{config};

    my $driver= ($config->{db}->{driver} or 'mysql');;
    my $db_user = ($config->{db}->{user} or getpwnam($>));;
    my $db_pass = ($config->{db}->{password} or undef);
    my $db = ( $config->{db}->{db} or 'ravada' );
    $self->{connector} = DBIx::Connector->new("DBI:$driver:$db"
                        ,$db_user,$db_pass,{RaiseError => 1
                        , PrintError=> 0 });

    return $self;
}

sub dbh {
    my $self = shift;
    return $self->{connector}->dbh;
}

1;
