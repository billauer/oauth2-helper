#!/usr/bin/perl
use warnings;
use strict;

# See http://billauer.co.il/blog/2022/10/git-send-email-with-oauth2-gmail/
# for how to use this script.

use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use JSON;

my $reftokenfile = "$ENV{HOME}/.oauth2_reftoken";
my $acctokenfile = "$ENV{HOME}/.oauth2_acctoken";

# These three parameters are taken from Thunderbird's OAuth2Providers.jsm
my $tokenserver = 'https://www.googleapis.com/oauth2/v3/token';
my $client_id = '406964657835-aq8lmia8j95dhl1a2bvharmfk3t1hgqj.apps.googleusercontent.com';
my $client_secret = 'kSmqreRr0qwBWJgbf5Y-PjSU';

###########################################################

if (open(my $fd, "<", $acctokenfile)) {
  my $line = <$fd>;
  close $fd;

  my ($expiry, $token) = ($line =~ /^(\d+):([^\n\r]+)/);
  if (defined $expiry) {
    if ($expiry > time()) {
      print STDERR "Using cached access token in $acctokenfile\n";
      print $token;
      exit 0;
    }
  } else {
    warn("$acctokenfile exists, but was ignored as it's poorly formatted\n");
  }
}

open(my $fd, "<", $reftokenfile) or
  die("Failed to open $reftokenfile: $!\n\n".helptext());
my $refresh_token = <$fd>;
close $fd;

$refresh_token =~ s/[ \t\n\r]*//g;

die("No data in $reftokenfile\n\n".helptext())
  unless ($refresh_token);

print STDERR "Fetching access token based upon refresh token in $reftokenfile...\n";

my $ua = LWP::UserAgent->new;
my $req = POST $tokenserver,
  [
   'grant_type' => 'refresh_token',
   'client_id' => $client_id,
   'client_secret' => $client_secret,
   'refresh_token', $refresh_token,
  ];

my $res = $ua->request($req);

unless ($res->is_success) {
  print STDERR "\nFailed to obtain an access token. See transcript:\n";
  print STDERR $ua->request($req)->content;
  die "\nError: " . $res->status_line . "\n\nIf the error indicates an invalid refresh token (invalid_grant), do as follows:\n".helptext();
}

my $json = $res->content;
my $tree = decode_json($json);

# If "expires_in" doesn't appear in the answer, the access token has is
# valid forever. In theory. In reality, the server will reject it sooner or
# later. So default to a very short time, in order to avoid an authentication
# failure in the SMTP phase.

my $access_token = $tree->{access_token};
my $ttl = $tree->{expires_in} || 120;
my $new_refresh = $tree->{refresh_token};

unless (defined $access_token) {
  print STDERR "Huh? A proper response should offer \"access_token\".\n";
  print STDERR "Instead, I got just this:\n\n$json\n";
  die("Something is seriously wrong. Aborting.\n");
}

if (defined $new_refresh) {
  print STDERR << "END";
**************************************************************************

IMPORTANT: The token server returned a refresh token:

$new_refresh

Update the password in Thunderbird as well as $reftokenfile
with this, or subsequent attempts to log in will fail. Alternatively,
attempt to send a mail through the server in Thunderbird, which is likely
to require a renewed login to the account in a browser window.

Note that this came with an access token as well, so it's still possible
to send emails in the next $ttl seconds.

**************************************************************************
END
}

my $expiry = time() + $ttl - 30; # 30 seconds room for Internet delays

umask 0077; # Create file accessible by user only

if (open (my $out, ">", $acctokenfile)) {
  print $out "$expiry:$access_token\n";
  close $out;
} else {
  warn("Failed to open $acctokenfile for write, access token is hence not saved:\n$!\n");
}

print $access_token; # This is the whole purpose of this script

exit 0;

#######################################################################

sub helptext {
  return << "TEXT";
First, make sure that Thunderbird has access to the mail account itself,
possibly by attempting to send an email through the relevant server.
Then go to Thunderbird's Preferences > Privacy & Security and click on Saved
Passwords. Look for the account, where the Provider start with oauth://.
Right click that line and choose "Copy Password". Paste that blob into
$reftokenfile (instead of what it is now).

Note that access to this file gives anyone full access to your email account.
To mitigate this inherent security risk, change its permissions to 0600.
TEXT
}
