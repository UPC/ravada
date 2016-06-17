package Ravada::Domain::LXC;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

with 'Ravada::Domain';

#my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################

sub name {
 #   my $self = shift;
 #   $self->_select_domain_db or return;

#    return 1 if $self->_data('name');
}

sub remove {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-destroy','-n',$name,'-f');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    #TODO look $?
    #Ravada::VM->_domain_remove_db($name);
    #my $sth = $test->connector->dbh->prepare("DELETE FROM domains WHERE name=?");
    #$sth->execute($name);

    return;
}

sub create_files{
    # my $self = shift;
    # my $path = search_path;
    # open my $out,'>' , "$path/$filename" or die $!;
    # print $out "hola";
    # close $out;

}

sub search_path{
    my $self = shift;

}

#Introduce limits when create a new container 
sub limits{ 
    my $self = shift;
    my $name = shift; 
    my $memory = shift;
    my $swap = shift;
    my $cpushares = shift;
    my $ioweight = shift;

    my $mountpoint = "/var/lib/lxc/$name";
    open my $config, '>>' , "$mountpoint/config" or die $!;
    print $config lxc_config();
    close $config;
}

#TODO: repair variables inside sub
sub lxc_config{
    return <<EOF;

# RAM, swap, cpushare and ioweight Limits 
lxc.cgroup.memory.limit_in_bytes = memory
lxc.cgroup.memory.memsw.limit_in_bytes = swap
lxc.cgroup.cpu.shares = cpushares
lxc.cgroup.blkio.weight = ioweight
EOF
}

#TODO: when port in db
sub port {
    my $self = shift;
    return $self->_data('port');
}

sub display {
    my $self = shift;

}

sub is_active {
    my $self = shift;

}

sub start {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-start','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;

}

sub shutdown {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-stop','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;

}


=head2 pause

Pauses the domain

=cut

sub pause {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-freeze','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;
}



1;
