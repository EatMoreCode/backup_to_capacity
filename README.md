# NAME

backup\_to\_capacity.pl - Backup recent files, up to a capacity

# SYNOPSIS

backup\_to\_capacity.pl \[options\]

    Options:
      --help             brief help message
      --src <dirname>    source directory
      --dst <dirname>    destination directory
      --capacity <bytes> amount of capacity available at destination
      --quiet            shhh!
      --dry-run          don't do anything, just pretend

# OPTIONS

- **--help**

    Print this help information

- **--src**

    The source directory for the files to be backed up.

- **--dst**

    The destination directory for the files to be backed up to. This
    directory must exist.

    Note that any contents in this directory will be deleted and replaced
    with the files from the source (up to the capacity).

- **--capacity**

    This amount of data to store in the destination directory. Can be specified
    as either bytes, or suffixed with M or G to specify megabytes or gigabytes.

    The amount specified will not always be less than the amount actually used
    by the backup, because of file and directory overheads. You may want to allow
    some slack. Anecdotal evidence suggests that for sources with many files, this
    overhead could be 10% or higher.

- **--dry-run**

    Do everything except the actual sync. Will run rsync in dry run mode as well,
    so a lot of output will be produced, though no changes will occur.

- **--quiet**

    Don't produce any output.

# DESCRIPTION

This program will backup files from a source to a destination directory using
rsync, but only up to a certain capacity. The files are evaluated based on their
modification date. The outcome is a backup with a fixed size, containing the
most recently modified files from the source, excluding older files if the capacity
is less than the source size.

When first preparing to use this script, it is recommended you use **--dry-run** mode!
rsync (and thus this script) has no regard for the existing contents of the
destination directory - everything there will be replaced with a backup of your source.
Use the **--dry-run** mode and examine the output carefully to ensure you are using the
correct parameters.

# EXAMPLE

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

# NOTES

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
