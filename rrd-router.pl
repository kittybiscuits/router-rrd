#!/usr/bin/env perl
#
# Get all available interfaces:
#   snmpwalk -v2c -c public 10.0.0.1 .1.3.6.1.2.1.2.2.1.2
#
# Get interface #2 description:
#   snmpget -v2c -c public 10.0.0.1 .1.3.6.1.2.1.2.2.1.2.2
#
# Get interface #2 packets in:
#   snmpget -v2c -c public 10.0.0.1 .1.3.6.1.2.1.31.1.1.1.6.2
#
# Get interface #2 packets out:
#   snmpget -v2c -c public 10.0.0.1 .1.3.6.1.2.1.31.1.1.1.10.2

use Net::SNMP;
use JSON::MaybeXS qw(decode_json);
use RRDs;

use strict;
use warnings;

CheckUsage();
Main();
exit 0;


sub Main {
	my $config = GetConfig($ARGV[0]);
	my %config = %{$config};

	my $session = GetSnmpSession($config{'hostname'}, $config{'port'},
		$config{'timeout'}, $config{'community'});

	my %discoveredInterfaces = GetInterfaceList($session);

	foreach my $oid (sort keys %discoveredInterfaces) {
		my $numIndex = rindex($oid, '.') + 1;
		my $interfaceNum = substr($oid, $numIndex);
		my $interfaceDesc = $discoveredInterfaces{$oid};
		my $interfaceIn = GetInterfaceIn($session, $interfaceNum);
		my $interfaceOut = GetInterfaceOut($session, $interfaceNum);

		printf("Interface #%-2s (%-8s)  In: %-12s Out: %s\n",
			$interfaceNum, $interfaceDesc, $interfaceIn, $interfaceOut);

		my $filename = defined($config{'interfaces'}{$interfaceDesc}{'rrd_filename'}) ?
			$config{'interfaces'}{$interfaceDesc}{'rrd_filename'} : $interfaceDesc;
		my $image_title = defined($config{'interfaces'}{$interfaceDesc}{'rrd_title'}) ?
			$config{'interfaces'}{$interfaceDesc}{'rrd_title'} : $interfaceDesc;

		CreateRRD($config{'rrd_dir'}, $filename);
		UpdateRRD($config{'rrd_dir'}, $filename, $interfaceIn, $interfaceOut);

		CreateImage($config{'png_dir'}, $config{'rrd_dir'}, $filename, 'day',
			$config{'png_width'}, $config{'png_height'},
			"Traffic on $image_title (1 day, 5min avg)");
		CreateImage($config{'png_dir'}, $config{'rrd_dir'}, $filename, 'week',
			$config{'png_width'}, $config{'png_height'},
			"Traffic on $image_title (1 week, 5min avg)");
		CreateImage($config{'png_dir'}, $config{'rrd_dir'}, $filename, 'month',
			$config{'png_width'}, $config{'png_height'},
			"Traffic on $image_title (1 month, 5min avg)");
		CreateImage($config{'png_dir'}, $config{'rrd_dir'}, $filename, 'year',
			$config{'png_width'}, $config{'png_height'},
			"Traffic on $image_title (1 year, 5min avg)");
	}
}

sub CheckUsage {
	if (!defined($ARGV[0])) {
		print "Usage: $0 <configFilename>\n";
		exit 1;
	}
}

sub GetConfig {
	local $/ = undef;
	my $configFilename = $_[0];

	open (FILE, '<', $configFilename) or die "ERROR: Unable to open file: $!";
	my $rawJson = <FILE>;
	close FILE;

	my $parsedConfig = decode_json($rawJson);

	return $parsedConfig;
}

sub GetSnmpSession {
	my $hostname = $_[0];
	my $port = $_[1];
	my $timeout = $_[2];
	my $community = $_[3];

	my ($session, $error) = Net::SNMP->session(
		-hostname  => $hostname,
		-community => $community,
		-version   => 2,
		-timeout   => $timeout,
		-port      => $port,
	);

	if (!defined($session)) {
		printf("ERROR: %s.\n", $error);
		exit 1;
	}

	return $session;
}

sub GetInterfaceDesc {
	my $session = $_[0];
	my $interfaceIndex = $_[1];
	my $oid = '.1.3.6.1.2.1.2.2.1.2.' . $interfaceIndex;

	return SnmpGetRequest($session, $oid);
}

sub GetInterfaceIn {
	my $session = $_[0];
	my $interfaceIndex = $_[1];
	# my $oid = '.1.3.6.1.2.1.2.2.1.10.' . $interfaceIndex; # 32 bit counter
	my $oid = '.1.3.6.1.2.1.31.1.1.1.6.' . $interfaceIndex; # 64 bit counter

	return SnmpGetRequest($session, $oid);
}

sub GetInterfaceOut {
	my $session = $_[0];
	my $interfaceIndex = $_[1];
	# my $oid = '.1.3.6.1.2.1.2.2.1.16.' . $interfaceIndex; # 32 bit counter
	my $oid = '.1.3.6.1.2.1.31.1.1.1.10.' . $interfaceIndex; # 64 bit counter

	return SnmpGetRequest($session, $oid);
}

