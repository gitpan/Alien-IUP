package My::Builder::Unix;

use strict;
use warnings;
use base 'My::Builder';

use File::Spec::Functions qw(catdir catfile rel2abs);
use File::Spec qw(devnull);
use File::Glob qw(glob);
use File::Copy;
use Config;

sub build_binaries {
  my ($self, $build_out, $srcdir) = @_;
  my $success = 1;
  my ($extra_cflags, $extra_lflags) = ('-I/usr/local/include', '-L/usr/local/lib');

  #try to detect some inc/lib directories
  my $d;
  $d = $self->run_stdout2str(qw[pkg-config --variable=libdir x11]);
  my $dir_x11_lib = ($d && -d $d && $d ne '/usr/lib') ? $d : '';
  $d = $self->run_stdout2str(qw[pkg-config --variable=includedir x11]);
  my $dir_x11_inc = ($d && -d $d && $d ne '/usr/include') ? $d : '';
  $d = $self->run_stdout2str(qw[pkg-config --variable=libdir gl]);
  my $dir_opengl_lib = ($d && -d $d && $d ne '/usr/lib') ? $d : '';
  $d = $self->run_stdout2str(qw[pkg-config --variable=includedir gl]);
  my $dir_opengl_inc = ($d && -d $d && $d ne '/usr/include') ? $d : '';
  $d = $self->run_stdout2str(qw[pkg-config --variable=prefix gtk+-2.0]);
  my $dir_gtk = ($d && -d $d) ? $d : '';

  my $dir_mot_inc = ''; # Xm/Xm.h (do not know where to get a sane default)
  $dir_mot_inc  ||= '/usr/local/include'         if (-f '/usr/local/include/Xm/Xm.h');

  my $dir_mot_lib = ''; # -lXm (do not know where to get a sane default)
  $dir_mot_lib  ||= '/usr/local/lib'             if (-f '/usr/local/lib/libXm.a');
  $dir_mot_lib  ||= '/usr/local/lib'             if (-f '/usr/local/lib/libXm.so');
  $dir_mot_lib  ||= '/usr/local/lib'             if (-f '/usr/local/lib/libXm.la');

  #platform specific hacks
  if ($^O eq 'solaris') {
    $dir_mot_inc    ||= '/usr/dt/include'            if (-f '/usr/dt/include/Xm/Xm.h');
    $dir_mot_lib    ||= '/usr/dt/lib'                if (-f '/usr/dt/lib/libXm.so');
    $dir_opengl_inc ||= '/usr/X11/include'           if (-f '/usr/X11/include/GL/gl.h');
    $dir_opengl_lib ||= '/usr/X11/lib/GL'            if (-f '/usr/X11/lib/GL/libGL.so');
    $dir_x11_inc    ||= '/usr/openwin/include'       if (-f '/usr/openwin/include/X11/Xlib.h');
    $dir_x11_lib    ||= '/usr/openwin/lib'           if (-f '/usr/openwin/lib/libX11.so');
    $dir_x11_inc    ||= '/usr/openwin/share/include' if (-f '/usr/openwin/share/include/X11/Xlib.h');
    $dir_x11_lib    ||= '/usr/openwin/share/lib'     if (-f '/usr/openwin/share/lib/libX11.so');
  }

  if ($^O eq 'darwin') {
    $extra_cflags .= ' -I/opt/local/include';
    $extra_lflags .= ' -L/opt/local/lib';
  }

  #generic /usr/X11R6/...
  $dir_x11_inc    ||= '/usr/X11R6/include' if (-f '/usr/X11R6/include/X11/Xlib.h');
  $dir_x11_lib    ||= '/usr/X11R6/lib'     if (-f '/usr/X11R6/lib/libX11.so');
  $dir_opengl_inc ||= '/usr/X11R6/include' if (-f '/usr/X11R6/include/GL/gl.h');
  $dir_opengl_lib ||= '/usr/X11R6/lib'     if (-f '/usr/X11R6/lib/libGL.so');
  #generic /usr/X11R7/...
  $dir_x11_inc    ||= '/usr/X11R7/include' if (-f '/usr/X11R7/include/X11/Xlib.h');
  $dir_x11_lib    ||= '/usr/X11R7/lib'     if (-f '/usr/X11R7/lib/libX11.so');
  $dir_opengl_inc ||= '/usr/X11R7/include' if (-f '/usr/X11R7/include/GL/gl.h');
  $dir_opengl_lib ||= '/usr/X11R7/lib'     if (-f '/usr/X11R7/lib/libGL.so');

  $extra_cflags .= " -I$dir_x11_inc"    if $dir_x11_inc;
  $extra_lflags .= " -L$dir_x11_lib"    if $dir_x11_lib;
  $extra_cflags .= " -I$dir_opengl_inc" if $dir_opengl_inc;
  $extra_lflags .= " -I$dir_opengl_lib" if $dir_opengl_lib;

  print STDERR "Checking available libraries/headers...\n";
  if ($self->notes('build_debug_info')) {
    print STDERR "extra_cflags=$extra_cflags\n";
    print STDERR "extra_lflags=$extra_lflags\n";
  }
  my %has;

  $has{gtk}     = `pkg-config --modversion gtk+-2.0 2>/dev/null` ? 1 : 0;        #iupgtk
  $has{gtkx11}  = `pkg-config --modversion gtk+-x11-2.0 2>/dev/null` ? 1 : 0;
  $has{gdk}     = `pkg-config --modversion gdk-2.0 2>/dev/null` ? 1 : 0;        #cdgdk
  $has{gdkx11}  = `pkg-config --modversion gdk-x11-2.0 2>/dev/null` ? 1 : 0;
  $has{cairo}   = `pkg-config --modversion cairo 2>/dev/null` ? 1 : 0;                 #cdcairo
  $has{pango}   = `pkg-config --modversion pango 2>/dev/null` ? 1 : 0;                #cdcairo
  #$has{pangox}  = `pkg-config --modversion pangox 2>/dev/null` ? 1 : 0;

  $has{l_gtk}   = $has{gtk}    && $self->check_lib( [] , `pkg-config --cflags gtk+-2.0 2>/dev/null`,     `pkg-config --libs gtk+-2.0 2>/dev/null`);
  $has{l_gtkx11}= $has{gtkx11} && $self->check_lib( [] , `pkg-config --cflags gtk+-x11-2.0 2>/dev/null`, `pkg-config --libs gtk+-x11-2.0 2>/dev/null`);
  $has{l_gdk}   = $has{gdk}    && $self->check_lib( [] , `pkg-config --cflags gdk-2.0 2>/dev/null`,      `pkg-config --libs gdk-2.0 2>/dev/null`);
  $has{l_gdkx11}= $has{gdkx11} && $self->check_lib( [] , `pkg-config --cflags gdk-x11-2.0 2>/dev/null`,  `pkg-config --libs gdk-x11-2.0 2>/dev/null`);
  $has{l_cairo} = $has{cairo}  && $self->check_lib( [] , `pkg-config --cflags cairo 2>/dev/null`,        `pkg-config --libs cairo 2>/dev/null`);
  $has{l_pango} = $has{pango}  && $self->check_lib( [] , `pkg-config --cflags pango 2>/dev/null`,        `pkg-config --libs pango 2>/dev/null`);
  #$has{l_pangox}= $has{pangox} && $self->check_lib( [] , `pkg-config --cflags pangox 2>/dev/null`,       `pkg-config --libs pangox 2>/dev/null`);

  $has{l_Xp}    = $self->check_lib( 'Xp',   $extra_cflags, $extra_lflags );
  $has{l_Xt}    = $self->check_lib( 'Xt',   $extra_cflags, $extra_lflags );
  $has{l_Xm}    = $self->check_lib( 'Xm',   $extra_cflags, $extra_lflags . ' -lX11 -lXt' );
  $has{l_Xmu}   = $self->check_lib( 'Xmu',  $extra_cflags, $extra_lflags );
  $has{l_Xext}  = $self->check_lib( 'Xext', $extra_cflags, $extra_lflags );
  $has{l_X11}   = $self->check_lib( 'X11',  $extra_cflags, $extra_lflags );
  $has{l_GL}    = $self->check_lib( 'GL',   $extra_cflags, $extra_lflags );
  $has{l_GLU}   = $self->check_lib( 'GLU',  $extra_cflags, $extra_lflags . ' -lGL -lm' );
  $has{l_glut}  = $self->check_lib( 'glut', $extra_cflags, $extra_lflags );

  $has{Xm}      = $self->check_header('Xm/Xm.h',   $extra_cflags);
  $has{Xlib}    = $self->check_header('X11/Xlib.h',$extra_cflags); #iupgl cdx11
  $has{glx}     = $self->check_header('GL/glx.h',  $extra_cflags); #iupgl
  $has{glu}     = $self->check_header('GL/glu.h',  $extra_cflags);
  $has{gl}      = $self->check_header('GL/gl.h',   $extra_cflags);

  if ($self->notes('build_debug_info')) {
    #$has{fftw3}   = $self->check_header('fftw3.h',   $extra_cflags); #im_fftw3 = http://www.fftw.org/
    #$has{wmsdk}   = $self->check_header('wmsdk.h');                  #im_wmv
    #$has{ecw}     = $self->check_header('NCSECWClient.h');           #im_format_ecw = ECW (Enhanced Compression Wavelet) format
    #$has{XxXxX}   = $self->check_header('XxXxX/XxXxX.h');            #non existing header
    print STDERR "Has: $has{$_} - $_\n" foreach (sort keys %has);

    print STDERR "Brute force lookup:\n";
    my $re = qr/\/(Xlib.h|Xm.h|gtk.h|glu.h|glut.h|gl.h|gtkprintunixdialog.h|libX11\.[^\d]*|libGL\.[^\d]*|libXm\.[^\d]*)$/;
    print STDERR "[/usr    ] $_\n" foreach ($self->find_file('/usr', $re));
    print STDERR "[/lib    ] $_\n" foreach ($self->find_file('/usr', $re));
    print STDERR "[/opt    ] $_\n" foreach ($self->find_file('/opt', $re));
    print STDERR "[/sw     ] $_\n" foreach ($self->find_file('/sw', $re));
    print STDERR "[/System ] $_\n" foreach ($self->find_file('/System', $re));
    print STDERR "[/Library] $_\n" foreach ($self->find_file('/Library', $re));
    print STDERR "[/Network] $_\n" foreach ($self->find_file('/Network', $re));

    print STDERR "Dumping some pkg-info:\n";
    print STDERR "[gtk2 cflags] " . $self->run_stdout2str(qw[pkg-config --cflags gtk+-2.0]) . "\n";
    print STDERR "[gtk2 libs  ] " . $self->run_stdout2str(qw[pkg-config --libs gtk+-2.0]) . "\n";
    for my $pkg (qw[gtk+-2.0 gl glu glut x11 xt xext xmu]) {
      print STDERR "[prefix     $pkg] " . $self->run_stdout2str(qw[pkg-config --variable=prefix], $pkg) . "\n";
      print STDERR "[libdir     $pkg] " . $self->run_stdout2str(qw[pkg-config --variable=libdir], $pkg) . "\n";
      print STDERR "[includedir $pkg] " . $self->run_stdout2str(qw[pkg-config --variable=includedir], $pkg) . "\n";
    }
  }

  my @x11_libs; # just base X11 libs
  push(@x11_libs, 'X11')  if $has{l_X11};
  push(@x11_libs, 'Xext') if $has{l_Xext};

  my @opengl_libs;
  push(@opengl_libs, 'GL')  if $has{l_GL};
  push(@opengl_libs, 'GLU') if $has{l_GLU};

  #possible targets: im im_process im_jp2 im_fftw im_capture im_avi im_wmv im_fftw3 im_ecw
  my @imtargets = qw[im im_process im_jp2 im_fftw];
  if ($^O eq 'openbsd') {
    warn "###WARN### Skipping im_process on OpenBSD"; # xxx TODO xxx
    @imtargets = grep { $_ !~ /^(im_process)$/ } @imtargets;
  }

  #possible targets: cd_freetype cd_ftgl cd cd_pdflib cdpdf cdgl cdcontextplus cdcairo
  my @cdtargets = qw[cd_freetype cd_ftgl cd cd_pdflib cdpdf cdgl];
  @cdtargets = grep { $_ !~ /^(cd_ftgl|cdgl)$/ } @cdtargets unless $has{l_GLU};

  #possible targets: iup iupcd iupcontrols iupim iupimglib iup_pplot iupgl
  my @iuptargets = qw[iup iupcd iupcontrols iupim iupimglib iup_pplot iupgl];
  @iuptargets = grep { $_ !~ /^(iupgl)$/ } @iuptargets unless $has{glx};

  #store debug info into ConfigData
  $self->config_data('debug_has', \%has);
  $self->config_data('debug_imtargets', \@imtargets);
  $self->config_data('debug_cdtargets', \@cdtargets);
  $self->config_data('debug_iuptargets', \@iuptargets);

  my @makeopts  = qw[NO_DYNAMIC=Yes USE_NODEPEND=Yes];
  #my @makeopts  = qw[NO_STATIC=Yes USE_NODEPEND=Yes];
  
  #choose GUI subsystem, priorities if multiple subsystems detected: 1. GTK, 2. X11/Motif
  my @libs;
  my @build_opts;
  my $build_target = '';
  
  push(@build_opts, 'GTK2') if $has{gtk};
  push(@build_opts, 'X11/Motif') if ($has{Xlib} && $has{Xm});

  if (scalar(@build_opts) == 1) {
    $build_target = $build_opts[0];
  }
  elsif (scalar(@build_opts) > 1) {
    my $n = 1;
    my $msg = "\nYou have the following build options available:\n" .
              join("\n", map ($n++ . ") $_", @build_opts)) .
	      "\nWhat do you wanna build?";
    my $i = $self->prompt($msg, 1);
    $build_target = $build_opts[$i-1];
    die "###ERROR### Wrong selection!" unless $build_target;
  }
  else {
    die "###FATAL### No supported GUI subsystem (Win32, GTK, X11/Motif) detected! (trying X11)";
    #warn "###WARN### No supported GUI subsystem (Win32, GTK, X11/Motif) detected! (trying X11)";
    $success = 0;
    $build_target = 'X11/Motif';
  }

  print STDERR "Build target=", ($build_target || ''), "\n";  
  if ($build_target eq 'GTK2') {
    push(@makeopts, 'USE_GTK=Yes');
    #detected libs
#xxx    push(@makeopts, "GTK_BASE=$dir_gtk") if $dir_gtk;
    push(@makeopts, "X11_LIBS=" . join(' ', @x11_libs));
    push(@makeopts, "X11_LIB=$dir_x11_lib") if $dir_x11_lib;
    push(@makeopts, "X11_INC=$dir_x11_inc") if $dir_x11_inc;
    push(@makeopts, "OPENGL_LIBS=" . join(' ', @opengl_libs));
    push(@makeopts, "OPENGL_LIB=$dir_opengl_lib") if $dir_opengl_lib;
    push(@makeopts, "OPENGL_INC=$dir_opengl_inc") if $dir_opengl_inc;

    push(@libs, @opengl_libs);
    #Note: $extra_?flags will be stored into ConfigData - they are not used for building
    my @mods = qw[gtk+-2.0 gdk-2.0 pango cairo];
    $extra_cflags = $self->run_stdout2str(qw[pkg-config --cflags], @mods) . " $extra_cflags";
    $extra_lflags = $self->run_stdout2str(qw[pkg-config --libs], @mods) . " $extra_lflags";
  }
  elsif ($build_target eq 'X11/Motif') {
    push(@makeopts, 'USE_X11=Yes');
    #additional X11 related libs
    push(@x11_libs, 'Xp')   if $has{l_Xp};
    push(@x11_libs, 'Xt')   if $has{l_Xt};
    push(@x11_libs, 'Xm')   if $has{l_Xm};
    push(@x11_libs, 'Xmu')  if $has{l_Xmu};
    #detected libs
    push(@makeopts, "X11_LIBS=" . join(' ', @x11_libs));
    push(@makeopts, "X11_LIB=$dir_x11_lib") if $dir_x11_lib;
    push(@makeopts, "X11_INC=$dir_x11_inc") if $dir_x11_inc;
    push(@makeopts, "OPENGL_LIBS=" . join(' ', @opengl_libs));
    push(@makeopts, "OPENGL_LIB=$dir_opengl_lib") if $dir_opengl_lib;
    push(@makeopts, "OPENGL_INC=$dir_opengl_inc") if $dir_opengl_inc;
    push(@makeopts, "MOTIF_INC=$dir_mot_inc") if $dir_mot_inc;
    push(@makeopts, "MOTIF_LIB=$dir_mot_lib") if $dir_mot_lib;
    push(@libs, @x11_libs, @opengl_libs);
    #Note: $extra_?flags set at the beginning of this sub
  }
  else {
    die "###ERROR### Wrong build target '$build_target!";
  }

  #do the job
  print STDERR "Gonna make these targets: " . join(' ', @iuptargets, @cdtargets, @imtargets) . "\n";
  unless ($self->build_via_tecmake($build_out, $srcdir, \@makeopts, \@iuptargets, \@cdtargets, \@imtargets)) {
    warn "###MAKE FAILED###";
    $success = 0;
  }

  #make a list of libs necessary to link with IUP and related libraries
  my %seen;
  my @gl_l = glob("$build_out/lib/*");
  my @gl_i = glob("$build_out/include/*");
  print STDERR "Output counts: lib=" . scalar(@gl_l) . " include=" . scalar(@gl_i) . "\n";
  if ((scalar(@gl_l) < 3) || (scalar(@gl_i) < 3)) {
    warn "###WARN### $build_out/lib/ or $build_out/include/ not complete";
    $success = 0;
  }
  foreach (@gl_l) {
    if ($_ =~ /lib([a-zA-Z0-9\_\-\.]*?)\.(so|dylib|bundle|a|dll\.a)$/) {
      $seen{$1} = 1;
    }
    elsif ($_ !~ /\.dll$/) { # *.dll on cygwin is OK
      warn "###WARN### Unexpected filename '$_'";
      $success = 0;
    }
  }

  push(@libs, 'stdc++'); # -lstdc++ needed by Linux (at least)

  print STDERR "Output libs: $_\n" foreach (sort keys %seen);
  @libs = ( $self->sort_libs(keys %seen), @libs );

  $self->config_data('linker_libs', \@libs);
  $self->config_data('extra_cflags', $extra_cflags);
  $self->config_data('extra_lflags', $extra_lflags);

  die "###BUILD ABORTED###" unless $success;
  print STDERR "Build finished sucessfully!\n";

  #DEBUG: fail intentionally here if you want to see build details from cpan testers
  #die "Intentionally failing";
};

