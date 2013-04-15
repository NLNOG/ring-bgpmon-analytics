#!/usr/bin/perl

#
#=BEGIN BGPMON-RING GPL
#
# This file is part of the BGPMon Analysis software
# Developed for the NLNOG Ring Project. 
#
# Copyright(c) 2012-2013 NLNog Ring Project. 
# http://ring.nlnog.net
#
# This file may be licensed under the terms of of the
# GNU General Public License Version 2 (the ``GPL'').
#
# Software distributed under the License is distributed
# on an ``AS IS'' basis, WITHOUT WARRANTY OF ANY KIND, either
# express or implied. See the GPL for the specific language
# governing rights and limitations.
#
# You should have received a copy of the GPL along with this
# program. If not, go to http://www.gnu.org/licenses/gpl.html
# or write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
#=END BGPMON-RING GPL
#

$| = 1;				# Autoflush
our $VERSION = '1.01';

use strict;
use warnings;

use threads qw(yield);
use threads::shared;

use BGPmon::Log qw(log_init log_fatal log_err log_warn log_notice log_info debug log_close);
use BGPmon::Fetch qw(connect_bgpdata read_xml_message close_connection is_connected);
use BGPmon::Translator::XFB2BGPdump qw(translate_message);
use BGPmon::Translator::XFB2PerlHash qw(translate_msg toString get_content get_error_code get_error_message);
use BGPmon::Configure;
use BGPmon::Filter;

use Boost::Graph;

use Data::Dumper;
use DBI;

use IO::Handle;
use IO::Socket;

use MIME::Lite;

use Net::Address::IP::Local;
use Net::IP;

use Perl::Unsafe::Signals;

use POSIX;

use Regexp::IPv6 qw($IPv6_re);

# Core constants
use constant FALSE 	=> 0;
use constant TRUE 	=> 1;

# Constants relating to bgpmon
use constant ERRNOMATCH	=> 1;	# This enables error handling outside of the BGPmon::Filter::matches() block, 
				# do not enable during production, will cause poor performance, this is purely
				# a diagnostic tool used to determine if BGPMon has gone insane

# Constants relating to email 
use constant ALERTSUBJ		=> 'New alert from BGPMON';
use constant NOTIFYMAX		=> 100; # Maximum  of 100 total notifications we can send about uncleared alarms to a recipient
use constant NOTIFYTIME 	=> 60;  # 60 seconds between email notifications
use constant NOTIFYMAXTIME  	=> 20;  # Maximum of 20 alerts in the NOTIFYTIME period for a recipient

# Constants relating to alerting
use constant MAXTRIGGERS=> 10000;	# Maximum number of cleared triggers in the database

# Constants relating to XML reading
use constant MAXIDLE	=> 10;		# Maximum amount of time (in seconds) we can be waiting for a message from bgpmon

my ($daemon, $database, $debug, $logFile, $logLevel, $maindbh, $outputFilename, $mailserver, $mailsender, $port, $printLock, $aThread, $eThread, $pThread, $reloadNeeded, $rThread, $server, $stdoutPrint, $tcpListThread, $useSyslog, $weburl);
my (@alerts, @asNumbers, @ipv4Prefixes, @ipv6Prefixes, @messages);

my $progName 	= $0;
my $exit 	= FALSE;	share($exit);
my $outputToFile= FALSE;

##--- Variables for Logging ---
#LOG_EMERG	: 0
#LOG_ALERT	: 1
#LOG_CRIT	: 2
#LOG_ERR	: 3
#LOG_WARNING	: 4
#LOG_NOTICE	: 5
#LOG_INFO	: 6
#LOG_DEBUG	: 7

$SIG{'HUP'} = \&reloadFiltersFromDBSignal;

#Checking that the command line arguments and configureation file are set properly.
die "Unable to verify if commandline arguments and configuration file are set properly" unless (parseAndCheck());

# Print debugging information if we are in debug mode
printDebugInfo() if ($debug);

