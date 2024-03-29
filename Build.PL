use 5.008;
use strict;
use warnings;
use Module::Build;

use lib 'inc';

my %platforms =(
  MSWin32   => 'Windows',
  cygwin    => 'Cygwin',
  linux     => 'Unix',
  _default_ => 'Unix', # Unix = default, thus not listing all UNIX like systems
);

my $package = 'My::Builder::' . ($platforms{$^O} || $platforms{_default_});
eval "require $package" or die "###ERROR### Require '$package' failed: $@";
print STDERR "Gonna use '$package' class ...\n";

my $cvs_src;

my $builder = $package->new(
  module_name        => 'Alien::IUP',
  dist_version_from  => 'lib/Alien/IUP.pm',
  dist_author        => 'KMX, kmx@cpan.org',
  license            => 'mit',
  requires => {
    'perl'              => 5.008008,
    'File::ShareDir'    => 0,
    'File::Spec'        => 0,
  },
  configure_requires => {
    'perl'              => 5.008008,
    'Module::Build'     => 0.36,
    'File::ShareDir'    => 0,
    'File::Spec'        => 0,
    'File::Path'        => 0,
    'File::Temp'        => 0.22,
    'File::Find'        => 0,
    'ExtUtils::CBuilder'=> 0,
    'ExtUtils::Command' => 0,
    'ExtUtils::Liblist' => 0,
    'LWP::Simple'       => 0,
    'Digest::SHA'       => 0,
    'Archive::Extract'  => 0,
    'Text::Patch'       => 0,
    'IPC::Run3'         => 0.041, # we need return_if_system_error
  },
  build_requires => {
    'perl'              => 5.008008,
    'Module::Build'     => 0.36,
    'Test::More'        => 0,
    'File::ShareDir'    => 0,
    'File::Spec'        => 0,
    'File::Path'        => 0,
    'File::Temp'        => 0.22,
    'File::Find'        => 0,
    'ExtUtils::CBuilder'=> 0,
    'ExtUtils::Command' => 0, #Win32 external makefiles need this
    'ExtUtils::Liblist' => 0,
    'LWP::Simple'       => 0,
    'Digest::SHA'       => 0,
    'Archive::Extract'  => 0,
    'Text::Patch'       => 0,
    'IPC::Run3'         => 0.041, # we need return_if_system_error
  },
  share_dir          => 'sharedir',
  get_options => { 'cvs' => { qw(type :s  store) => \$cvs_src } },
  #create_makefile_pl => 'small', # creating Makefile.PL to satisfy old CPAN clients (does not work well with our style of M::B use)
  create_readme      => 1,
  meta_merge => {
    resources  => {
      bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Alien-IUP',
      repository => 'https://github.com/kmx/alien-iup',
    }
  },
);

unlink 'build_done'; # delete build marker (= force rebuild after running Build.PL)
$builder->add_to_cleanup("sharedir/" . $builder->{properties}->{dist_version}); # catfile() would be better
$builder->add_to_cleanup('build_done');
$builder->add_to_cleanup('build_src');

if (defined $cvs_src) { ### use the latest sources from iup repository
  warn "###\n";
  warn "###BEWARE: gonna use CVS sources (might be unstable)!\n";
  warn "###\n";
  $builder->notes('iup_url',  'https://github.com/kmx/mirror-iup/tarball/master');
  $builder->notes('iup_sha1', 'DO_NOT_CHECK_SHA1');
  $builder->notes('im_url',   'https://github.com/kmx/mirror-im/tarball/master');
  $builder->notes('im_sha1',  'DO_NOT_CHECK_SHA1');
  $builder->notes('cd_url',   'https://github.com/kmx/mirror-cd/tarball/master');
  $builder->notes('cd_sha1',  'DO_NOT_CHECK_SHA1');
  $builder->notes('build_debug_info', 1);
  $builder->notes('is_devel_cvs_version', 1)
}
else {
  if ($builder->check_installed_lib()) {
    my $ans = $ENV{TRAVIS} ? 'y' : $builder->prompt("\nIUP detected, wanna use IUP already installed on your system (y/n)?", 'y');
    $builder->notes('already_installed_lib', undef) if lc($ans) ne 'y';
  }

  # set what tarballs we are gonna use
  $builder->notes('iup_url', 'http://download.sf.net/iup/iup-3.11.2_Sources.tar.gz');
  $builder->notes('iup_sha1', '29353033eed05c0258e49e2ef4925baeca15c607');
  $builder->notes('iup_patches', [ qw!patches/old-cygwin.diff patches/makefile-matex.diff patches/mglplot-cygwin.diff patches/iup-cygwin.diff! ] );

  $builder->notes('im_url', 'http://download.sf.net/imtoolkit/im-3.9_Sources.tar.gz');
  $builder->notes('im_sha1', '55e54739e1f0b88c206e84ab2636a3277693e156');
  $builder->notes('im_patches', [ qw!patches/im-dragonfly.diff! ] );

  $builder->notes('cd_url', 'http://download.sf.net/canvasdraw/cd-5.8_Sources.tar.gz');
  $builder->notes('cd_sha1', '397627d89811191c0db42b19accc2f7867042ab1');
  $builder->notes('cd_patches', [ qw!patches/cd-dragonfly.diff! ] );
}

# check if we have GNU make otherwise 'exit 0' - cpan testers will report "N/A"
my $m = $builder->get_make;
exit 0 unless $m;
$builder->notes('gnu_make', $m);

$builder->create_build_script();