sub build_via_tecmake {
  my ($self, $build_out, $srcdir, $mopts, $iuptgs, $cdtgs, $imtgs) = @_;
  $srcdir ||= 'src';
  my $prefixdir = rel2abs($build_out);
  my $make = $self->notes('gnu_make') || $self->get_make;
  die "###ERROR## make command not defined" unless $make;
  my $im_si;
  my $success = 1;

  # save it for future use in ConfigData
  $self->config_data('build_prefix', $prefixdir);
  $self->config_data('debug_makeopts', $mopts);

  #create output directory structure
  mkdir "$prefixdir" unless -d "$prefixdir";
  mkdir "$prefixdir/lib" unless -d "$prefixdir/lib";
  mkdir "$prefixdir/include" unless -d "$prefixdir/include";

  my %done;

  if(-d "$srcdir/im/src") {
    print STDERR "Gonna build 'im'\n";
    chdir "$srcdir/im/src";
    foreach my $t (@{$imtgs}) {
      if ($self->notes('build_msgs')) {
        $done{$t} = $self->run_output_std($make, $t, @{$mopts});
      }
      else {
        $done{$t} = $self->run_output_on_error(undef, $make, $t, @{$mopts});
      }
      warn "###WARN### error [$?] during make $t" unless $done{$t};
      $success = 0 unless $done{$t};
    }
    copy($_, "$prefixdir/include/") foreach (glob("../include/*.h"));
    copy($_, "$prefixdir/lib/") foreach (glob("../lib/*/*"));
    chdir $self->base_dir();
  }

  if (-d "$srcdir/cd/src") {
    print STDERR "Gonna build 'cd'\n";
    chdir "$srcdir/cd/src";
    foreach my $t (@{$cdtgs}) {
      if ($self->notes('build_msgs')) {
        $done{$t} = $self->run_output_std($make, $t, @{$mopts});
      }
      else {
        $done{$t} = $self->run_output_on_error(undef, $make, $t, @{$mopts});
      }
      warn "###WARN### error [$?] during make $t" unless $done{$t};
      $success = 0 unless $done{$t};
    }
    copy($_, "$prefixdir/include/") foreach (glob("../include/*.h"));
    copy($_, "$prefixdir/lib/") foreach (glob("../lib/*/*"));
    chdir $self->base_dir();
  }

  if (-d "$srcdir/iup") {
    print STDERR "Gonna build 'iup'\n";
    chdir "$srcdir/iup";
    foreach my $t (@{$iuptgs}) {
      if ($self->notes('build_msgs')) {
        $done{$t} = $self->run_output_std($make, $t, @{$mopts});
      }
      else {
        $done{$t} = $self->run_output_on_error(undef, $make, $t, @{$mopts});
      }
      warn "###WARN### error [$?] during make $t" unless $done{$t};
      $success = 0 unless $done{$t};
    }
    copy($_, "$prefixdir/include/") foreach (glob("./include/*.h"));
    copy($_, "$prefixdir/lib/") foreach (glob("./lib/*/*"));
    chdir $self->base_dir();
  }

  unless ($done{iup} && $done{iupim} && $done{iupcd}) {
    warn "###WARN### essential libs not built!";
    $success = 0;
  }

  print STDERR "Done: $done{$_} - $_\n" foreach (sort keys %done);
  $self->config_data('debug_done', \%done);
  $self->config_data('debug_si', $im_si);

  return $success;
}

sub get_make {
  my ($self) = @_;

  my $devnull = File::Spec->devnull();
  my @try = ($Config{gmake}, 'gmake', 'make', $Config{make});
  my %tested;
  print STDERR "Gonna detect GNU make:\n";

  if ($^O eq 'cygwin') {
    print STDERR "- on cygwin always 'make'\n";
    return 'make'
  }

  foreach my $name ( @try ) {
    next unless $name;
    next if $tested{$name};
    $tested{$name} = 1;
    print STDERR "- testing: '$name'\n";
    my $ver = `$name --version 2> $devnull`;
    if ($ver =~ /GNU Make/i) {
      print STDERR "- found: '$name'\n";
      return $name
    }
  }

  warn "###WARN### it seems we do not have GNU make, build is likely gonna fail!";
  return;
  
  #print STDERR "- fallback to: 'make'\n";
  #return 'make';
}

sub quote_literal {
    my ($self, $txt) = @_;
    $txt =~ s|'|'\\''|g;
    return "'$txt'";
}

1;