# Initialise logging
my $logRetVal = log_init(use_syslog => 0, log_level => $logLevel, log_file => $logFile, prog_name => $progName);
die "Error initilaizing log" if ($logRetVal && defined($logFile));
log_info("bgpmon_analytics has started the log file.");

# Initialise output file if we are writing to one
if($outputToFile){
	openFile();
	log_info("bgpmon_analytics has started the output file to $outputFilename.");
}

# Establish the database connection
$maindbh = &dbConnect();
log_info("bgpmon_analytics has connected to the database");

# Initialise BGPMon filter unit
if(BGPmon::Filter::init()){
	log_err("Error initializing the filter module.");
	die "Couldn't start filter, Aborting";
}
else {
	log_info("Initialized the filter module.");
}


# Load filters from Database
&reloadFiltersFromDB($maindbh);

# Connect to BGPMon
print "Connecting to BGPmon\n" if $debug;
if(connect_bgpdata($server, $port)) {
	log_err("Couldn't connect to BGPmon server.");
	die "Couldn't connect to the BGPmon server.  Aborting\n";
}
else {
	log_info("Connected to BGPmon server");
}

# Here is the start of the main action, this code can be interrupted by signals (unsafe mode)
UNSAFE_SIGNALS {
	#Daemonizing
	daemonize() if ($daemon);
	
	# Share variables with other threads now
	share(@alerts);
	share(@messages);
	share($printLock);
	share($reloadNeeded);
	
	# Create threads
	$aThread = threads->create('alert');
	$eThread = threads->create('email');
	$rThread = threads->create('reader'); 
	$pThread = threads->create('parser'); 
	$aThread->join();
	$eThread->join();
	$rThread->join();
	$pThread->join();
};

#Close the logfile
log_close();

##############################END MAIN PROGRAM#################################




################################PROGRAM START SUBROUTINES#############################


sub parseAndCheck{

	my @params = (
		{
			Name	=> BGPmon::Configure::CONFIG_FILE_PARAMETER_NAME,
			Type	=> BGPmon::Configure::FILE,
			Default => "/etc/bgpmon/bgpmon_analytics_config.txt",
			Description => "This is the configuration file name.",
		},
		{
			Name => "server",
			Type => BGPmon::Configure::ADDRESS,
			Default => "127.0.0.1",
			Description => "This is the BGPmon server address",
		},
		{
			Name => "mailserver",
			Type => BGPmon::Configure::ADDRESS,
			Default => "127.0.0.1",
			Description => "This is the BGPmon mail server address",
		},
		{
			Name => "port",
			Type => BGPmon::Configure::PORT,
			Default => 50001,
			Description => "This is the BGPmon server port number",
		},
		{
			Name => "mailsender",
			Type => BGPmon::Configure::STRING,
			Default => 'bgpmon@ring.nlnog.net', 
			Description => "This is the SMTP address where mail will be sent from",
		},
		{
			Name => "database",
			Type => BGPmon::Configure::STRING,
			Default => undef, 
			Description => "This is the database connection string, mysql://user:pass\@localhost/bgpmon_analytics",
		},

		{
			Name => "output_file",
			Type => BGPmon::Configure::FILE,
			Default => "",
			Description => "This is where the BGP XML messages will be saved if the user wants them.",
		},

		{
			Name => "log_file",
			Type => BGPmon::Configure::FILE,
			Default => undef, #Note, undef is convention copied from BGPmon-Archiver
			Description => "This is the location the log file will be saved",
		},

		{
			Name => "log_level",
			Type => BGPmon::Configure::UNSIGNED_INT,
			Default => 7,
			Description => "This is how verbose the user wants the log to be",
		},

		{
			Name => "debug",
			Type => BGPmon::Configure::BOOLEAN,
			Default => FALSE,
			Description => "This is for debugging purposes",
		},

		{
			Name => "daemonize",
			Type => BGPmon::Configure::BOOLEAN,
			Default => FALSE,
			Description => "This will make the make the script run as a daemon",
		},
		{
			Name => "weburl",
			Type => BGPmon::Configure::STRING,
			Default => 'http://bgpmon.ring.nlnog.net',
			Description => "This is the web url for embedding in notifications and used by the web interface",
		},
		{
			Name => "stdout",
			Type => BGPmon::Configure::BOOLEAN,
			Default => FALSE,
			Description => "This is if the user wants to print to standard out",
		} );


	#Checking that everything parsed correctly
	if(BGPmon::Configure::configure(@params) ) {
		my $code = BGPmon::Configure::get_error_code("configure");
		my $msg = BGPmon::Configure::get_error_message("configure");
		print "$code: $msg\n";
		return FALSE;
	}

	#Moving all of the variables into the variables from previous version
	$daemon 		= BGPmon::Configure::parameter_value("daemonize");
	$debug 			= BGPmon::Configure::parameter_value("debug");
	$logFile 		= BGPmon::Configure::parameter_value("log_file");
	$logLevel 		= BGPmon::Configure::parameter_value("log_level");
	$port 			= BGPmon::Configure::parameter_value("port");
	$database 		= BGPmon::Configure::parameter_value("database");
	$server 		= BGPmon::Configure::parameter_value("server");
	$mailserver 		= BGPmon::Configure::parameter_value("mailserver");
	$mailsender 		= BGPmon::Configure::parameter_value("mailsender");
	$stdoutPrint 		= BGPmon::Configure::parameter_value("stdout");
	$weburl 		= BGPmon::Configure::parameter_value("weburl");

	my $tempOutputFilename 	= BGPmon::Configure::parameter_value("output_file");

	if($tempOutputFilename eq ""){
		$outputToFile = FALSE;
	}
	else{
		$outputToFile = TRUE;
		$outputFilename = $tempOutputFilename;
	}

	return TRUE;
}

