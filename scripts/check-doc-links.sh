#!/bin/zsh
# Lists relative links and images in the Markdown files that point to nothing.
# usage: scripts/check-doc-links.sh        (exit 1 if any are broken)
cd "$(dirname "$0")/.." || exit 1
perl -e '
use strict; use File::Basename;
my @files = (glob("*.md"), split /\n/, `find docs -name "*.md" -not -path "docs/design/source/*"`);
my $bad = 0;
for my $f (@files) {
  open my $h, "<:utf8", $f or next; local $/; my $s = <$h>; close $h;
  $s =~ s/<!--.*?-->//gs;
  $s =~ s/```.*?```//gs;
  while ($s =~ /\]\(([^)\s]+)\)/g) {
    my $t = $1; next if $t =~ m{^(https?:|mailto:|#)};
    $t =~ s/#.*$//; next if $t eq "";
    my $p = dirname($f) . "/" . $t;
    unless (-e $p) { print "$f -> $t\n"; $bad++ }
  }
  while ($s =~ /src="([^"]+)"/g) {
    my $t = $1; next if $t =~ m{^https?:};
    my $p = dirname($f) . "/" . $t;
    unless (-e $p) { print "$f (img) -> $t\n"; $bad++ }
  }
}
print $bad ? "$bad broken link(s)\n" : "All relative links resolve.\n";
exit($bad ? 1 : 0);
'
