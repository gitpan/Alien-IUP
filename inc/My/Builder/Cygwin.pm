package My::Builder::Cygwin;

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
  
  #do the job
  $success = $self->build_via_tecmake($build_out, $srcdir);
  warn "###MAKE FAILED###" unless $success;

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
    if ($_ =~ /lib([a-zA-Z0-9\_\-\.]*?)\.(a|dll\.a)$/) {
      $seen{$1} = 1;
    }
    elsif ($_ !~ /\.dll$/) { # *.dll on cygwin is OK
      warn "###WARN### Unexpected filename '$_'";
      $success = 0;
    }
  }
  print STDERR "Output libs: $_\n" foreach (sort keys %seen);
  my @libs = $self->sort_libs(keys %seen);

  $self->config_data('extra_cflags', '');
  $self->config_data('extra_lflags', '');
  $self->config_data('linker_libs', [ @libs, qw/gdi32 comdlg32 comctl32 winspool uuid ole32 oleaut32 opengl32 glu32/ ] );

  die "###BUILD ABORTED###" unless $success;
  print STDERR "Build finished sucessfully!\n";
};

sub build_via_tecmake {
  my ($self, $build_out, $srcdir) = @_;
  my $prefixdir = rel2abs($build_out);

  my @cdtgs = qw[cd_freetype cd_ftgl config cd_pdflib cdpdf cdgl]; #config = default target (libcd)
  my @imtgs = qw[config im_process im_jp2 im_fftw]; #config = default target (libim)
  my @iuptgs = qw[src srccd srccontrols srcpplot srcgl srcim srcimglib srcole]; #!!! srcweb fails

  my $im_si;
  my $success = 1;

  # save it for future use in ConfigData
  $self->config_data('build_prefix', $prefixdir);

  #create output directory structure
  mkdir "$prefixdir" unless -d "$prefixdir";
  mkdir "$prefixdir/lib" unless -d "$prefixdir/lib";
  mkdir "$prefixdir/include" unless -d "$prefixdir/include";

  my %done;
  my $tecuname = 'gcc4';
  #my $tecuname = 'dllg4';
  my @basecmd = (qw[make -f ../tecmakewin.mak USE_NODEPEND=Yes], "TEC_UNAME=$tecuname");

  if(-d "$srcdir/im/src") {
    print STDERR "Gonna build 'im'\n";
    chdir "$srcdir/im/src";
    # some debug info
    $im_si = $self->run_output_std(@basecmd, 'sysinfo') if $self->notes('build_debug_info');    
    foreach my $t (@imtgs) {
      $done{"im:$t"} = $self->run_custom(@basecmd, "MF=$t");
      $success = 0 unless $done{"im:$t"};
    }
    copy($_, "$prefixdir/include/") foreach (glob("../include/*.h"));
    copy($_, "$prefixdir/lib/") foreach (glob("../lib/$tecuname/*"));
    chdir $self->base_dir();
  }

  if (-d "$srcdir/cd/src") {
    print STDERR "Gonna build 'cd'\n";
    chdir "$srcdir/cd/src";
    foreach my $t (@cdtgs) {
      $done{"cd:$t"} = $self->run_custom(@basecmd, "MF=$t");
      $success = 0 unless $done{"cd:$t"};
    }
    copy($_, "$prefixdir/include/") foreach (glob("../include/*.h"));
    copy($_, "$prefixdir/lib/") foreach (glob("../lib/$tecuname/*"));
    chdir $self->base_dir();
  }

  if (-d "$srcdir/iup") {
    print STDERR "Gonna build 'iup'\n";    
    foreach my $t (@iuptgs) {
      print STDERR "changing dir '$srcdir/iup/$t'\n";    
      chdir "$srcdir/iup/$t";
      $done{"iup:$t"} = $self->run_custom(@basecmd);
      $success = 0 unless $done{"iup:$t"};
      chdir $self->base_dir();
    }
    chdir "$srcdir/iup";
    copy($_, "$prefixdir/include/") foreach (glob("./include/*.h"));
    copy($_, "$prefixdir/lib/") foreach (glob("./lib/$tecuname/*"));
    chdir $self->base_dir();
  }

  print STDERR "Done: $done{$_} - $_\n" foreach (sort keys %done);
  $self->config_data('debug_done', \%done);
  $self->config_data('debug_si', $im_si);
  
  return $success;
}

sub get_make {
  # on cygwin always 'make'
  return 'make';
}

sub quote_literal {
    my ($self, $txt) = @_;
    $txt =~ s|'|'\\''|g;
    return "'$txt'";
}

1;
