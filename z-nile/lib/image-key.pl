#!/usr/bin/perl
# The content key of a fixture image (c0178): one digest of what the image is built from.
#   perl z-nile/lib/image-key.pl <root> [<path>...] [--skip <path>]... [--also <file>]... [--salt <text>]
# Walks each <path> (a file or a folder, relative to <root>) and hashes every entry's relative path, whether a file is
# executable, and its bytes; a symlink is hashed by its target text and never followed; a <path> that does not exist
# is an error naming it. A path given after --skip, relative to <root>, is left out with everything under it.
# Each --also file (an absolute path: the harness code that builds the image) is hashed by its bytes alone, and each
# --salt text (something else the image depends on, such as a commit) by itself. Prints one
# 40-hex digest and writes nothing. Exits 1, naming the path, on anything it cannot read.
use strict;
use warnings;
use Digest::SHA;

my $root = shift @ARGV;
die "usage: image-key.pl <root> [<path>...] [--skip <path>]... [--also <file>]... [--salt <text>]\n" unless defined $root && @ARGV;
my (@paths, @also, @salt, %skip);
while (@ARGV) {
    my $a = shift @ARGV;
    if ($a eq '--skip' || $a eq '--also' || $a eq '--salt') {
        my $v = shift @ARGV;
        die "image-key: $a needs a value\n" unless defined $v;
        if ($a eq '--skip') { $skip{$v} = 1 } elsif ($a eq '--also') { push @also, $v } else { push @salt, $v }
    } else {
        push @paths, $a;
    }
}
my $all = Digest::SHA->new(1);
sub file_digest {
    my ($abs) = @_;
    open(my $fh, '<:raw', $abs) or die "image-key: $abs: $!\n";
    my $d = Digest::SHA->new(1);
    $d->addfile($fh);
    close $fh;
    return $d->hexdigest;
}
sub add {
    my ($rel) = @_;
    return if $skip{$rel};
    my $abs = "$root/$rel";
    if (-l $abs) {
        $all->add("L $rel -> " . readlink($abs) . "\n");
    } elsif (-d $abs) {
        opendir(my $dh, $abs) or die "image-key: $abs: $!\n";
        my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
        closedir $dh;
        $all->add("D $rel\n");
        add("$rel/$_") for @names;
    } elsif (-f $abs) {
        $all->add("F $rel " . (-x $abs ? "x" : "-") . " " . file_digest($abs) . "\n");
    } else {
        die "image-key: $abs: not found\n";
    }
}
add($_) for @paths;
$all->add("C " . file_digest($_) . "\n") for @also;
$all->add("S $_\n") for @salt;
print $all->hexdigest, "\n";
