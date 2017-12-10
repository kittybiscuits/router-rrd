#!/usr/bin/env python

import json

from pysnmp.hlapi import *

OID_INTERFACE_LIST_BEGIN = '1.3.6.1.2.1.2.2.1.2'
OID_INTERFACE_LIST_END = '1.3.6.1.2.1.2.2.1.3'
OID_INTERFACE_DESC = '1.3.6.1.2.1.2.2.1.2.{:s}'
OID_INTERFACE_IN = '1.3.6.1.2.1.2.2.1.10.{:s}'
OID_INTERFACE_OUT = '1.3.6.1.2.1.2.2.1.16.{:s}'


def main(config):
    interfaces = get_interface_list(config)

    for oid in interfaces:
        interface_num_idx = oid.rindex('.') + 1
        interface_num = oid[interface_num_idx:]
        interface_desc = get_interface_desc(config, interface_num)
        interface_in = get_interface_in(config, interface_num)
        interface_out = get_interface_out(config, interface_num)

        print("Interface #%-2s (%-8s)  In: %-12s  Out: %-12s"
              % (interface_num, interface_desc, interface_in, interface_out))


def get_config():
    raw_json = open('config.json').read()
    return json.loads(raw_json)


def get_interface_list(config):
    interfaces_found = {}

    for (error_indication, error_status, error_index, var_binds) \
            in snmp_next_cmd(config['community'], config['hostname'],
                             config['port'], config['timeout'],
                             OID_INTERFACE_LIST_BEGIN):
        check_error(error_indication, error_status, error_index, var_binds)

        for var_bind in var_binds:
            returned_oid = str(var_bind[0])
            returned_value = str(var_bind[1])

            if OID_INTERFACE_LIST_END in returned_oid:
                return interfaces_found

            interfaces_found[returned_oid] = returned_value

    return interfaces_found


def get_interface_desc(config, interface_num):
    oid = OID_INTERFACE_DESC.format(interface_num)
    return snmp_get_value(config['community'], config['hostname'],
                          config['port'], config['timeout'], oid)


def get_interface_in(config, interface_num):
    oid = OID_INTERFACE_IN.format(interface_num)
    return snmp_get_value(config['community'], config['hostname'],
                          config['port'], config['timeout'], oid)


def get_interface_out(config, interface_num):
    oid = OID_INTERFACE_OUT.format(interface_num)
    return snmp_get_value(config['community'], config['hostname'],
                          config['port'], config['timeout'], oid)


def snmp_next_cmd(community, hostname, port, timeout, oid):
    return nextCmd(SnmpEngine(),
                   CommunityData(community, mpModel=1),
                   UdpTransportTarget((hostname, port), timeout=timeout),
                   ContextData(),
                   ObjectType(ObjectIdentity(oid)))


def snmp_get_value(community, hostname, port, timeout, oid):
    error_indication, error_status, error_index, var_binds = next(
        getCmd(SnmpEngine(),
               CommunityData(community, mpModel=1),
               UdpTransportTarget((hostname, port), timeout=timeout),
               ContextData(),
               ObjectType(ObjectIdentity(oid))))
    check_error(error_indication, error_status, error_index, var_binds)

    return str(var_binds[0][1])


def check_error(error_indication, error_status, error_index, var_binds):
    if error_indication:
        print(error_indication)
        exit(1)
    elif error_status:
        print('%s at %s' % (error_status.prettyPrint(), error_index and
                            var_binds[int(error_index) - 1][0] or '?'))
        exit(1)


if __name__ == "__main__":
    loaded_config = get_config()
    main(loaded_config)
