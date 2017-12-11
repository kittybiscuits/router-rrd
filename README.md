# Purpose

1. Get network in/out traffic stats for all interfaces on a router.
2. Use RRDtool to make pretty pictures for all those interfaces.

# Configuration

Copy the `config.json.example` file to `config.json` and edit its contents appropriately.

## Interface definitions

Listing all interfaces in the `config.json` file is not required.

If an interface is found on a router and it's not listed in `config.json`, the
`IF-MIB::ifDescr` value will be used in generated PNG files.

# Usage

	$ ./network_rrd.pl config.json

# Details

This script will identify all interfaces on a router and obtain the following info:

- Interface description (`IF-MIB::ifDescr`)
- Network traffic in (`IF-MIB::ifInOctets`)
- Network traffic out (`IF-MIB::ifOutOctets`)

# Dependencies

- rrdtool
- Perl, with the following modules:
	- Net::SNMP
	- JSON::MaybeXS
	- RRDs

## Debian packages

If you are using Debian, the above dependencies can be satisfied by installing the following packages:

- rrdtool
- libnet-snmp-perl
- libjson-maybexs-perl
- librrds-perl

