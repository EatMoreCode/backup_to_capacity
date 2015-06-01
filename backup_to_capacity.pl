#!/usr/bin/env perl

# backup recently modified files, up to a capacity

# for documentation, either run perldoc on this script, use the --help
# command line option, or scroll to the bottom and read the POD

# should run on any perl > 5.8 - there are no non core dependancies

# runs rsync with --delete, improper use or bugs may be harmful to your data!
# all responsibility lies with you, dear user

use strict;
use warnings;

use File::Find   qw//;
use File::Temp   qw/tempfile/;
use Cwd          qw/abs_path/;
use POSIX        qw/strftime/;
use Pod::Usage   qw/pod2usage/;
use Getopt::Long qw/GetOptions/;

my ($src, $dst);
my $capacity;

my $dry_run = 0;
my $quiet   = 0;
my $help    = 0;

my $MB = 1024 * 1024;
my $GB =  $MB * 1024;

GetOptions ("src=s",      \$src,
            "dst=s",      \$dst,
            "dry-run",    \$dry_run,
            "quiet",      \$quiet,
            "help",       \$help,
            "capacity=s", \$capacity)
  or pod2usage("error: bad command line arguments - try --help");

pod2usage(-verbose => 2) if ($help);

# Convert to absolute paths to avoid all relative nastiness
$src = abs_path($src) if $src;
$dst = abs_path($dst) if $dst;

my @cmd_errors;

# Check arguments and sanity check paths
push @cmd_errors, "error: bad or missing --src parameter"       unless $src && -d $src;
push @cmd_errors, "error: bad or missing --dst parameter"       unless $dst && -d $dst;
push @cmd_errors, "error: --src and --dst are the same place!" if ($src && $dst && $src eq $dst);

# Convert GB and MB values
if ($capacity && $capacity =~ s/^(\d+)g$/$1/i) { $capacity *= $GB }
if ($capacity && $capacity =~ s/^(\d+)m$/$1/i) { $capacity *= $MB }

push @cmd_errors, "error: bad or missing --capacity parameter"  if (! $capacity || $capacity !~ /^\d+$/);

if (@cmd_errors) {
  pod2usage(-message => join("\n", @cmd_errors));
}

chdir $src || die "can't chdir to $src: $!\n";

_log("rsyncing files");
_log("from: $src");
_log("to:   $dst");
_log(sprintf "with capacity:  %15s bytes", commify($capacity));

# Generate file exclusion list
my $files = excluded_file_list($src, $capacity);

# Sync source to destination, with exclusions
sync_with_exclusions($src, $dst, $files);

_log("complete");
exit;

sub excluded_file_list {
  my $src            = shift;
  my $capacity       = shift;
  
  my $complete_list  = [];
  my $bytes_to_send  = 0;
  my $bytes_skipped  = 0;
  my $included_files = 0;
  my $scan_count     = 0;

  # Find All The Files!
  File::Find::find({no_chdir => 1,
                    wanted   => sub {
                      if (-f $_) {
                        push @$complete_list, $_;
                        $scan_count++;
                        _log("scanned " . commify($scan_count) . " files")
                          unless ($scan_count % 10000);
                      }
                    },
                   },
                   '.');

  # Remove the leading ./ because it confuses rsync
  s{^./}{} foreach @$complete_list;

  # Sort by last modified date, newest first
  my $sorted_list = [ sort { (stat($b))[9] <=> (stat($a))[9] } @$complete_list ];

  # Skip over files until we hit capacity, then record the rest as exclusions
  my $final_list = [];
  foreach my $file (@$sorted_list) {
    my $size = (stat($file))[7];
    if ( $size <= $capacity ) {
      # These are actually files we will NOT exclude, so we just record
      # the capacity reduction
      $capacity -= $size;
      $bytes_to_send += $size;
      $included_files++;
      next;
    }
    else {
      # Out of capacity, stop trying - everything from now on
      # is a file to exclude
      $capacity = 0;
      $bytes_skipped += $size;
      push @$final_list, $file;
      next;
    }
  }

  _log(sprintf "including: %15s bytes (%9s files)", commify($bytes_to_send), commify($included_files));
  _log(sprintf "excluding: %15s bytes (%9s files)", commify($bytes_skipped), commify(scalar @$final_list));

  return $final_list;
}

