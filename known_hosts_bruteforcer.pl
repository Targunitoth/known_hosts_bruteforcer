#!/usr/bin/perl
#
# SSH known_hosts file bruteforcer
#
# v1.0 - Xavier Mertens <xavier(at)rootshell(dot)be>
# v1.1 - Targunitoth
#
# This Perl script read a SSH known_host file containing hashed hosts and try to find hostnames
# or IP addresses
#
# 20101103 : Created
# 20200101 : Update
#
# Todo
# ----
# - Support for IPv6 addresses
# - Increase performances
#

use Getopt::Std;
use Digest::HMAC_SHA1;
use MIME::Base64;
use Path::Tiny;
use Net::IP;
#use strict;
#use warnings;

my $MAXLEN = 8;				# Maximum hostnames length to check
my $MAXIP  = 4294967296; # 2^32		# The whole IPv4 space

my @saltStr   = ();
my @base64Str = ();
my $idx       = 0;

my %options = ();
# Process the arguments
getopts("d:f:l:s:w:ivh", \%options);

# Some help is sometimes useful
if ($options{h} || !%options) {
	print <<EOF;
Usage: known_hosts_bruteforcer.pl [options]

  -d <domain>   Specify a domain name to append to hostnames (default: none)
  -f <file>     Specify the known_hosts file to bruteforce (default: $HOME/.ssh/known_hosts)
  -i            Bruteforce IP addresses (default: hostnames)
  -l <integer>  Specify the hostname maximum length (default: 8)
  -s <string>   Specify an initial IP address or password (default: none)
  -v            Verbose output
  -w		Specify wordlist
  -h            Print this help, then exit
EOF
	exit;
}

# SSH Keyfile to process (default: $HOME/.ssh/known_hosts)
$knownhostFile = ($options{f} ne "") ? $options{f} : $ENV{HOME} . "/.ssh/known_hosts";
if (! -r $knownhostFile) {
	print STDERR "Cannot read file $knownhostFile ...\n";
	exit 1;
}

# Max password length (default: 8)
$passwordLen = ($options{l} ne "") ? $options{l} : $MAXLEN;
if ($passwordLen < 1 || $passwordLen > 30) {
	print STDERR "Invalid maximum password length: $passwordLen ...\n";
	exit 1;
}

# Domain name to append
$domainName = $options{d};

# Verbose mode
$verbose = ($options{v}) ? 1 : 0;

# Wordlist mode
$wordlist = ($options{w}) ? 1 : 0;
$wordlistlen = 0;
if($wordlist) {
	open(my $fh, '<:encoding(UTF-8)', $options{w}) or die "Could not open file '$options{w}' $!";
	while(my $line = <$fh>){
		$wordlistlen++;
	}
	#exit 0;
}



# IP address mode
$ipMode = ($options{i}) ? 1 : 0;

# Starting IP or password?
# To increase the speed of run the script across multiple computers,
# an initial hostname or IP address can be given
$initialStr = $options{s};

# First read the known_hosts file and populate the lists
# Only hashed hosts are processed
($verbose) && print STDERR "Reading hashes from $knownhostFile ...\n";
open(HOSTFILE, "$knownhostFile") || die "Cannot open $knownhostFile";
while(<HOSTFILE>) {
	($hostHash, $keyType, $publicKey) = split(/ /);
	if ($hostHash =~ m/\|1\|/) {
		($dummy, $one, $saltStr[$idx], $base64Str[$idx]) = split(/\|/, $hostHash);
		$idx++;
	}
}
close(HOSTFILE);

	

# ---------
# Main Loop
# ---------

