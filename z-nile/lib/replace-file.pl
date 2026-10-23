#!/usr/bin/perl
# Replaces the file at <dest> with new content, never writing through whatever is there (c0077).
#   perl z-nile/lib/replace-file.pl <dest> [<src>]     # content from <src> (bytes), else from stdin
# A sibling temporary file is created exclusively and without following links (O_CREAT|O_EXCL|O_NOFOLLOW), written,
# then rename(2)d onto <dest>. A rename replaces a link of any kind (to a file or to a directory) instead of
# following it, and refuses a real directory. On any failure the temporary file is removed. Every unjailed writer
# under .cache uses this (or, in z-nile/lib/fence.sh, an inline rename): a spec may have swapped a link in there.
use strict;
use warnings;
use Fcntl qw(O_WRONLY O_CREAT O_EXCL O_NOFOLLOW);
use File::Basename qw(dirname basename);

my ($dest, $src) = @ARGV;
die "usage: replace-file.pl <dest> [<src>]\n" unless defined $dest && $dest ne '';
if (-d $dest && !-l $dest) {
    print STDERR "replace-file: $dest is a directory; refusing\n";
    exit 1;
}

my $tmp;
sub fail {
    my ($why) = @_;
    unlink $tmp if defined $tmp;
    print STDERR "replace-file: $dest: $why\n";
    exit 1;
}

# the temporary file: next to <dest> (so the rename stays on one filesystem), created exclusively, never followed
my ($dir, $base) = (dirname($dest), basename($dest));
my @letters = ('a' .. 'z', '0' .. '9');
my $out;
for my $try (1 .. 5) {
    my $name = "$dir/.$base.pickman-tmp.$$." . join('', map { $letters[rand @letters] } 1 .. 6);
    if (sysopen($out, $name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644)) {
        $tmp = $name;
        last;
    }
    fail("$!") unless $!{EEXIST};
}
fail("no free temporary name") unless defined $tmp;
chmod 0644, $tmp or fail("chmod: $!"); # against the umask
binmode $out;

my $in;
if (defined $src) {
    open($in, '<', $src) or fail("$src: $!");
} else {
    $in = \*STDIN;
}
binmode $in;
while (1) {
    my $n = sysread($in, my $buf, 65536);
    fail(defined $src ? "$src: $!" : "stdin: $!") unless defined $n;
    last if $n == 0;
    my $off = 0;
    while ($off < $n) {
        my $w = syswrite($out, $buf, $n - $off, $off);
        fail("write: $!") unless defined $w;
        $off += $w;
    }
}
close $in if defined $src;
close $out or fail("close: $!");
rename $tmp, $dest or fail("$!");
exit 0;
