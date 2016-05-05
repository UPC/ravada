package Ravada::Domain;

use warnings;
use strict;

use Moose::Role;

has 'name' => (
    isa => 'Str'
    ,is => 'ro'
);

1;
