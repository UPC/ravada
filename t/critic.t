use strict;
use Test::More;
use Test::Perl::Critic( -exclude => ['Prototypes']);

if ($@ ) {
    diag($@);
    plan(skip_all => "Test::Perl::Critic required to criticise code");
} else {
    Test::Perl::Critic::all_critic_ok('lib','script');
}
