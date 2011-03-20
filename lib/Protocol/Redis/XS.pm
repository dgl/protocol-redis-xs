package Protocol::Redis::XS;
use strict;
use warnings;
use parent "Protocol::Redis";

use XS::Object::Magic;
use XSLoader;

our $VERSION = '0.01';

XSLoader::load "Protocol::Redis::XS", $VERSION;

sub new {
  my($class) = @_;
  my $self = bless {}, $class;
  $self->create;

  return $self;
}

1;

__END__

=head1 NAME

Protocol::Redis::XS - hiredis based parser compatible with Protocol::Redis

=head1 SYNOPSIS

  use Protocol::Redis::XS;
  my $redis = Protocol::Redis::XS->new;
  $redis->parse("+OK\r\n");
  $redis->get_message;

=head1 DESCRIPTION

This provides a fast parser for the Redis protocol using the code from
L<http://github.com/antirez/hiredis|hiredis> and with API compatibility with
L<Protocol::Redis>.

This is a low level parsing module, you probably want to look at the modules
mentioned in L</SEE ALSO> first.

=head1 METHODS

As per L<Protocol::Redis>.

=head2 parse($string)

Parse a chunk of data (calls L</on_message> callback if defined and a complete
message is received).

=head2 get_message

Return a message. This is a potentially nested data structure, for example as
follows:

  {
    type => '*',
    data => [
      {
        type => '$',
        data => 'hello'
      }
    ]
  }

=head2 on_message

Set callback for L</parse>.

=head1 SEE ALSO

L<Redis>, L<Redis::hiredis>, L<AnyEvent::Redis>, L<Protocol::Redis>.

=head1 AUTHOR

David Leadbeater <dgl@dgl.cx>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 David Leadbeater.

This program is free software; you can redistribute it and/or modify it under
the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

The hiredis library included in this distribution has a seperate license (3
clause BSD). See F<hiredis/COPYING>.

=cut

# ex:sw=2 et:
