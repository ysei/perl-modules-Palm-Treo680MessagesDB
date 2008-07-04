# $Id: Treo680MessagesDB.pm,v 1.3 2008/07/04 15:15:39 drhyde Exp $

package Palm::Treo680MessagesDB;

use strict;
use warnings;

use Palm::Raw();
use DateTime;
use Data::Hexdumper ();

use vars qw($VERSION @ISA $timezone $incl_raw $debug);

$VERSION = '1.1';
@ISA = qw(Palm::Raw);
$timezone = 'Europe/London';
$debug = 0;
$incl_raw = 0;

sub import {
    my $class = shift;
    my %opts = @_;
    $timezone = $opts{timezone} if(exists($opts{timezone}));
    $incl_raw = $opts{incl_raw} if(exists($opts{incl_raw}));
    $debug    = $opts{debug}    if(exists($opts{debug}));
    Palm::PDB::RegisterPDBHandlers(__PACKAGE__, [MsSt => 'MsDb']);
}

=head1 NAME

Palm::Treo680MessagesDB - Handler for Treo 680 SMS message databases

=head1 SYNOPSIS

    use Palm::PDB;
    use Palm::Treo680MessagesDB timezone => 'Europe/London';

    my $pdb = Palm::PDB->new();
    $pdb->Load("MessagesDB.pdb");
    print Dumper(@{$pdb->{records}})'

=head1 DESCRIPTION

This is a helper class for the Palm::PDB package, which parses the
database generated by a Treo 680 as a record of all your SMSes.

=head1 OPTIONS

You can set some global options when you 'use' the module:

=over

=item timezone

Defaults to 'Europe/London'.

=item incl_raw

Whether to include the raw binary blob of data in the parsed records.
Defaults to false.

=item debug

Include a hexadecimal dump of each record in the 'debug' field.
Defaults to false.  If this is set to 2, then you may also get some
extra warnings.

=back

=head1 METHODS

This class inherits from Palm::Raw, so has all of its methods.  The
folliwing are over-ridden, and differ from that in the parent class
thus:

=head2 ParseRecord

Returns data structures with the following keys:

=over

=item rawdata

The raw data blob passed to the method.  This is only present if the
incl_raw option is true.

=item date

The date of the message, if available, in YYYY-MM-DD format

=item time

The time of the message, if available, in HH:MM format

