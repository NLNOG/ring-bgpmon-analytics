package BGPmon::Filter;
use strict;
use warnings;
use constant FALSE => 0;
use constant TRUE => 1;
use BGPmon::Translator::XFB2PerlHash;
use BGPmon::Filter::Prefix;
use Net::IP;
use Regexp::IPv6 qw($IPv6_re);


BEGIN{
	require Exporter;
	our $VERSION = '1.06';
	our $AUTOLOAD;
	our @ISA = qw(Exporter);
	our @EXPORT_OK = qw(init parse_xml_msg parse_config_file parse_config_db_result toString reset get_error_msg get_error_code matches printFilters);
}


my $progName = $0;


# Variables to hold error codes and messages
my %error_code;
my %error_msg;
my @function_names = ('init', 'parse_config_file', 'parse_config_db_result', 'matches');

use constant NO_ERROR_CODE => 0;
use constant NO_ERROR_MSG => 'No Error. Relax with some tea.';

#Error codes for opening the configuration file.
use constant UNOPANABLE_CONFIG_FILE => 520;
use constant UNOPANABLE_CONFIG_FILE_MSG => 'Invalid filename given for config
file.';
#Error codes for parsing the configuration file.
use constant INVALID_IPV4_CONFIG => 530;
use constant INVALID_IPV4_CONFIG_MSG => "Invalid IPv4 given in config file.";
use constant INVALID_IPV6_CONFIG => 531;
use constant INVALID_IPV6_CONFIG_MSG => "Invalid IPv6 given in config file.";
use constant INVALID_AS_CONFIG => 532;
use constant INVALID_AS_CONFIG_MSG => "Invalid AS given in config file.";
use constant UNKNOWN_CONFIG => 533;
use constant UNKNOWN_CONFIG_MSG => "Invalid line in config file.";

#Error codes for parsing the XML file.
use constant NO_MSG_GIVEN => 540;
use constant NO_MSG_GIVEN_MSG => "No XML message was given.";

# Variables to hold the prefixes we'd like to filter
my @v6prefixes = ();
my @v4prefixes = ();
my @asNumbers = ();
my $prefixFilename;

# Variables to hold the prefixes we've found in the latest message that was parsed.
my @v4 = ();
my @v6 = ();
my @as = ();

# Variable to hold the AS_PATH
my $aspath;


=head1 NAME

BGPmon::Filter

This module provides information of if a BGP message matches a set of 
IPv4 or IPv6 prefixes, or if it matches a specific autonymous system number.
=cut

=head1 SYNOPSIS

use BGPmon::Filter;

if(BGPmon::Filter::init()){

	my $err_code = BGPmon::Filter::get_error_code('init');
	
	my $err_msg = BGPmon::Filter::get_error_msg('init');
	
	print "$err_code : $err_msg\n";
	
	exit 1;
}
if(BGPmon::Filter::parse_config_file('config_file.txt')){
	
	my $err_code = BGPmon::Filter::get_error_code('parse_config_file');
	
	my $err_msg = BGPmon::Filter::get_error_msg('parse_config_file');
	
	print "$err_code : $err_msg\n";
	
	exit 1;
}
my $xml4msg = '<BGP_MESSAGE length="00001140" version="0.4" xmlns="urn:ietf:pa

rams:xml:ns:xfb-0.4" type_value="2" type="UPDATE"><BGPMON_SEQ id="127893688" se

q_num="1541418969"/><TIME timestamp="1346459370" datetime="2012-09-01T00:29:30Z

" precision_time="0"/><PEERING as_num_len="2"><SRC_ADDR><ADDRESS>187.16.217.154

</ADDRESS><AFI value="1">IPV4</AFI></SRC_ADDR><SRC_PORT>179</SRC_PORT><SRC_AS>5

3175</SRC_AS><DST_ADDR><ADDRESS>200.160.6.217</ADDRESS><AFI value="1">IPV4</AFI

></DST_ADDR><DST_PORT>179</DST_PORT><DST_AS>6447</DST_AS><BGPID>0.0.0.0</BGPID>

</PEERING><ASCII_MSG length="31"><MARKER length="16">FFFFFFFFFFFFFFFFFFFFFFFFFF

FFFFFF</MARKER><UPDATE withdrawn_len="8" path_attr_len="0"><WITHDRAWN count="2"

><PREFIX label="WITH"><ADDRESS>150.196.29.0/24</ADDRESS><AFI value="1">IPV4

