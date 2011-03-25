use strict;
use warnings;
use Test::More tests => 3;
use Protocol::Redis::Test;

use_ok 'Protocol::Redis::XS';
my $redis = new_ok 'Protocol::Redis::XS';

# Test Protocol::Redis API
protocol_redis_ok $redis, 1;
