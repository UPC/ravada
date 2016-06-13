package Ravada::VM::LXC;

use warnings;
use strict;

use Carp qw(carp croak);
use Data::Dumper;
use Fcntl qw(:flock O_WRONLY O_EXCL O_CREAT);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use Moose;
use Sys::Hostname;
use XML::LibXML;

#use Ravada::Domain::LXC;

with 'Ravada::VM';

our $CMD_LXC_LS;

sub BUILD {
    my $self = shift;

    $self->connect()                if !defined $CMD_LXC_LS;
    die "No LXC backend found\n"    if !$CMD_LXC_LS;
}

sub connect {

#There are two user-space implementations of containers, each exploiting the same kernel
#features. Libvirt allows the use of containers through the LXC driver by connecting 
#to 'lxc:///'.
#We use the other implementation, called simply 'LXC', is not compatible with libvirt,
#but is more flexible with more userspace tools. 
#Use of libvirt-lxc is not generally recommended due to a lack of Apparmor protection 
#for libvirt-lxc containers.
#
#Reference: https://help.ubuntu.com/lts/serverguide/lxc.html#lxc-startup
#
    return $CMD_LXC_LS if defined $CMD_LXC_LS;

    $CMD_LXC_LS = `which lxc-ls`;
    chomp $CMD_LXC_LS;

    return $CMD_LXC_LS;
}

sub create_domain {
 my $self = shift;
    my %args = @_;

    $args{active} = 1 if !defined $args{active};
    
    croak "argument name required"       if !$args{name};
    croak "argument id_iso or id_base required" 
        if !$args{id_iso} && !$args{id_base};

    my $domain;
    if ($args{id_iso}) {
        $domain = $self->_domain_create_from_template(@_);
    } elsif($args{id_base}) {
        $domain = $self->_domain_create_from_base(@_);
    } else {
        confess "TODO";
    }

    return $domain;
}

sub _domain_create_from_template {
    my $self = shift;
    my %args = @_;
    
    croak "argument id_iso required" 
        if !$args{id_iso};

    die "Domain $args{name} already exists"
        if $self->search_domain($args{name});
    
    my $template = "ubuntu";
    my $name = $args{name};

    my @cmd = ('lxc-create','-n',$name,'-t', $template);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    die $err   if $?;

    my $domain = Ravada::Domain::LXC->new(domain => $args{name});
    $domain->_insert_db(name => $args{name});
    return $domain;
}

sub _domain_create_from_base {

}

sub search_domain {
    my $self = shift;
    my $name = shift;
    my @cmd = ('lxc-ls','-f');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if !$out;
    warn $err   if $err;
    my $domain;

    for ( split /\n/,$out ) {
        my ($out_name) = /(\w+) /;
        next if $out_name ne $name;
        eval { 
            $domain = $name;
        };
    return $domain if $domain;
    }
    return $name;
}



sub search_domain_by_id {
   }

sub list_domains {
    # my $self = shift;

 #    my @list;
 #    for my $name ($self->vm->list_all_domains()) {
 #        my $domain ;
 #        my $id;
 #        eval { $domain = Ravada::Domain::LXC->new(
 #                          domain => $name
 #                        ,storage => $self->storage_pool
 #                    );
 #             $id = $domain->id();
 #        };
 #        push @list,($domain) if $domain && $id;
 #    }
 #    return @list;
}

sub create_volume {
}

1;