</AFI><SAFI value="1">UNICAST </SAFI></PREFIX><PREFIX label="WITH"><ADDRESS>

205.94.224.0/20</ADDRESS><AFI value="1">IPV4</AFI><SAFI value="1">UNICAST

</SAFI></PREFIX></WITHDRAWN><PATH_ATTRIBUTES count="0"/><NLRI count="0"/>

</UPDATE></ASCII_MSG><OCTET_MSG><OCTETS length="31">FFFFFFFFFFFFFFFFFFFFFFFFFFF

FFFFF001F0200081896C41D14CD5EE00000</OCTETS></OCTET_MSG></BGP_MESSAGE>';


if(BGPmon::Filter::matches($xml4msg)){
	
	print "Matches!\n";
	
	print BGPmon::Filter::toString(); #This will print out the parsed info

}

else{
	
	print "Does not match.\n";

}

=head1 EXPORT

init parse_xml_msg parse_config_file toString reset get_error_msg get_error_code matches printFilters



=head1 SUBROUTINES/METHODS

=head2 init

Will initilialize the module an its state variables.  This only needs
to be called once.

=cut
sub init{
	my $fname = 'init';

	$error_code{$fname} = NO_ERROR_CODE;
	$error_msg{$fname} = NO_ERROR_MSG;

	return 0;
}


=head2 reset

Resets the module's state values.

=cut
sub reset{
	my $fname = 'reset';

	foreach(@v6prefixes){
		$_ = undef;
	}
	foreach(@v4prefixes){
		$_ = undef;
	}
	foreach(@asNumbers){
		$_ = undef;
	}
	foreach(@v4){
		$_ = undef;
	}
	foreach(@v6){
		$_ = undef;
	}
	foreach(@as){
		$_ = undef;
	}
	@v4prefixes = ();
	@v6prefixes = ();
	@asNumbers = ();
	@v4 = ();
	@v6 = ();
	@as = ();


	$prefixFilename = undef;
	%error_code = ();
	%error_msg = ();

	$error_code{$fname} = NO_ERROR_CODE;
	$error_msg{$fname} = NO_ERROR_MSG;

	return 0;
}

=head2 get_error_msg

Will return the error message of the given function name.

Input:  A string that contains the function name where an error occured.

Output: The message which represents the error stored from that function.

=cut
sub get_error_msg{
	my $str = shift;
	my $fname = 'get_error_msg';
	my $toReturn = $error_msg{$str};
	return $toReturn;
}

=head2 get_error_code

Will return the error code of the given function name.

Input:  A string that represents the function name where an error occured.

Output: The code which represents the error stored from that function.

=cut
sub get_error_code{
	my $str = shift;
	my $fname = 'get_error_code';
	my $toReturn = $error_code{$str};
	return $toReturn;
}

#comment
#Will check to see if the string passed in is of proper IPv6 format.
#cut
sub is_IPv6{
	my $str = shift;
	my $fname = 'is_IPv6';
	if(!($str =~ /^$IPv6_re$/)){
		return FALSE;
	}
	return TRUE;
}




sub ipv4_chkip($) {
	my ($ip) = $_[0];
	return $ip if ($ip=~m/^0*([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])\.0*([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])\.0*([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])\.0*([1-9]?\d|1\d\d|2[0-4]\d|25[0-5])(\/[0-9]+)*$/);
	return;
}



=head2 parse_config_file

Will parse the wanted IPv4 and IPv6 prefixes from a configuration file as well
as any autonymous system numbers.  These will be stored until 
BGPmon::Filter::reset() is called.

Input: A string with the location of the configuration file to parse

Output: 0 if there is no error
        1 if an error occured


