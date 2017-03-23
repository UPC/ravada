package Ravada::Domain::LXC;

use warnings;
use strict;

=head1 NAME

Ravada::Domain::LXC - LXC containers library for Ravada

=cut

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;
use XML::LibXML;

with 'Ravada::Domain';

##################################################
#
our $TIMEOUT_SHUTDOWN = 60;
our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################

sub name {
    my $self = shift;
    return $self->domain;
}

sub remove {
    my $self = shift;
    my $name = $self->name or confess "Missing domain name";
    my @cmd = ('lxc-destroy','-n',$name,'-f');
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    #die $err   if $?;
    #TODO look $?
    Ravada::VM->_domain_remove_db($name);
  
    return;
}

sub create_files{
    my $self = shift;
    my $domain = shift;
    my $filename = shift;
    my $port = shift;
    my $content = shift;

    my $path = "/var/lib/lxc/$domain/delta0/";
    open my $out,'>>' , "$path/$filename" or die $!;
    print $out $content;
    close $out;
}

sub _run_sh{
    return <<EOF;
#!/bin/bash
SPICE_RES=\${SPICE_RES:-"1280x960"}
SPICE_LOCAL=\${SPICE_LOCAL:-"es_CA.UTF-8"}
TIMEZONE=\${TIMEZONE:-"Europe/Madrid"}
SPICE_USER=\${SPICE_USER:-"user"}
SPICE_UID=\${SPICE_UID:-"1000"}
SPICE_GID=\${SPICE_GID:-"1000"}
SPICE_PASSWD=\${SPICE_PASSWD:-"password"}
SPICE_KB=`echo "\$SPICE_LOCAL" | awk -F"_" '{print \$1}'` 
SUDO=\${SUDO:-"NO"}
locale-gen \$SPICE_LOCAL
echo \$TIMEZONE > /etc/timezone
userdel -r ubuntu
useradd -ms /bin/bash -u \$SPICE_UID \$SPICE_USER
echo "\$SPICE_USER:\$SPICE_PASSWD" | chpasswd
#sed -i "s|#Option \"SpicePassword\" \"\"|Option \"SpicePassword\" \"\$SPICE_PASSWD\"|" /etc/X11/spiceqxl.xorg.conf
#unset SPICE_PASSWD
update-locale LANG=\$SPICE_LOCAL
sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"\$SPICE_KB\"/" /etc/default/keyboard
sed -i "s/SPICE_KB/\$SPICE_KB/" /etc/xdg/autostart/keyboard.desktop
sed -i "s/SPICE_RES/\$SPICE_RES/" /etc/xdg/autostart/resolution.desktop
if [ "\$SUDO" != "NO" ]; then
    sed -i "s/^\(sudo:.*\)/\1\$SPICE_USER/" /etc/group
fi
cd /home/\$SPICE_USER
su \$SPICE_USER -c "/usr/bin/Xorg -config /etc/X11/spiceqxl.xorg.conf -logfile  /home/\$SPICE_USER/.Xorg.2.log :2 &" 2>/dev/null
su \$SPICE_USER -c "DISPLAY=:2 /usr/bin/mate-session"
EOF
}

sub _keyboard_desktop{
    return <<EOF;
[Desktop Entry]
Type=Application
Name=xrandr
Exec=/usr/bin/setxkbmap  SPICE_KB
NoDisplay=true
EOF
}

sub _resolution_desktop{
    return <<EOF;
[Desktop Entry]
Type=Application
Name=xrandr
Exec=/usr/bin/xrandr -s SPICE_RES 
NoDisplay=true
EOF
}

sub _spiceqxl_xorg{
    my $port = shift;
    return <<EOF;
Option "SpicePort" "$port"
Option "SpiceDisableTicketing" "1"
Option "SpiceDeferredFPS" "10"
Option "SpiceIPV4Only" "true"
EOF
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
    print $config _lxc_config($memory,$swap,$cpushares,$ioweight);
    close $config;
}

sub _lxc_config{
    my $memory = shift;
    my $swap =shift;
    my $cpushares = shift;
    my $ioweight = shift;

    return <<EOF;

# RAM, swap, cpushare and ioweight Limits 
lxc.cgroup.memory.limit_in_bytes = $memory
lxc.cgroup.memory.memsw.limit_in_bytes = $swap
lxc.cgroup.cpu.shares = $cpushares
lxc.cgroup.blkio.weight = $ioweight
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
# lxc-execute -n name -- /bin/bash -c /root/run.sh

    my @cmd = ('lxc-start','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;

}

sub shutdown {
    my $self = shift;
    my $name = $self->name;
#    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-stop','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;

}

sub shutdown_now {
    my $self = shift;
    return $self->shutdown(@_);
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

sub unpause {
    my $self = shift;
    my $name = shift or confess "Missing domain name";

    my @cmd = ('lxc-unfreeze','-n',$name);
    my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    warn $out  if $out;
    warn $err   if $err;
    return;
}

=head2 prepare_base

Makes the container available to be a base for other containers.

=cut

sub prepare_base {
    my $self = shift;
    $self->_prepare_base_db();
}

sub disk_device {
    confess "TODO";
}

=head2 add_volume

Adds a new volume to the domain

    $domain->add_volume($size);

=cut

sub add_volume {
}

sub list_volumes {
}

sub list_files_base {
}

sub is_paused {}

sub resume {}

1;
