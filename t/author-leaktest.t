use strict;
use warnings;
use if !$ENV{AUTHOR_TESTING}, 'Test::More', skip_all => 'Author side testing only';
use Test::More;
use Protocol::Redis::XS;
use Devel::Gladiator 'walk_arena';

sub count_arena { my $arena = walk_arena; my $count = @$arena; @$arena = (); return $count }

my $protocol = Protocol::Redis::XS->new(api => 1);

my $input = {
  'type' => '*',
  'data' => [
    {
      'type' => '$',
      'data' => 'GET'
    },
    {
      'data' => 'cool:key',
      'type' => '$'
    }
  ]
};

my $start_count = count_arena;

$protocol->encode($input);

my $end_count = count_arena;

is $end_count, $start_count, 'no memory leak';

done_testing;
