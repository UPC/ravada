use strict;
use Test::More;
eval { require Test::Perl::Critic; };

if ($@ ) {
    plan(skip_all => "Test::Perl::Critic required to criticise code");
} else {
    Test::Perl::Critic::all_critic_ok('lib');
}