$loops=0;
while(1) {
	if ($ipMode) {
		# Generate an IP address using the main loop counter
		# Don't go beyond the IPv4 scope (2^32 addresses)
		if ($loops > $MAXIP) {
			print "Done.\n";
			exit 0;
		}

		# If we have an initial IP, check the syntax and use it
		if ($initialStr ne "") {
			my $ip = new Net::IP($initialStr);
			$initialIP = $ip->intip();
		}
		else {
			$initialIP = 0;
		}
		$tmpHost = sprintf("%vd", pack("N", $loops + $initialIP));
	}
	else {
		# Generate a temporary hostname (starting with an initial value if provided)
		if ($wordlist){
			#chomp $tmpHost; 
			if($loops == $wordlistlen) {
				print "Done.\n";
				exit 0;
			}
			(my @tmp) = path($options{w})->lines;
			$tmpHost = @tmp[$loops];
			($verbose) && printf("Testing: %s", $tmpHost); 
		}
		else{
			$tmpHost = generateHostname($initialStr);
		
			if (length($tmpHost) > $passwordLen) {
				print "Done.\n";
				exit 0;
			}
		}

		# Append the domain name if provided
		if ($domainName) {
			$tmpHost = $tmpHost . "." . $domainName;
		}
	}

	# In verbose mode, display a line every 1000 attempts
	($verbose) && (($loops % 1000) == 0) && print STDERR "Testing: $tmpHost ($loops probes) ...\n";
	
	if ($line = searchHash($tmpHost)) {
		printf("*** Found host: %s (line %d) ***\n", $tmpHost, $line + 1);
	}

	$loops++;
}

#
# Generate SHA1 hashes of a hostname/IP and compare it to the available hashes
# Returns the line index of the initial known_hosts file
#
sub searchHash() {
	$host = shift;
	($host) || return 0;

	# Process the list containing our hashes
	# For each one, generate a new hash and compare it
	for ($i = 0; $i < scalar(@saltStr); $i++) {
		$decoded = decode_base64($saltStr[$i]);
		$hmac = Digest::HMAC_SHA1->new($decoded);
		$hmac->add($host);
		$digest = $hmac->b64digest;
		$digest .= "="; # Quick fix ;-)
		if ($digest eq $base64Str[$i]) {
			return $i;
		}
	}
	return 0;
}

#
# Generate a hostname based on a given set of allowed caracters
# This sub-routine is based on:
# bruteforce 0.01 alpha
# Written by Tony Bhimani
# (C) Copyright 2004
# http://www.xenocafe.com
#

sub generateHostname {
	$initialPwd = shift;

	$alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-";
	@tmpPwd = ();
	$firstChar = substr($alphabet, 0, 1);
	$lastChar = substr($alphabet, length($alphabet)-1, 1);

	# If an initial password is provided, start with this one
	if ($initialPwd ne "" && $currentPwd eq "") {
		$currentPwd = $initialPwd;
		return $currentPwd;
	}

	# No password so start with the first character in our alphabet
	if ($currentPwd eq "") {
		$currentPwd= $firstChar;
		return $currentPwd;
	}

	# If the current password is all of the last character in the alphabet
	# then reset it with the first character of the alphabet plus 1 length greater
	if ($currentPwd eq fillString(length($currentPwd), $lastChar)) {
 		$currentPwd = fillString(length($currentPwd) + 1, $firstChar);
		return $currentPwd;
	}
  
	# Convert the password to an array
	@tmpPwd = split(//, $currentPwd);
  
	# Get the length of the password - 1 (zero based index)
	$x = @tmpPwd - 1;

	# This portion adjusts the characters
	# We go through the array starting with the end of the array and work our way backwords
	# if the character is the last one in the alphabet, we change it to the first character
	# then move to the next array character
	# if we aren't looking at the last alphabet character then we change the array character
	# to the next higher value and exit the loop
	while (1) {
		$iTemp = getPos($alphabet, $tmpPwd[$x]);
  
		if ($iTemp == getPos($alphabet, $lastChar)) {
			@tmpPwd[$x] = $firstChar;
			$x--;
		} else {
			@tmpPwd[$x] = substr($alphabet, $iTemp + 1, 1);
			last;
		}
	}
  
	# Convert the array back into a string and return the new password to try
	$currentPwd = join("", @tmpPwd);
    
	return $currentPwd;
}

#
# Fill a string with the same caracter
#

sub fillString {
	my ($len, $char) = (shift, shift);
	$str = "";
	for ($i=0; $i<$len; $i++) {
		$str .= $char;
	}
	return $str;
}

#
# Return the position of a caracter in a string
#

sub getPos {
	my ($alphabet, $char) = (shift, shift);
	for ($i=0; $i<length($alphabet); $i++) {
		if ($char eq substr($alphabet, $i, 1)) {
			return $i;
		}
	}
}

# Eof
