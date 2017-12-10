#!/usr/bin/env perl
#
# Get all available interfaces:
#   snmpwalk -v1 -c public -m +UBNT-UniFi-MIB 10.0.0.1 .1.3.6.1.2.1.2.2.1.2
#
# Get interface #2 description:
#   snmpget -v1 -c public -m +UBNT-UniFi-MIB 10.0.0.1 .1.3.6.1.2.1.2.2.1.2.2
#
# Get interface #2 packets in:
#   snmpget -v1 -c public -m +UBNT-UniFi-MIB 10.0.0.1 .1.3.6.1.2.1.2.2.1.10.2
#
# Get interface #2 packets out:
#   snmpget -v1 -c public -m +UBNT-UniFi-MIB 10.0.0.1 .1.3.6.1.2.1.2.2.1.16.2

use Net::SNMP;
use JSON::MaybeXS qw(decode_json);

use strict;
use warnings;

my $config = GetConfig();
Main($config);
exit 0;


sub Main {
	my %config = %{$_[0]};

	my $session = GetSnmpSession($config{'hostname'}, $config{'port'},
		$config{'timeout'}, $config{'community'});

	my %discoveredInterfaces = GetInterfaceList($session);

	foreach my $oid (sort keys %discoveredInterfaces) {
		my $numIndex = rindex($oid, '.') + 1;
		my $interfaceNum = substr($oid, $numIndex);

		printf("Interface #%-2s (%-8s)  In: %-12s Out: %s\n",
			$interfaceNum,
			$discoveredInterfaces{$oid},
			GetInterfaceIn($session, $interfaceNum),
			GetInterfaceOut($session, $interfaceNum),
		);
	}
}

sub GetConfig {
	local $/ = undef;

	open (FILE, '<', 'config.json') or die "ERROR: Unable to open file: $!";
	my $rawJson = <FILE>;
	close FILE;

	my $config = decode_json($rawJson);

	return $config;
}

sub GetSnmpSession {
	my $hostname = $_[0];
	my $port = $_[1];
	my $timeout = $_[2];
	my $community = $_[3];

	my ($session, $error) = Net::SNMP->session(
		-hostname  => $hostname,
		-community => $community,
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
	my $oid = '.1.3.6.1.2.1.2.2.1.10.' . $interfaceIndex;

	return SnmpGetRequest($session, $oid);
}

sub GetInterfaceOut {
	my $session = $_[0];
	my $interfaceIndex = $_[1];
	my $oid = '.1.3.6.1.2.1.2.2.1.16.' . $interfaceIndex;

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

