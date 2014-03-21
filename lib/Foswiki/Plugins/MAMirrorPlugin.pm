# See bottom of file for default license and copyright information

=begin TML

---+ package Foswiki::Plugins::MAMirrorPlugin
=cut


package Foswiki::Plugins::MAMirrorPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version
use Archive::Tar;
# use File::Path qw ( remove_tree ); # Zu neu fuer HH
use File::Path qw ( rmtree );

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package.  Two version formats are supported:
#
# Recommended:  Dotted triplet.  Use "v1.2.3" format for releases,  and
# "v1.2.3_001" for "alpha" versions.  The v prefix is required.
# This format uses the "declare" format
#     use version; our $VERSION = version->declare("v1.2.0");
#
# Alternative:  Simple decimal version.   Use "1.2" format for releases, and
# "1.2_001" for "alpha" versions.  Do NOT use the "v" prefix.  This style
# is set either by using the "parse" method, or by a simple assignment.
#    use version; our $VERSION = version->parse("1.20_001");  OR
#    our $VERSION = "1.20_001";   # version->parse isn't really needed
#
# To convert from a decimal version to a dotted version, first normalize the
# decimal version, then increment it.
# perl -Mversion -e 'print version->parse("4.44")->normal'  ==>  v4.440.0
# In this example the next version would be v4.441.0.
#
# Note:  Alpha versions compare as numerically lower than the non-alpha version
# so the versions in ascending order are:
#   v1.2.1_001 -> v1.2.1 -> v1.2.2_001 -> v1.2.2
#
# These statements MUST be on the same line. See "perldoc version" for more
# information on version strings.
#use version; our $VERSION = version->declare("v1.0.0_001");
our $VERSION          = '1.1';

# $RELEASE is used in the "Find More Extensions" automation in configure.
# It is a manually maintained string used to identify functionality steps.
# You can use any of the following formats:
# tuple   - a sequence of integers separated by . e.g. 1.2.3. The numbers
#           usually refer to major.minor.patch release or similar. You can
#           use as many numbers as you like e.g. '1' or '1.2.3.4.5'.
# isodate - a date in ISO8601 format e.g. 2009-08-07
# date    - a date in 1 Jun 2009 format. Three letter English month names only.
# Note: it's important that this string is exactly the same in the extension
# topic - if you use %$RELEASE% with BuildContrib this is done automatically.
# It is preferred to keep this compatible with $VERSION. At some future
# date, Foswiki will deprecate RELEASE and use the VERSION string.
our $RELEASE = '1.1';

our $SHORTDESCRIPTION = 'Manage a local mirror for extensions.';

our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerRESTHandler( 'update', \&restUpdate );

    # Plugin correctly initialized
    return 1;
}

sub oops {
    my ( $mweb, $mtopic, $message, $status ) = @_;
    $status ||= 'Failed';
    my $url = Foswiki::Func::getScriptUrl(
        $mweb, $mtopic, 'oops',
        template => 'oopsgeneric',
        param1   => $status,
        param2   => $message
       );
    Foswiki::Func::redirectCgiQuery( undef, $url );
    return undef;
}