sub reloadFiltersFromDBSignal {
	# Set reloadNeeded flag
	$reloadNeeded = 1;
}

sub reloadFiltersFromDB {

	my $dbh = shift;
	return unless ($dbh);

	BGPmon::Filter::reset();
		
	my $sql 	= "SELECT p.type,p.prefix,p.matchop,p.as_regexp FROM alarms a RIGHT JOIN prefixes p ON (a.prefix = p.id) WHERE a.type='email' and enabled=1;";
	my $results 	= &dbQuery($dbh, $sql);

	BGPmon::Filter::parse_config_db_result($results);

	# Debug active filters if we are in debug mode
	if ($debug) {
		print "Filter reload triggered, Active filters are now:\n";
		BGPmon::Filter::printFilters();
	}

	# Reset reloadNeeded flag
	$reloadNeeded = 0;

}


sub printDebugInfo{

	my $config_file = BGPmon::Configure::parameter_value(BGPmon::Configure::CONFIG_FILE_PARAMETER_NAME);

	print "BGPMon Server:		$server\n";
	print "BGPMon Port:		$port\n";	
	print "Configuration File	$config_file\n";
	print "Database Connection	$database\n";
	print "Web URL			$weburl\n";
	print "Mail Server		$mailserver\n";
	print "Mail Sender		$mailsender\n";
	print "Log Level		$logLevel\n";
	print "Log File		" 	. ($logFile 		? $logFile 		: '<none>'	) . "\n";
	print "Output File		" . ($outputToFile 	? $outputFilename 	: '<none>'	) . "\n";
	print "Debug			" . ($debug 		? 'TRUE' 		: 'FALSE'	) . "\n";
	print "STDOUT Print		" . ($stdoutPrint 	? 'TRUE' 		: 'FALSE'	) . "\n";
	print "Daemonize		" . ($daemon 		? 'TRUE' 		: 'FALSE'	) . "\n";
}