=item epoch or timestamp (it's available under both names)

The epoch time of the message, if available.  Note that because
the database doesn't
store the timezone, we assume 'Europe/London'.  If you want to change
that, then suppy a timezone option when you 'use' the module.

Internally, this uses the DateTime module.  In the case of
ambiguous times then it uses the latest UTC time.  For invalid
local times, the epoch is set to -1, an impossible number as it's
before Palm even existed.

Note that this is always the Unix epoch time.  See L<DateTime> for
details of what this means.

=item name

The name of the other party, which the Treo extracts from the SIM
phone-book or from the Palm address book at the time the SMS is saved.

=item number or phone

The number of the other party.  This is not normalised so you might see
the same number in different formats, eg 07979866975 and +447979866975.
I may add number normalisation in the future.

=item direction

Either 'incoming', or 'outgoing'.

=back

Other fields may be added in the future.

=cut

sub ParseRecord {
    my $self = shift;
    my %record = @_;

    my $buf = $record{rawdata} = delete($record{data});

    my $type = 256 * ord(substr($buf, 10, 1)) + ord(substr($buf, 11, 1));
    my($dir, $num, $name, $msg) = ('', '', '', '');
    if($type == 0x400C || $type == 0x4009) { # 4009 not used by 680?
        $dir = ($type == 0x400C) ? 'inbound' : 'outbound';

	($num  = substr($buf, 0x22)) =~ s/\00.*//s;

	$name = substr($buf, length($num) + 1 + 0x22);
	$name =~ /^([^\00]*?)\00+(.*)$/s;
	($name, my $trailer) = ($1, $2);
	# $trailer =~ s/^\00+//;
	$record{unknown_before_msg} = Data::Hexdumper::hexdump(data => substr($trailer, 0, 4));
	($msg = substr($trailer, 4)) =~ s/\00.*//s;

	$record{unknown_after_message} = Data::Hexdumper::hexdump(data => substr($trailer, 4 + length($msg) + 1, 2));

	my $epoch = substr($trailer, 4 + length($msg) + 1 + 2, 4);
	$record{unknown_after_timestamp} = Data::Hexdumper::hexdump(data => substr($trailer, 4 + length($msg) + 1 + 2 + 4));

        $record{epoch} = $epoch =
	         0x1000000 * ord(substr($epoch, 0, 1)) +
	         0x10000   * ord(substr($epoch, 1, 1)) +
                 0x100     * ord(substr($epoch, 2, 1)) +
	                     ord(substr($epoch, 3, 1)) -
	         2082844800; # offset from Palm epoch (1904) to Unix
        my $dt = DateTime->from_epoch(
	    epoch => $epoch,
	    time_zone => $timezone
	);
	$record{date} = sprintf('%04d-%02d-%02d', $dt->year(), $dt->month(), $dt->day());
	$record{time} = sprintf('%02d:%02d', $dt->hour(), $dt->minute());
    } elsif($type == 0) {
        $dir = 'outbound';
        ($num, $name, $msg) = split(/\00+/, substr($buf, 0x4C), 3);
        $msg =~ s/^.{9}//s;
        $msg =~ s/\00.*$//s;

    } elsif($type == 0x0002) {
        $dir = 'outbound';
        ($num, $name, $msg) = split(/\00+/, substr($buf, 0x46), 3);
        $msg =~ s/^.Trsm....//s;
        $msg =~ s/\00.*$//s;
    } else {
        $type = 'unknown';
    }
    delete $record{rawdata} unless($incl_raw);
    $record{debug} = "\n".Data::Hexdumper::hexdump(data => $buf) if($debug);
    $record{device}    = 'Treo 680';
    $record{direction} = $dir;  # inbound or outbound
    $record{phone}     = $record{number} = $num;
    $record{timestamp} = $record{epoch};
    $record{name}      = $name;
    $record{text}      = $msg;
    $record{type}      = $type eq 'unknown' ? $type : sprintf('0x%04X', $type);
    return \%record;
}

=head1 LIMITATIONS

The message format is undocumented.  Consequently it has had to be
reverse-engineered.  There appear to be several message formats in
the database, not all of which are handled.

There is currently no support for creating a new database, or for
editing the contents of an existing database.  If you need that
functionality, please submit a patch with tests.  I will *not* write
this myself unless I need it.

Behaviour if you try to create or edit a database is currently
undefined.

=head1 BUGS and FEEDBACK

I can only reverse-engineer record formats that appear on my phone, so
there may be some missing.  In addition, I may decode some formats
incorrectly because they're not quite what I thought they were.

If you find any bugs please report them either using
L<http://rt.cpan.org/> or by email.  Ideally, I would like to receive a
sample database and a test file, which fails with the latest version of
the module but will pass when I fix the bug.

=head1 SEE ALSO

L<Palm::SMS>, which handles SMS messages databases on some other models
of Treo, and includes very basic Treo 680 support.

L<Palm::PDB>

L<DateTime>

=head1 AUTHOR

David Cantrell E<lt>F<david@cantrell.org.uk>E<gt>

=head1 AUTHOR, COPYRIGHT and LICENCE

Copyright 2008 David Cantrell E<lt>david@cantrell.org.ukE<gt>

This software is free-as-in-speech software, and may be used,
distributed, and modified under the terms of either the GNU
General Public Licence version 2 or the Artistic Licence. It's
up to you which one you use. The full text of the licences can
be found in the files GPL2.txt and ARTISTIC.txt, respectively.

=head1 CONSPIRACY

This module is also free-as-in-mason software.

=cut

1;