sub restUpdate {
    my ( $session, $subject, $verb, $response ) = @_;

    my $webtopic = $Foswiki::cfg{Extensions}{MAMirrorPlugin}{ExtensionsWeb} || 'Extensions';
    $webtopic .= '.';
    $webtopic .= $Foswiki::cfg{Extensions}{MAMirrorPlugin}{ManageMirrorTopic} || 'ManageMirror';
    my ($mweb, $mtopic) = Foswiki::Func::normalizeWebTopicName( '', $webtopic );
    return oops($mweb, $mtopic, "ManageMirrorTopic does not exist: '$mweb.$mtopic'") unless Foswiki::Func::topicExists( $mweb, $mtopic );

    my $eweb = $Foswiki::cfg{Extensions}{MAMirrorPlugin}{ExtensionsWeb} || 'Extensions';
    return oops($mweb, $mtopic, "Illegal ExtensionsWeb: '$eweb'") unless Foswiki::Func::isValidWebName( $eweb );
    return oops($mweb, $mtopic, "ExtensionsWeb does not exist: '$eweb'") unless Foswiki::Func::webExists( $eweb );

    my $wa = Foswiki::Func::getWorkArea("MAMirrorPlugin");

    # for reporting
    my @couldNotExtract = ();
    my @extracted = ();
    my @updated = ();
    my @skipped = ();

    return oops($mweb, $mtopic, "You must be an admin to do that!") unless Foswiki::Func::isAnAdmin();

    Foswiki::Func::writeWarning("Will now attempt to update mirror...");
    my ($meta, $text) = Foswiki::Func::readTopic( $mweb, $mtopic );
    my @attachments = $meta->find( 'FILEATTACHMENT' );
    foreach my $attachmentHash (@attachments) {
        my $attachment = $attachmentHash->{attachment};
        Foswiki::Func::writeWarning("processing $attachment");
        unless( $attachment =~ m/^[a-zA-Z_.0-9-]*\.tar$/ ) {
            push( @skipped, $attachment );
            next;
        }

        my $IhatePerl = rand;
        my $tmp = "$wa/$IhatePerl";
        $tmp =~ m#^([a-zA-Z_.0-9/-]*)$# or die; # XXX Foswiki::Sandbox::untaint...
        $tmp = $1;
        mkdir $tmp;
        chdir $tmp || die; # XXX Store old cwd?
        #Foswiki::Func::writeWarning("extracting to $tmp");

        # extract tar
        my $plugins = Archive::Tar->new();
        my $src = "$Foswiki::cfg{PubDir}/$mweb/$mtopic/$attachment";
        Foswiki::Func::writeWarning("Could not find source for $attachment at $src") unless ( -e $src );
        $src =~ m#^([a-zA-Z_.0-9/-]*)$# or die; # XXX Foswiki::Sandbox::untaint...
        $src = $1;
        Foswiki::Func::writeWarning("Now dealing with $src...");
        my $read = $plugins->read( $src, undef, {extract => 1} );
        #Foswiki::Func::writeWarning("read: $read");
        if ( $read ) {
            push( @extracted, $attachment );
            Foswiki::Func::writeWarning('ls');
            # update each plugin
            foreach my $installer ( <*_installer> ) {
                my $plugin = $installer;
                $plugin =~ s#_installer$##;
                my $plugintopic = "$plugin.txt";
                my $plugintar = "$plugin.tgz";

                Foswiki::Func::writeWarning("Updating $plugin");

                unless ( Foswiki::Func::isValidTopicName( $plugin, 1 ) ) {
                    Foswiki::Func::writeWarning("Not a valid topicname (skipping): $plugin");
                    next;
                }

                unless ( -e $plugintopic ) {
                    Foswiki::Func::writeWarning("No valid topic ($plugintopic) for plugin (skipping): $plugin");
                    next;
                }

                unless ( -e $plugintar ) {
                    Foswiki::Func::writeWarning("No valid tgz for plugin (skipping): $plugin");
                    next;
                }

                # plugin description
                open FILE, '<', $plugintopic;
                my $contents = join('', <FILE>);
                close FILE;
                my $meta = new Foswiki::Meta( $Foswiki::Plugins::SESSION, $mweb, $plugin, $contents );
                Foswiki::Func::saveTopic( $eweb, $plugin, $meta, $meta->text() );

                # attach stuff
                Foswiki::Func::saveAttachment( $eweb, $plugin, $installer, {file=>"$tmp/$installer"} );
                Foswiki::Func::saveAttachment( $eweb, $plugin, "$plugin.tgz", {file=>"$tmp/$plugintar"} );

                push( @updated, $plugin );
            }
        } else {
            push( @couldNotExtract, $attachment );
        }

        # cleanup
        # remove_tree( $tmp ); # Zu neu fuer HH
        rmtree( $tmp );
        Foswiki::Func::moveAttachment( $mweb, $mtopic, $attachment, $Foswiki::cfg{TrashWebName}, 'TrashAttachment', $attachment );
    }

    my $report = "Updated from '$mweb.$mtopic' to your ExtensionsWeb '$eweb'.";
    $report .= "\n\nThe following files could not be extracted (they have been moved to trash): ".join( ', ', @couldNotExtract ) if scalar @couldNotExtract;
    $report .= "\n\nThe following files were processed (and moved to trash): ".join( ', ', @extracted ) if scalar @extracted;
    $report .= "\n\nThe following files were ignored: ".join( ', ', @skipped ) if scalar @skipped;
    if( scalar @updated ) {
        $report .= "\n\nThe following plugins were updated: ".join( ', ', @updated );
    } else {
        $report .= "\n\nNo updates could be found!";
    }
    return oops( $mweb, $mtopic, $report , 'Operation finished!' );
}

=begin TML


1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: StephanOsthold

Copyright (C) 2008-2012 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