sub openFile{
	open OUTPUTFILE, ">>", "$outputFilename" or die "Couldn't open output file $outputFilename.  Aborting.\n";
	log_err("Coudln't open $outputFilename.");
}

sub closeFile{
	close(OUTPUTFILE);
}

sub daemonize {
    # Fork and exit parent. Makes sure we are not a process group leader.
    my $pid = fork;
    exit 0 if $pid;
    exit 1 if not defined $pid;

    # Become leader of a new session, group leader of new
    # process group and detach from any terminal.
    setsid();
    $pid = fork;
    exit 0 if $pid;
    exit 1 if not defined $pid;
}



#################################THREADING SUBROUTINES####################################

# Alert from parser
sub alert {
	my $alertdbh = &dbConnect();		# Alerting thread has its own database handle

	while(!$exit){

		# Get a message
		my $nextAlert = "";
		{
			lock(@alerts);
			$nextAlert = $alerts[0];
			shift(@alerts);
		}

		# If nothing was on the queue, sleep and yield the processor
		if(!defined($nextAlert) or $nextAlert eq "" ) {
			yield();
			sleep(1);
			next;
		}

		# Else, create the alert in the database 
		my $type  = $nextAlert->{'xtype'};
		my $source= $nextAlert->{'xsource'};
		my $path  = $nextAlert->{'xpath'};
		foreach my $prefix (sort keys %{$nextAlert->{'xmatches'}}) {
			foreach my $alarmedprefixstr (@{$nextAlert->{'xmatches'}->{$prefix}}) {
				my ($alarmedprefix, $alarmedmatchop, $alarmedregexp) = split(/ /, $alarmedprefixstr);

				if ($alarmedmatchop) { 
					$alarmedmatchop = "= '$alarmedmatchop'";
				}
				else {
					$alarmedmatchop = 'is NULL';
				}

				if ($alarmedregexp) { 
					$alarmedregexp = "= '$alarmedregexp'";
				}
				else {
					$alarmedregexp = 'is NULL';
				}

				# Nothing is cleared yet
				my $cleared = 0;

				# If there is a withdraw, look for a corresponding ANNOUNCE and clear it
				if ($type eq 'WITHDRAW') {
					$cleared = 1;	# leave cleared flag set so that the corresponding alarm will also be cleared
					&dbDo($alertdbh, "update alarmtriggers set cleared = '$cleared' where cleared=0 and type='ANNOUNCE' and prefix='$prefix';");
				}
				
				# Create the alarm
				&dbDo($alertdbh, "
				INSERT INTO
					alarmtriggers (alarm, type, prefix, path, source, cleared)
				VALUES ((
					SELECT 
						a.id
					FROM
						alarms a
					RIGHT JOIN
						prefixes p
					ON
						(a.prefix = p.id)
					WHERE
						a.type = 'email'
					AND
						p.prefix = '$alarmedprefix'
					AND
						p.matchop $alarmedmatchop
					AND
						p.as_regexp $alarmedregexp
				),'$type','$prefix','$path','$source','$cleared');
				");
			}
		}

		#Memory Management
		$nextAlert = undef;

	}

	&dbClose($alertdbh);

	print "Alert thread finished.\n" if ($debug);

}

# Email out notifications we need
sub email {
	my $emaildbh = &dbConnect();		# Emailing thread has its own database handle

	while(!$exit){

		my %emailbatch;			# Stack representing the batch of emails we're going to send

		# Find all notifications pending
		my $results = &dbQuery($emaildbh, "select * from alarmtriggerview where alarmtype='email' and notified=0");
		unless ($$results[0]) {
			yield();
			sleep(NOTIFYTIME);
			next;
		}

		# yes, I know about the potential race condition here, I need some kind of database locking or atomic select + update transcation 
		# somebody help me!

		# Set all rows as notified
		&dbDo($emaildbh, "update alarmtriggers set notified=1;");	

		# Count number of rows in triggers in order to truncate 
		my $count = $emaildbh->selectrow_array('SELECT count(*) FROM alarmtriggers where notified=1 and cleared=1', undef);
		if ($count> MAXTRIGGERS) {
			my $triggersToDelete = $count - MAXTRIGGERS;
			if ($triggersToDelete >= 1) {
				# Truncate the table to MAXTRIGGERS size
				&dbDo($emaildbh, "delete from alarmtriggers where notified=1 and cleared=1 limit $triggersToDelete");
			}
		}

		# Now send the emails we were going to send
		foreach my $result (@{$results}) {
			if ($emailbatch{$result->{'email'}}{'count'} && $emailbatch{$result->{'email'}}{'count'} >= (NOTIFYMAXTIME-1)) {
				$emailbatch{$result->{'email'}}{'textbody'} .= "\n\nThe maximum number of alerts you can receive in this email has been reached, please log in via the web interface to see more.\n";
				$emailbatch{$result->{'email'}}{'htmlbody'} .= "<br><br>The maximum number of alerts you can receive in this email has been reached, please <a href='$weburl'>log in</a> via the web interface to see more.";
			}
			else {

				my $cleared   = $result->{'cleared'};
				my $announces = $result->{'announces'};
				my $withdraws = $result->{'withdraws'};

				my ($bodyline, $newpath, $origin, $upstreams);
				($newpath, $origin, $upstreams) = &simplifyPaths($result->{'path'}) if ($result->{'path'});
				$newpath    = "N/A" unless ($newpath);
				$origin     = "N/A" unless ($origin);
				$upstreams  = "N/A" unless ($upstreams);

				# Determine how to phrase the mail
				if (($announces >= 1 ) || (($announces >= 1) && ($withdraws >= 1))) {
					$bodyline .= 'NEW ALERT';
					if ($cleared == 1) {
						$bodyline .= ', ALREADY CLEARED: ';
					}
					else {
						$bodyline .= ': ';
					}
				}
				elsif ($withdraws >= 1) {
					$bodyline .= 'NEW WITHDRAW ALERT: ';
				}

				$bodyline .= '@ ' . $result->{'triggerperiodbegin'};
				$bodyline .= " ($announces announces, $withdraws withdraws)";
				$bodyline .= ' '  . $result->{'prefix'};
				$bodyline .= ' for alarm ' . $result->{'alarmprefix'};
				$bodyline .= "\n\n Origin: $origin, Alert paths: $newpath, Path upstreams: $upstreams\n";
				$bodyline .= "\n\n\n";

				my $htmlbodyline = $bodyline; $htmlbodyline=~s/\n/<br>/g;

				$emailbatch{$result->{'email'}}{'textbody'} .= $bodyline;
				$emailbatch{$result->{'email'}}{'htmlbody'} .= $htmlbodyline;
				$emailbatch{$result->{'email'}}{'count'}++;
			
			}
		}

		# Send the emails
		foreach my $mailrecipient (sort keys %emailbatch) {
			my $msg =  MIME::Lite->new(From=>$mailsender, To=>$mailrecipient, Subject=>ALERTSUBJ, Type=>'multipart/alternative');
			$msg->attach(Type=>'text/plain', Data=>$emailbatch{$mailrecipient}{'textbody'});
			$msg->attach(Type=>'text/html',  Data=>$emailbatch{$mailrecipient}{'htmlbody'});
		    	$msg->send('smtp', $mailserver);
		}

		sleep(NOTIFYTIME);

	}
	&dbClose($emaildbh);

	print "Email thread finished.\n" if ($debug);
}



# Read from BGPMon
sub reader{
	my $msgType;
	my $xmlMsg 	= '';
	my $write 	= 0;
	my $count 	= 0;

	while(!$exit){
		$SIG{'INT'} = sub {print "Exiting\n"; threads->exit();};

		if(!is_connected){
			print "Lost connection to BGPmon. Stopping.\n" if $debug;
			log_info("Lost connection to BGPmon.  Stopping.");
			$exit = TRUE;
			next;
		}

		$xmlMsg = read_xml_message();

		# Check if we received an XML message
		log_err("Error reading XML message from BGPmon") unless (defined $xmlMsg);

		# Add a message to the message queue (@messages)
		{
			lock (@messages);
			my $tempRef = \$xmlMsg;
			share($tempRef);
			push(@messages, $tempRef);
		}
	}

	print "Exiting reading thread.\n" if $debug;

	# closing connection to BGPmon
	close_connection();
	print "Connection to bgpmon instance closed.\n" if $debug;
	log_info("Connection to bgpmon instance closed.");
}

#Read a message from the messages queue
sub parser{

	my $parserdbh = &dbConnect();				# Parsing thread has its own database handle
	my $parserNothingToDo;					# Parser idle timer

	PLOOP:
	while(!$exit){

		# Check if we need to reload filters
		&reloadFiltersFromDB($parserdbh) if ($reloadNeeded == 1);

		# Get a message
		my $nextMsg = "";
		{
			lock(@messages);
			$nextMsg = $messages[0];
			shift(@messages);
		}

		# If nothing was on the queue, sleep and yield the processor
		if(!defined($nextMsg) or $nextMsg eq "" ) {
			$parserNothingToDo++;
			if ($parserNothingToDo >= MAXIDLE) {	# But if we've been idle too long, bail
				print "Parser has been idle too long, probably an issue with BGPmon. Stopping\n" if ($debug);
				log_info("Parser idle too long.  Stopping.");
				$exit = TRUE;
				next PLOOP;
			}
			yield();
			sleep(1);
			next;
		}
		else {
			$parserNothingToDo = 0;
		}

		# Make a copy of what we just shifted off the array, so it doesn't get modified
		my $processMsg = $$nextMsg;

		#Checking to see if the message has addresses/AS#'s we want, then handling message to stdout, clients, and file.
		#But ignore status messages 
		if ($processMsg=~m/<STATUS_MSG>/) {
			print "STATUSMSG: Skipping BGPMon status message\n" if ($debug);
		}
		elsif(my $matches = BGPmon::Filter::matches($processMsg) || ERRNOMATCH) {

			no autovivification;									# Disable autovivification in this scope
			undef($matches) unless (ref($matches) eq 'HASH');					# clean $matches hashref on import

			{
				lock($printLock);
				print "$processMsg\n\n" if $stdoutPrint;
			}

			if($outputToFile){
				print OUTPUTFILE $processMsg;
				OUTPUTFILE->autoflush(1);
			}

			# Decode XFB 
			my ($nomatches, $xmatch, $xpath);
			my $xtype = 'UNKNOWN';
			my $xfb   = translate_msg($processMsg);

			my $xsource  = $xfb->{'BGP_MESSAGE'}->{'PEERING'}->{'SRC_ADDR'}->{'ADDRESS'}->{'content'};
			my $xdata    = $xfb->{'BGP_MESSAGE'}->{'ASCII_MSG'}->{'UPDATE'};

			if ($xdata->{'NLRI'}->{'count'} && $xdata->{'NLRI'}->{'count'} > 0) {			# Announced prefixes
				foreach my $aprefix (@{$xdata->{'NLRI'}->{'PREFIX'}}) {
					my $nlriprefix = $aprefix->{'ADDRESS'}->{'content'};
					if ($matches->{$nlriprefix}) {
						$xtype  = 'ANNOUNCE';
						$xmatch = 1;
					}
					elsif (ERRNOMATCH) {
						$xtype = 'ANNOUNCE';
						push (@{$nomatches->{'ANNOUNCE'}}, $nlriprefix);
					}
				}
			}

			if ($xdata->{'WITHDRAWN'}->{'count'} && $xdata->{'WITHDRAWN'}->{'count'} > 0) {		# Withdrawn prefixes
				foreach my $wprefix (@{$xdata->{'WITHDRAWN'}->{'PREFIX'}}) {
					my $nlriprefix = $wprefix->{'ADDRESS'}->{'content'};
					if ($matches->{$wprefix->{'ADDRESS'}->{'content'}}) {
						$xtype  = 'WITHDRAW';
						$xmatch = 1;
					}
					elsif (ERRNOMATCH) {
						$xtype = 'WITHDRAW';
						push (@{$nomatches->{'WITHDRAW'}}, $nlriprefix);
					}
				}
			}

			if ($xdata->{'PATH_ATTRIBUTES'}->{'count'} && $xdata->{'PATH_ATTRIBUTES'}->{'count'} > 0) {	# Harvest Path attributes 
				foreach my $attribute (@{$xdata->{'PATH_ATTRIBUTES'}->{'ATTRIBUTE'}}) {

					if ($attribute->{'AS_PATH'}->{'AS_SEG'}) {				# Harvest AS_PATH
						XPATH:
						foreach my $asseg (@{$attribute->{'AS_PATH'}->{'AS_SEG'}}) {
							foreach my $as (@{$asseg->{'AS'}}) {
								$xpath .= $as->{'content'} . '_';
							}
							if ($xpath=~m/_/) {
								chop $xpath;
								last XPATH;
							}
						}
					}
					elsif (
						$attribute->{'MP_REACH_NLRI'}->{'NLRI'}->{'count'} && 
						$attribute->{'MP_REACH_NLRI'}->{'NLRI'}->{'count'} > 0) {	# Harvest MP_REACH_NLRI
						foreach my $aprefix (@{$attribute->{'MP_REACH_NLRI'}->{'NLRI'}->{'PREFIX'}}) {
							my $nlriprefix = $aprefix->{'ADDRESS'}->{'content'};
							if ($matches->{$nlriprefix}) {
								$xtype  = 'ANNOUNCE';
								$xmatch = 1;
							}
							elsif (ERRNOMATCH) {
								$xtype = 'ANNOUNCE';
								push (@{$nomatches->{'ANNOUNCE'}}, $nlriprefix);
							}
						}
					}
					elsif (
						$attribute->{'MP_UNREACH_NLRI'}->{'WITHDRAWN'}->{'count'} && 
						$attribute->{'MP_UNREACH_NLRI'}->{'WITHDRAWN'}->{'count'} > 0) {	# Harvest MP_UNREACH_NLRI
						foreach my $wprefix (@{$attribute->{'MP_UNREACH_NLRI'}->{'WITHDRAWN'}->{'PREFIX'}}) {
							my $nlriprefix = $wprefix->{'ADDRESS'}->{'content'};
							if ($matches->{$wprefix->{'ADDRESS'}->{'content'}}) {
								$xtype  = 'WITHDRAW';
								$xmatch = 1;
							}
							elsif (ERRNOMATCH) {
								$xtype = 'WITHDRAW';
								push (@{$nomatches->{'WITHDRAW'}}, $nlriprefix);
							}
						}
					}
				}
			}

			$xpath = '' if (!$xpath || $xtype ne 'ANNOUNCE');	# For announced prefixes ONLY get the path, 
										# RFC4271 and RFC4760 do not require, 
										# path information to be present for a WITHDRAW

			if ($xtype eq 'UNKNOWN') {
				# This shouldn't happen, it means we got a match for something that wasn't in the dequeued message and hence couldn't classify it
				# when you dump these messages, you can see that they differ from the initial messages passed into the matches() function,
				# they are indeed the NEXT message in the queue, they've been somehow intefered with by the threading, 
				# we attempt to fix this by cloning the shifted message into processMsg so that this should never happen.
				log_err("Can't determine what kind of update this is, something may be overwriting the message queue, please investigate");
			}

			# If we really had a match (and yes, we've double checked it ourselves, using xmatch), then we can generate a bona fide alert
			# so add an alert to the alerts queue (@alerts)
			if ($xmatch) {
				lock (@alerts);
				push (@alerts, shared_clone({'xmatches'=>$matches, 'xsource'=>$xsource, 'xtype'=>$xtype, 'xpath'=>$xpath}));
				print "MATCH: " . Dumper($matches) . " SOURCE = $xsource, TYPE = $xtype, PATH = $xpath\n" if ($debug);
			}
			elsif (ERRNOMATCH && $xtype eq 'UNKNOWN') {
				print "NOMATCH: " . Dumper($xfb);
			}


		};

		#Memory Management
		$processMsg = undef;
		$nextMsg    = undef;
		$nextMsg    = undef;

	}

	&dbClose($parserdbh);

	print "Parser thread finished.\n" if ($debug);

}

sub analyticsExit{
	print "\nCaught exit signal.  Quitting.\n";
	{
		&dbClose($maindbh);	# Close main database handle
		$exit = TRUE;
	}
};


# Path functions
# simplify a set of paths down to a common path factor
# returns new simplified path (netpath), origin AS, and a list of possible upstreams
sub simplifyPaths {
        my $paths = shift;
        return unless ($paths);

        my $graph = new Boost::Graph(directed=>1);      # directed graph
        my @paths = split(/,/, $paths);                 # list of all paths

        my @children;           # Storage for directed graph children
        my @newpath;            # Space for new path to be constructed
        my ($node, $origin);    # Current Node and Origin AS

        #Now remove prepended AS nodes from the path, since they'll confuse our graph
        foreach my $path (@paths) {
                #print "INPATH = $path ";
                my @elems = reverse(split(/_/, $path));
                for (my $i=0; $i<$#elems; $i++) {
                        if ($elems[$i] == $elems[($i+1)]) {
                                splice (@elems, $i, 1);
                                $i--;
                        }
                }
                #print "OUTPATH = " . join('_', reverse(@elems)) . "\n";
                $origin = $elems[0] unless ($origin);
                $graph->add_path(@elems);
        }

        #Now we can build the graph and work out what the shortest common path is 
        $node = $origin;
        WALKNODES:
        for (my $i=1; $i<$graph->nodecount(); $i++) {
                @children = @{$graph->children_of_directed($node)};
                #print "Investigating " . Dumper(\@children) . "\n";
                if ($#children > 0) {
                        last WALKNODES;
                }
                else { 
                        $node = $children[0];
                        if ($node) {
                                push (@newpath, $node);
                        }
                        else { 
                                last WALKNODES;
                        }
                }
        }
	my $newpathstr  = join('_', reverse(@newpath), $origin);
	my $upstreamstr = join(',', sort({ $a <=> $b } @children));
	return ($newpathstr, $origin, $upstreamstr);
}

# Database functions
sub dbConnect {
	if ($database=~m/^([^:]+):\/\/([^:]+):([^@]+)@([^\/]+)\/(\S+)$/) {
		my $dbh = DBI->connect("DBI:$1:database=$5;host=$4", $2, $3, {RaiseError => 1}) || die "Can't connect to database " . DBI::errstr . "\n";
		return ($dbh);
	}
	else {
		die "Malformed or missing database handle in config file, format is <provider>://<user>:<password>@<host>/<db>";
	}
}

sub dbClose {
	my $dbh = shift;
	return unless ($dbh);
	eval {close($dbh)};
}

sub dbQuery {
	my ($dbh, $sql) = @_;
	return unless ($dbh && $sql);
	my $result = eval {			# Keep thread alive during query
		return $dbh->selectall_arrayref($sql, { Slice => {} }) || log_err("Error running query for sql [ $sql ] " . DBI::errstr);
	};
	return $result;
}

sub dbDo {
	my ($dbh, $sql) = @_;
	return unless ($dbh && $sql);
	my $result = eval {			# Keep thread alive during query
		return $dbh->do($sql) || log_err("Error running query for sql [ $sql ] " . DBI::errstr);
	};
	return $result;
}