sub SnmpGetRequest {
	my $session = $_[0];
	my $oid = $_[1];

	my $response = $session->get_request($oid);
	if ($session->error) {
		print "ERROR: " . $session->error . "\n";
		exit 1;
	}
	my %data = %{$response};

	return $data{$oid};
}

sub GetInterfaceList {
	my $session = $_[0];
	my $parentOid = '.1.3.6.1.2.1.2.2.1.2';

	my @args = (-varbindlist => [ $parentOid ]);
	my %returnData;

	while (defined($session->get_next_request(@args))) {
		my $returnedOid = ($session->var_bind_names())[0];
		last if ($returnedOid =~ '^\.1\.3\.6\.1\.2\.1\.2\.2\.1\.3');

		$returnData{$returnedOid} = $session->var_bind_list()->{$returnedOid};

		@args = (-varbindlist => [ $returnedOid ]);
	}

	return %returnData;
}

sub CreateRRD {
	my $rrdDir = $_[0];
	my $filenameWithoutExt = $_[1];

	my $rrdFilename = "$rrdDir/$filenameWithoutExt.rrd";

	if (!-e $rrdFilename) {
		print "  Creating new RRD file: $rrdFilename\n";
		RRDs::create($rrdFilename,
			"-s", "300",
			"DS:in:DERIVE:600:0:U",
			"DS:out:DERIVE:600:0:U",
			"RRA:AVERAGE:0.5:1:288", # 1 day, 5 min resolution
			"RRA:MAX:0.5:1:288",
			"RRA:AVERAGE:0.5:3:672", # 1 week, 15 min resolution
			"RRA:MAX:0.5:3:672",
			"RRA:AVERAGE:0.5:12:744", # 1 month, 1 hour resolution
			"RRA:MAX:0.5:12:744",
			"RRA:AVERAGE:0.5:72:1480", # 1 year, 6 hour resolution
			"RRA:MAX:0.5:72:1480",
		);

		if (my $error = RRDs::error()) {
			die "Failed to create RRD file: \"$rrdFilename\" -- $error\n";
		}
	}
}

sub UpdateRRD {
	my $rrdDir = $_[0];
	my $filenameWithoutExt = $_[1];
	my $in = $_[2];
	my $out = $_[3];

	my $rrdFilename = "$rrdDir/$filenameWithoutExt.rrd";

	RRDs::update($rrdFilename, "-t", "in:out", "N:$in:$out");

	if (my $error = RRDs::error()) {
		die "Failed to update RRD file: \"$rrdFilename\" -- $error\n";
	}
}

sub CreateImage {
	my $imageDir = $_[0];
	my $rrdDir = $_[1];
	my $filenameWithoutExt = $_[2];
	my $interval = $_[3];
	my $width = $_[4];
	my $height = $_[5];
	my $title = $_[6];

	my $imageFilename = "$imageDir/$filenameWithoutExt\_$interval.png";
	my $rrdFilename = "$rrdDir/$filenameWithoutExt.rrd";

	RRDs::graph($imageFilename,
		"-s -1$interval",
		"-t $title",
		"--lazy",
		"-h", $height, "-w", $width,
		"-l 0",
		"-a", "PNG",
		"-v bytes/sec",
		# "--slope-mode",
		"--border", "0",
		"--color", "BACK#ffffff",
		"--color", "CANVAS#ffffff",
		"--font", "LEGEND:7",
		"DEF:in=$rrdFilename:in:AVERAGE",
		"DEF:maxin=$rrdFilename:in:MAX",
		"DEF:out=$rrdFilename:out:AVERAGE",
		"DEF:maxout=$rrdFilename:out:MAX",

		"CDEF:out_neg=out,-1,*",
		"CDEF:maxout_neg=maxout,-1,*",
		"VDEF:in_total=in,TOTAL",
		"VDEF:out_total=out,TOTAL",

		"AREA:in#77dd77:Incoming",
		"LINE1:maxin#009900",
		"GPRINT:in:MAX:  Max\\: %6.1lf %s",
		"GPRINT:in:AVERAGE: Avg\\: %6.1lf %S",
		"GPRINT:in:LAST: Current\\: %6.1lf %SBytes/sec",
		"GPRINT:in_total:Total\\: %6.1lf %s\\n",

		"AREA:out_neg#9bbae1:Outgoing",
		"LINE1:maxout_neg#000099",
		"GPRINT:maxout:MAX:  Max\\: %6.1lf %S",
		"GPRINT:out:AVERAGE: Avg\\: %6.1lf %S",
		"GPRINT:out:LAST: Current\\: %6.1lf %SBytes/sec",
		"GPRINT:out_total:Total\\: %6.1lf %s\\n",

		"HRULE:0#000000",
	);
	if (my $error = RRDs::error()) {
		die "Failed to create PNG file: $imageFilename\" -- $error\n";
	}
}

