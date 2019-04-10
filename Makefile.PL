use strict;
use warnings;
use ExtUtils::MakeMaker 6.31;
use ExtUtils::Depends;

my $pkg = ExtUtils::Depends->new("Protocol::Redis::XS", "XS::Object::Magic");
$pkg->set_inc("-Ihiredis");
my %dep = $pkg->get_makefile_vars;

# Workaround bugs in the toolchain so we can actually build things in
# directories.
my $my_xs = q[XS$(OBJ_EXT)];
my @hiredis_files = map "$_\$(OBJ_EXT)", qw(hiredis sds net);
my $hiredis_obj = join " ", map 'hiredis/' . $_, @hiredis_files;

my %WriteMakefile_args = (
  NAME          => 'Protocol::Redis::XS',
  AUTHOR        => 'David Leadbeater <dgl@dgl.cx>',
  LICENSE       => 'perl_5',
  ABSTRACT_FROM => 'lib/Protocol/Redis/XS.pm',
  VERSION_FROM  => 'lib/Protocol/Redis/XS.pm',

  CONFIGURE_REQUIRES => {
    'ExtUtils::MakeMaker' => '6.31',
    'ExtUtils::Depends' => 0,
    'XS::Object::Magic' => 0,
  },

  TEST_REQUIRES => {
    'Test::More' => '0.88',
    'Protocol::Redis::Test' => 0,
  },

  PREREQ_PM => {
    'XSLoader' => 0,
    'XS::Object::Magic' => 0,
    'Protocol::Redis' => '0.9001',
    'parent' => 0,
  },

  INC      => $dep{INC},
  TYPEMAPS => $dep{TYPEMAPS},
  OBJECT   => "$my_xs $hiredis_obj",
  LDFROM   => "$my_xs " . join(" ", @hiredis_files),

  META_MERGE => {
    'meta-spec'    => { version => 2 },
    resources      => {
      repository   => {
        type       => 'git',
        url        => 'https://github.com/dgl/protocol-redis-xs.git',
        web        => 'https://github.com/dgl/protocol-redis-xs',
      },
      bugtracker   => { web => 'https://github.com/dgl/protocol-redis-xs/issues' },
      x_IRC        => 'irc://irc.perl.org/#redis',
    },
    x_contributors => [
      'Mike Magowan <mike@magowan.co.uk>',
      'Sergey Zasenko <d3fin3@gmail.com>',
    ],
  },
);

delete $WriteMakefile_args{META_MERGE}
  unless eval { ExtUtils::MakeMaker->VERSION('6.46') };
unless (eval { ExtUtils::MakeMaker->VERSION('6.64') }) {
  my $test_requires = delete $WriteMakefile_args{TEST_REQUIRES};
  $WriteMakefile_args{PREREQ_PM}{$_} = $test_requires->{$_} for keys %$test_requires;
}

WriteMakefile(%WriteMakefile_args);
