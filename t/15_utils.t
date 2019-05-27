use Test::More;

use_ok('Ravada::Utils');

is( Ravada::Utils::number_to_size(512), '0.5K');
is( Ravada::Utils::number_to_size(1024), '1K');
is( Ravada::Utils::number_to_size(1024 + 512), '1.5K');

is( Ravada::Utils::number_to_size(1024 * 1024), '1M');
is( Ravada::Utils::number_to_size( (1024+512) * 1024), '1.5M');

is( Ravada::Utils::number_to_size(1024 * 1024 * 1024), '1G');
is( Ravada::Utils::number_to_size( (1024+512) * 1024 * 1024), '1.5G');

is( Ravada::Utils::number_to_size(9959 * 1024) , '9959K');
is( Ravada::Utils::number_to_size(9959 * 1024 * 1024) , '9959M');

is( Ravada::Utils::size_to_number('1K'), 1024 );
is( Ravada::Utils::size_to_number('1.5K'), 1024 * 1.5 );

is( Ravada::Utils::size_to_number('1M'), 1024 * 1024 );
is( Ravada::Utils::size_to_number('1.5M'), 1024 * 1024 * 1.5 );
is( Ravada::Utils::size_to_number('1.5G'), 1024 * 1024 * 1024 * 1.5 );

done_testing();
