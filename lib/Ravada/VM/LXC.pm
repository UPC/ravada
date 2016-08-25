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

use Ravada::Domain::LXC;

with 'Ravada::VM';

our $CMD_LXC_LS;
our $CONNECTOR = \$Ravada::CONNECTOR;

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
    croak "argument id_template or id_base required" 
        if !$args{id_template} && !$args{id_base};

    my $domain;
    if ($args{id_template}) {
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
    
    croak "argument id_template required" 
        if !$args{id_template};

    die "Domain $args{name} already exists"
        if $self->search_domain($args{name});
    
    my $template = $self->_search_template($args{id_template});
    my $name = $args{name};

    my @cmd = ('lxc-create','-n',$name,'-t', $template->{name}
            ,'-B','overlayfs');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    die join(" ",@cmd)."\n".$err   if $?;

    my $domain = Ravada::Domain::LXC->new(domain => $args{name});
    $domain->_insert_db(name => $args{name});
    return $domain;
}

sub _search_template {
    my $self = shift;
    my $id_template = shift or confess "Missing id_template";

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM lxc_templates WHERE id = ?");
    $sth->execute($id_template);
    my $row = $sth->fetchrow_hashref;
    die "Missing lx_template id=$id_template" if !keys %$row;
    lock_hash(%$row);
    return $row;

}

sub _domain_create_from_base {
    my $self = shift;
    my %arg = @_;
    my $newname = $arg{name} or confess "Missing name";
    my $id_base = $arg{id_base} or confess "Missing id_base";

    my $base = $self->search_domain_by_id($id_base);

    my @cmd = ('lxc-clone','-s'
        ,'-o',$base->name,"-n",$newname,"-B","overlay");
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    die join(" ",@cmd)."\n".$err   if $?;
    #TODO create $newname in ddbb
    my $newdomain = Ravada::Domain::LXC->new(domain => $newname);
    $newdomain->_insert_db(name => $newname);
    return $newdomain;
}

sub search_domain {
    my $self = shift;
    my $name = shift or confess "Missing domain name";
    my $import = shift;

    for my $domain_lxc ( $self->_list_domains ) {
        next if $domain_lxc ne $name;
        my $domain ;
        my $id;
        eval{ $domain = Ravada::Domain::LXC->new(
                          domain => $domain_lxc
                         );
              $id = $domain->id()   if $domain && !$import;
        };

        return $domain if $domain && $domain->name eq $name;
    }
    return;
}

sub search_domain_by_id {
    my $self = shift;
    my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains "
        ." WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return if !$name;

    return $self->search_domain($name);
} 

 sub _list_domains {
    my $self = shift;
    my @list = ('lxc-ls','-1');
    my ($in,$out,$err);
    run3(\@list,\$in,\$out,\$err);
   
    #warn $out  if !$out;
    warn $err   if $err;   
    my @domains;
    for (split /\n/,$out) {
        s/^\s+//;
        s/\s+$//;
        push @domains,($_);
    }
    return @domains;
 }


sub list_domains {
    my $self = shift;

    my @list;
    for my $name ($self->_list_domains()) {
        my $domain ;
        my $id;
        eval{ $domain = Ravada::Domain::LXC->new(
                          domain => $name                          
                         );
              $id = $domain->id()   if $domain;
          };
        push @list,($domain) if $domain && $id;
    }
    return @list;
}

sub create_volume {
}

1;
