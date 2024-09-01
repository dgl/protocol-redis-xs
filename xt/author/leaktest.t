use strict;
use warnings;
use Test::More;
use Protocol::Redis::XS;
use Devel::Gladiator 'walk_arena';

sub count_arena { my $arena = walk_arena; my $count = @$arena; @$arena = (); return $count }

my $protocol = Protocol::Redis::XS->new(api => 1);

my $start_count = count_arena;
{
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


  $protocol->encode($input);
}
my $end_count = count_arena;

is $end_count, $start_count, 'no memory leak while encoding nested structure';

$start_count = count_arena;
{
  my $input = {
    'type' => '*',
    'data' => [
      {
        'type' => '$',
        'data' => 'GET',
      },
      {
        type => '*',
        data => [
          {
            'data' => 'cool:key',
            'type' => '$',
          },
          {
            type => '*',
            data => [
              {
                data => '',
                type => 'bogus',
              },
            ],
          },
        ],
      },
    ]
  };

  eval {
    $protocol->encode($input);
  };
}
$end_count = count_arena;

is $end_count, $start_count, 'no memory leak while encoding nested structure with errors';

done_testing;
