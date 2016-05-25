package Ravada::VM::LXC;

use Carp qw(croak);
use Data::Dumper;
use Fcntl qw(:flock O_WRONLY O_EXCL O_CREAT);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use Moose;
use Sys::Hostname;
use XML::LibXML;

#use Ravada::Domain::LXC;

with 'Ravada::VM';

1;