=cut
sub parse_config_file{
	$prefixFilename = shift;
	my $fname = 'parse_config_file';
	my $file;
	my $lineNum = 0;
	if(!open($file, $prefixFilename)){
		$error_code{$fname} = UNOPANABLE_CONFIG_FILE;
		$error_msg{$fname} = UNOPANABLE_CONFIG_FILE_MSG;
		return 1;
	}

	while(my $line = <$file>){
		$lineNum ++;
		chomp $line;

		# Remove any trailing white space.
		$line =~ s/^s+//g;

		# If the line starts with a #, skip it.
		next if ($line =~ /^s*#/);

		# Skipping the line if it's blank
		next if ($line eq "");


		# Splitting the line up

		my @lineArray = split ' ', $line;
		my $lineLength = scalar(@lineArray);
		if($lineLength < 1){
			$error_code{$fname} = UNKNOWN_CONFIG;
			$error_msg{$fname} = UNKNOWN_CONFIG_MSG;
			return 1;
		}


		# if this line is an AS number
		if($lineArray[0] =~ /[aA][sS]/){
			if($lineArray[1] > 0 and $lineArray[1] < 4294967296){
				my $temp = $lineArray[1];
				push(@asNumbers, $temp);
			}
			else{
				$error_code{$fname} = INVALID_AS_CONFIG;
				$error_msg{$fname} = INVALID_AS_CONFIG_MSG;
				return 1;
			}
		}
		# if this line is an IPv4 number
		elsif($lineArray[0] =~ /[iI][pP][vV][4]/){
			# Ensuring that it's a valid IPv4 prefix
=comment
			if(!($line =~  m/([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3}\/[0-9]{1,2})\s*[ml][s]/)){
				
				#TODO replace the next two lines later and allow for single address specification
				print "skipping $line\n";
				next;
				#$error_code{$fname} = INVALID_IPV4_CONFIG;
				#$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
				#return 1;
			}

=cut

			my $ipcheck = ipv4_chkip($lineArray[1]);
			print "Skipping $line\n" unless $ipcheck;
			next unless $ipcheck;

			my @ipv4Addr = split(/\//, $lineArray[1]);
			my @octals = split(/\./,$ipv4Addr[0]);
			my $prefix = $ipv4Addr[1] || 32;
			foreach(@octals){
				if($_ < 0 or $_ > 255){	
					$error_code{$fname} = INVALID_IPV4_CONFIG;
					$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
					return 1;
				}
			}
			if($prefix < 0 or $prefix > 32){
				$error_code{$fname} = INVALID_IPV4_CONFIG;
				$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
				return 1;
			}


			if(!defined($lineArray[2])){ 
				$error_code{$fname} = INVALID_IPV4_CONFIG;
				$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
				return 1;
			}
			if(!$lineArray[2] =~ m/[mMlL][sS]/){
				$error_code{$fname} = INVALID_IPV4_CONFIG;
				$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
				return 1;
			}
			# Adding prefix to the list since it's okay
			my $moreSpecific = $lineArray[2] =~ m/[mM][sS]/;
			my $temp = new BGPmon::Filter::Prefix(4, 
					$lineArray[1], $moreSpecific); 
			push(@v4prefixes, $temp);
		}

		# if this line is an IPv6 number
		elsif($lineArray[0] =~ /[iI][pP][vV][6]/){
			# Ensuring that it's a valid IPv6 number and prefix
			my @ipv6Addr = split(/\//, $lineArray[1]);
			my $address = $ipv6Addr[0];
			my $prefix = $ipv6Addr[1];

			# Making sure the IPv6 is valid - in any form.
			if(!is_IPv6($ipv6Addr[0])){
				$error_code{$fname} = INVALID_IPV6_CONFIG;
				$error_msg{$fname} = INVALID_IPV6_CONFIG_MSG;
				return 1;
			}

			# Making sure the prefix is valid
			if($prefix < 0 or $prefix > 128){
				$error_code{$fname} = INVALID_IPV6_CONFIG;
				$error_msg{$fname} = INVALID_IPV6_CONFIG_MSG;
				return 1;
			}

			# Adding prefix to the list
			if(!defined($lineArray[2])){ 
				$error_code{$fname} = INVALID_IPV6_CONFIG;
				$error_msg{$fname} = INVALID_IPV6_CONFIG_MSG;
			}
			if(!$lineArray[2] =~ m/[mMlL][sS]/){
				$error_code{$fname} = INVALID_IPV6_CONFIG;
				$error_msg{$fname} = INVALID_IPV6_CONFIG_MSG;
				return 1;
			}
			my $moreSpecific = $lineArray[2] =~ m/[mM][sS]/;
			my $temp = new BGPmon::Filter::Prefix(6, $lineArray[1], $moreSpecific);
			push(@v6prefixes, $temp);
		}

		# if we don't know what this line is
		else{
			$error_code{$fname} = UNKNOWN_CONFIG;
			$error_msg{$fname} = UNKNOWN_CONFIG_MSG;
			return 1;
		}



	}

	#closing the file
	close($file);


	$error_code{$fname} = NO_ERROR_CODE;
	$error_msg{$fname} = NO_ERROR_MSG;

	return 0;
}

sub parse_config_db_result{
	my $resultset = shift;
	return unless ($resultset);
	my $fname = 'parse_config_db_result';

	foreach my $result (@{$resultset}) {

		if ($result->{'type'} eq 'as') {
			push(@asNumbers, $result->{'prefix'});
		}
		elsif ($result->{'type'} eq 'ipv4') {
			my $ipcheck = ipv4_chkip($result->{'prefix'});
			print "Skipping $result->{'prefix'}\n" unless $ipcheck;
			next unless $ipcheck;

			my @ipv4Addr = split(/\//, $result->{'prefix'});
			my @octals = split(/\./,$ipv4Addr[0]);
			my $prefix = $ipv4Addr[1] || 32;

			foreach(@octals){
				if($_ < 0 or $_ > 255){	
					$error_code{$fname} = INVALID_IPV4_CONFIG;
					$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
					return 1;
				}
			}

			if($prefix < 0 or $prefix > 32){
				$error_code{$fname} = INVALID_IPV4_CONFIG;
				$error_msg{$fname} = INVALID_IPV4_CONFIG_MSG;
				return 1;
			}

			my $moreSpecific = $result->{'matchop'} =~ m/[mM][sS]/;
			my $temp = new BGPmon::Filter::Prefix(4, $result->{'prefix'}, $moreSpecific, $result->{'as_regexp'});
			push(@v4prefixes, $temp);
		}
		elsif ($result->{'type'} eq 'ipv6') {
			my @ipv6Addr = split(/\//, $result->{'prefix'});
			my $address = $ipv6Addr[0];
			my $prefix = $ipv6Addr[1];

			# Making sure the IPv6 is valid - in any form.
			if(!is_IPv6($ipv6Addr[0])){
				$error_code{$fname} = INVALID_IPV6_CONFIG;
				$error_msg{$fname} = INVALID_IPV6_CONFIG_MSG;
				return 1;
			}

			# Making sure the prefix is valid
			if($prefix < 0 or $prefix > 128){
				$error_code{$fname} = INVALID_IPV6_CONFIG;
				$error_msg{$fname} = INVALID_IPV6_CONFIG_MSG;
				return 1;
			}

			my $moreSpecific = $result->{'matchop'} =~ m/[mM][sS]/;
			my $temp = new BGPmon::Filter::Prefix(6, $result->{'prefix'}, $moreSpecific, $result->{'as_regexp'});
			push(@v6prefixes, $temp);
		}
		else{
			$error_code{$fname} = UNKNOWN_CONFIG;
			$error_msg{$fname} = UNKNOWN_CONFIG_MSG;
			return 1;
		}
	}

	$error_code{$fname} = NO_ERROR_CODE;
	$error_msg{$fname} = NO_ERROR_MSG;

	return 0;
}

=head2 printFilters

Will print to standard output the filters currently set for the module.
For example, if your prefix file looked like

#IPv4

ipv4 192.168.1.0/24 ls

#IPv6

ipv6 ::0/32 ms

#AS

as   1

This will print 

ipv4 192.168.1.0/24 ls

ipv6 ::0/32 ms

as   1

=cut

sub printFilters(){

	foreach(@v4prefixes){
		print $_->toString() . "\n";
	}
	foreach(@v6prefixes){
		print $_->toString() . "\n";
	}
	foreach(@asNumbers){
		print "$_\n";
	}
}



=head2 toString

Will return a string that prints the most recently filtered prefixes and
autonymous system numbers in human-readable format.

E.g., 
IPv4 prefixes pulled from the message:
192.168.1.0/24
IPv6 prefixes pulled from the message:
(none)
AS numbers pulled from the message:
12345

=cut
sub toString(){
	my $fname = 'toString';
	my $toReturn = "";

	#Adding v4's
	$toReturn .= "IPv4 prefixes pulled from the message:\n";
	if(scalar @v4 == 0){
		$toReturn .= "(none)\n";
	}
	else{
		foreach(@v4){
			$toReturn .= "$_\n";
		}
	}

	#Adding v6's
	#
	$toReturn .= "IPv6 prefixes pulled from the message:\n";
	if(scalar @v6 == 0){
		$toReturn .= "(none)\n";
	}
	else{
		foreach(@v6){
			$toReturn .= "$_\n";
		}
	}
	#Adding AS's
	#
	$toReturn .= "AS numbers pulled from the message:\n";
	if(scalar @as == 0){
		$toReturn .= "(none)\n";
	}
	else{
		foreach(@as){
			$toReturn .= "$_\n";
		}
	}

	return $toReturn;

}

#comment
#
#Will reset the most recently filtered prefixes and AS numbers, parse the 
#message that was sent to it, and store a unique set of prefixes and 
#AS numbers.
#
#cut
sub parse_xml_msg{
	my $fname = 'parse_xml_msg';
	my $xmlMsg = shift;

	if(!defined($xmlMsg)){
		$error_code{$fname} = NO_MSG_GIVEN;
		$error_msg{$fname} = NO_MSG_GIVEN_MSG;
		return undef;
	}

	# A list of all the prefixes and AS's found during searching.
	my @v4s = ();
	my @v6s = ();
	my @ases = ();

	# The translation of the message
	my $hash = BGPmon::Translator::XFB2PerlHash::translate_msg($xmlMsg);

	#Checking the withdrawn part of the message
	my $hashRes1 = BGPmon::Translator::XFB2PerlHash::get_content('/BGP_MESSAGE/ASCII_MSG/UPDATE/WITHDRAWN/PREFIX/');
	if(defined($hashRes1)){
		foreach(@$hashRes1){
			push(@v4s, $_->{'ADDRESS'}->{'content'});
		}
	}

	#Checking the address parts in NLRI place
	my $hashRes2 = BGPmon::Translator::XFB2PerlHash::get_content('/BGP_MESSAGE/ASCII_MSG/UPDATE/NLRI/PREFIX/ADDRESS/content');
	push(@v4s, $hashRes2) if defined $hashRes2;

	#Checking the address part of MP_REACH_NLRI but skipping the Next Hop addresses
	my $hashRes = BGPmon::Translator::XFB2PerlHash::get_content('/BGP_MESSAGE/ASCII_MSG/UPDATE/PATH_ATTRIBUTES/ATTRIBUTE/MP_REACH_NLRI/NLRI/PREFIX/ADDRESS/content');
	if(defined($hashRes)){
		my @parts = split(/\//, $hashRes);
		if(is_IPv6($parts[0])){
			push(@v6s, $hashRes);
		}
		else{
			push(@v4s, $hashRes);
		}
	}


	#Checking the address part of MP_UNREACH_NLRI
	my $hashRes7 = BGPmon::Translator::XFB2PerlHash::get_content('/BGP_MESSAGE/ASCII_MSG/UPDATE/PATH_ATTRIBUTES/ATTRIBUTE/MP_UNREACH_NLRI/WITHDRAWN/PREFIX/ADDRESS/content');
	if(defined($hashRes7)){
		my @parts = split(/\//, $hashRes7);
		if(is_IPv6($parts[0])){
			push(@v6s, $hashRes7);
		}
		else{
			push(@v4s, $hashRes7);
		}
	}

	#Checking for AS numbers in the AS_Path attribute
	my $hashRes5 = BGPmon::Translator::XFB2PerlHash::get_content('/BGP_MESSAGE/ASCII_MSG/UPDATE/PATH_ATTRIBUTES/ATTRIBUTE/AS_PATH/AS_SEG/AS/');
	if(defined($hashRes5)){
		# First stash AS PATH away
		foreach my $as (@$hashRes5) {
			$aspath .= $as->{'content'} . '_';
		}
		if ($aspath=~m/_/) {
			chop $aspath;
		}

		# Then start sticking ASs in ases
		my $size = scalar(@$hashRes5);
		my $wantedAS = @$hashRes5[$size-1];
		my $finalAS = $wantedAS->{'content'};
		push(@ases, $finalAS) if defined $finalAS;
	}


	@v4 = ();
	@v6 = ();
	@as = ();

	if(scalar @v4s > 0){
		$v4[0] = $v4s[0];
		my $i = 0;
		@v4s = sort(@v4s);
		foreach my $item(@v4s){
			unless($item eq $v4[$i]){
				push(@v4, $item);
				$i++;
			}
		}
	}

	if(scalar @v6s > 0){
		$v6[0] = $v6s[0];
		my $i = 0;
		@v6s = sort(@v6s);
		foreach my $item(@v6s){
			unless($item eq $v6[$i]){
				push(@v6, $item);
				$i++;
			}
		}
	}

	if(scalar @ases > 0){
		$as[0] = $ases[0];
		my $i = 0;
		@ases = sort(@ases);
		foreach my $item(@ases){
			unless($item eq $as[$i]){
				push(@as, $item);
				$i++;
			}
		}
	}

	return 0; # successful message parsing
}


=head2 matches

Will check to see if the BGPmon message passed to it has maching prefix or AS 
fields that were given earlier to the module.  

Input:  A BGPmon message in XML format

Output: is a hashref, keyed on the result (what was found), with the value an arrayref of matching questions to ask
        0 if no matches were found.

=cut
sub matches{
	my $xmlMsg = shift;
	my $fname = 'matches';
	my %matches; my $found;

	if(!defined($xmlMsg)){
		$error_code{$fname} = NO_MSG_GIVEN;
		$error_msg{$fname} = NO_MSG_GIVEN_MSG;
		return undef;
	}

	parse_xml_msg($xmlMsg);

	# Checking to see if any of these AS numbers are ones we're looking for.
	if(scalar @as > 0){
		foreach my $matchas (@asNumbers){
			foreach my $as (@as){	
				if ($as eq $matchas) {
					$found = 1;
					foreach (@v4) {
						push(@{$matches{$_}}, $as);
					}
					foreach (@v6) {
						push(@{$matches{$_}}, $as);
					}
				}
			}
		}
	}



	# Checking to see if any of the v4 addresses are matches.
	if(scalar @v4 > 0){
		foreach (@v4prefixes){
			my $v4Prefix = $_;
			# Seeing if we need to keep on to the message
			foreach(@v4){
				my $ipPrefAddr = $_;
				if($v4Prefix->matches($ipPrefAddr)){
					if ($v4Prefix->{'asRegexp'} && !&regexPaths($v4Prefix->{'asRegexp'}, $aspath) || !$v4Prefix->{'asRegexp'}) {
						$found = 1;
						push(@{$matches{$_}}, $v4Prefix->toString());
					}
				}
			}
		}
	}

	# Checking to see if any of the v6 addresses are matches.
	if(scalar @v6 > 0){
		foreach (@v6prefixes){
			my $v6Prefix = $_;
			#Seeing if we need to keep on to the message
			foreach(@v6){
				my $ipPrefAddr = $_;
				if($v6Prefix->matches($ipPrefAddr)){
					if ($v6Prefix->{'asRegexp'} && !&regexPaths($v6Prefix->{'asRegexp'}, $aspath) || !$v6Prefix->{'asRegexp'}) {
						$found = 1;
						push(@{$matches{$_}}, $v6Prefix->toString());
					}
				}
			}
		}
	}
	return $found ? (\%matches) : FALSE;
}

sub regexPaths {

        my ($as_regexp, $as_path) = @_;
        return unless ($as_regexp);
        return if ($as_regexp=~ m/[^0-9\(\)\[\]\,\.\*\?\{\}\|\_\+]+/);          # only permitted metacharacters, 
        use re::engine::RE2 (-max_mem => 32768, -strict => 1, -longest_match => 1, -never_nl => 1);       # Use DFA, limit memory to prevent ReDoS
        my $compiled_regexp = qr/$as_regexp/;                                   # Compile the DFA 
        return 1 if ($as_path=~ $compiled_regexp);                              # Execute the DFA
        return;
}




1;
__END__


=head1 ERROR CODES AND MESSAGES

The following error codes and messages are defined:
	
	0:   There isn't an error.
	     'No Error. Relax with some tea.'
	520: The name of the configuration file given doesn't exists or
	     cannot be opened.
	     'Invalid filename given for config file.'
	530: An IPv4 address given in the configuration file has on octet 
	     out of range, is syntactly incorrect, or is otherwise invalid.
	     'Invalid IPv4 given in config file.'
	531: An IPv6 address given in teh configuration file has a value
	     out of range, is syntactly incorrect, or is otherwise invalid.
	     'Invalid IPv6 given in config file.'
	532: An Autonymous System number given in the configuration file
	     is out of range or otherwise invalid.
	     'Invalid AS given in config file.'
	533: An unknown configuration was found in the configuration file.
	     'Invalid line in config file.'
	540: A message was not passed to the BGPmon::Filter::matches method.
	     'No XML message was given.'


=cut

=head1 AUTHOR

M. Lawrence Weikum C<< <mweikum at rams.colostate.edu> >>

=cut

=head1 BUGS

Please report any bugs or feature requeues to 
 C<bgpmon at netsec.colostate.edu> or through the web interface
 at L<http://bgpmon.netsec.colostate.edu>.

=cut

=head1 SUPPORT

You can find documentation on this module with the perldoc command.

	perldoc BGPmon::Filter

=cut


=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012 Colorado State University

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom
the Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.\

File: Filter.pm
Authors: M. Lawrence Weikum
Date: 5 September 2012
=cut