sub sync_with_exclusions {
  my $src  = shift;
  my $dst  = shift;
  my $list = shift;

  # Create the list for rsync
  # Null separated of course to correctly handle any filename
  my ($fh, $filename) = tempfile();
  print $fh join("\0", @$list);
  close $fh;

  # Construct the rsync command
  my @command = qw/rsync -0 --delete --delete-excluded -a -h -m /;

  push @command, qw/--progress -v/ unless $quiet;
  push @command, '--dry-run'       if $dry_run;

  # Add our exclusion list
  push @command, '--exclude-from', $filename;

  # Source and Destination are the final parameters
  # we have chdird, so src is here in .
  push @command, '.', $dst;

  _log("Running rsync in dry run mode: " . join(' ', @command)) if ($dry_run);
  system @command;

  _log("ERROR: rsync returned: $? - consult output above for details") if ($?);

  unlink $filename;

}

# Log things to the screen, plus timestamp
sub _log {
  return if ($quiet);
  my $msg = shift;
  my $now_string = strftime "%a %b %e %H:%M:%S %Y", localtime;
  printf("%-25s %-s\n", $now_string, $msg);
}

# Print numbers, nicely
sub commify {
  local $_  = shift;
  1 while s/^(-?\d+)(\d{3})/$1,$2/;
  return $_;
}

__END__

=head1 NAME

backup_to_capacity.pl - Backup recent files, up to a capacity

=head1 SYNOPSIS

backup_to_capacity.pl [options]

 Options:
   --help             brief help message
   --src <dirname>    source directory
   --dst <dirname>    destination directory
   --capacity <bytes> amount of capacity available at destination
   --quiet            shhh!
   --dry-run          don't do anything, just pretend

=head1 OPTIONS

=over 4

=item B<--help>

Print this help information

=item B<--src>

The source directory for the files to be backed up.

=item B<--dst>

The destination directory for the files to be backed up to. This
directory must exist.

Note that any contents in this directory will be deleted and replaced
with the files from the source (up to the capacity).

=item B<--capacity>

This amount of data to store in the destination directory. Can be specified
as either bytes, or suffixed with M or G to specify megabytes or gigabytes.

The amount specified will not always be less than the amount actually used
by the backup, because of file and directory overheads. You may want to allow
some slack. Anecdotal evidence suggests that for sources with many files, this
overhead could be 10% or higher.

=item B<--dry-run>

Do everything except the actual sync. Will run rsync in dry run mode as well,
so a lot of output will be produced, though no changes will occur.

=item B<--quiet>

Don't produce any output.

=back

=head1 DESCRIPTION

This program will backup files from a source to a destination directory using
rsync, but only up to a certain capacity. The files are evaluated based on their
modification date. The outcome is a backup with a fixed size, containing the
most recently modified files from the source, excluding older files if the capacity
is less than the source size.

When first preparing to use this script, it is recommended you use B<--dry-run> mode!
rsync (and thus this script) has no regard for the existing contents of the
destination directory - everything there will be replaced with a backup of your source.
Use the B<--dry-run> mode and examine the output carefully to ensure you are using the
correct parameters.

=head1 EXAMPLE

  backup_to_capacity.pl --src Documents --dst /var/tmp/backup --capacity 100M

Backup up to 100M of my most recently modified Documents to /var/tmp/backup.

Output:

  Fri May  8 13:14:04 2015  from: /Users/username/Documents
  Fri May  8 13:14:04 2015  to:   /private/var/tmp/backup
  Fri May  8 13:14:04 2015  capacity:      104,857,600 bytes
  Fri May  8 13:14:04 2015  scanned 10,000 files
  Fri May  8 13:14:04 2015  scanned 20,000 files
  Fri May  8 13:14:05 2015  including:     104,818,722 bytes (    9,058 files)
  Fri May  8 13:14:05 2015  excluding:     252,943,315 bytes (   13,550 files)
  building file list ...
  13328 files to consider

  sent 251.89K bytes  received 20 bytes  29.64K bytes/sec
  total size is 104.82M  speedup is 416.09
  Fri May  8 13:14:16 2015  complete

=head1 NOTES

The implementation uses rsync's ability to exclude files from a sync. If you have a
large source directory, a small capacity and a lot of files, the exclude list will be
very large. This is quite slow for rsync to process.

This script does not try to detect if the source or destination are inside one another.
If you do that, something bad will probably happen. Don't do that.

Files are considered in most-recently-modified-first order. As soon as the capacity is
exceeded, no further files will be included for backup. This means that if the 'n'th
file is 5Mb, and would exceed the capacity, the 'n+1'th file would not be added, even 
if it would fit. This is to avoid surprises like "why was file Y included and X was not, 
even though X is newer".

=cut
