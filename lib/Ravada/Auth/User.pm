package Ravada::Auth::User;

use warnings;
use strict;

use Carp qw(confess croak);
use Moose::Role;

requires 'add_user';
requires 'is_admin';

has 'name' => (
           is => 'ro'
         ,isa => 'Str'
    ,required => 1
);

has 'password' => (
           is => 'ro'
         ,isa => 'Str'
    ,required => 0
);

1;
