import json
import ipaddress
import time
import logging
import subprocess

from hwinfo.run_cmd import run_cmd
from hwinfo.network_interface import NetworkInterface


LAB_ACCESS_NETWORK = ipaddress.ip_network('192.168.16.0/20')

def convert_ip_address(ip):
    """Converts an IPv4 address to a new IPv4 address in the 10.10.Z.T format.

    Args:
        ip: A string representing a valid IPv4 address in X.Y.Z.T format.

    Returns:
        A string representing the new IPv4 address in 10.10.Z.T format,
        or None if the input is not a valid IPv4 address.
    """
    try:
        octets = ip.split(".")
        if len(octets) != 4:
            return None
        for octet in octets:
            if not octet.isdigit() or int(octet) < 0 or int(octet) > 255:
                return None
        return f"10.100.{octets[2]}.{octets[3]}"
    except ValueError:
        return None


def get_ip_address(interface_name, max_retries=40, retry_interval=3):
    """Gets the IP address of a specific network interface with retries.

    Args:
      interface_name: The name of the network interface (e.g., "eth0", "wlan0").
      max_retries: The maximum number of retries (default: 40 - 2 minute with 3s interval).
      retry_interval: The time to wait between retries in seconds (default: 3).

    Returns:
      The IP address as a string, or None if all retries fail.
    """
    for _ in range(max_retries):
        try:
            logging.info(f"getting IP address of {interface_name} (attempt {_}/{max_retries})")
            # Use subprocess.run with capture_output to get the command output
            result = subprocess.run(["ip", "addr", "show", interface_name], capture_output=True)
            result.check_returncode()  # Raise exception if command fails

            # Decode the output and search for 'inet' keyword in lines
            output = result.stdout.decode('utf-8').splitlines()
            for line in output:
                if 'inet' in line:
                    # Extract the IP address after 'inet' (assuming space separation)
                    return line.split()[1].strip()

            # If no 'inet' found in output after successful execution, retry
            logging.info(f"interface '{interface_name}' might be down (attempt {_}/{max_retries})")

        except subprocess.CalledProcessError as e:
            logging.info(f"error getting IP address (attempt {_}/{max_retries}): {e}")
        except Exception as e:
            logging.info(f"unexpected error (attempt {_}/{max_retries}): {e}")
        else:
            # Successful execution, break out of loop and avoid waiting
            break  # Exit the loop if IP address retrieved

        # Wait before retrying (only if no break occurred)
        time.sleep(retry_interval)

    # No successful retrieval after retries
    logging.info(f"couldn't get IP address of {interface_name} after {max_retries} retries")
    return None


def is_access_network_ip(ip_string):
    return ipaddress.ip_address(ip_string) in LAB_ACCESS_NETWORK

def assign_data_ip():
    """Calculate a unique data ip address according to the unique access IP address
    Assigns the data IP address to one of the data network interface."""
    net_info = NetworkInfo()
    network_ifaces = net_info.list_network_interfaces()

    data_interfaces = [iface for iface in network_ifaces.values() if iface._type == "data"]
    if not data_interfaces:
        raise ValueError("no data iface found")

    logging.info(f"data_network_ifaces: {json.dumps(data_interfaces, indent=2)}")

    access_interfaces = [iface for iface in network_ifaces.values() if iface._type == "access"]
    if not access_interfaces:
        raise ValueError("no access iface found")

    logging.info(f"access_network_ifaces: {json.dumps(access_interfaces, indent=2)}")

    # extract the IP address from the LAB network access interface
    access_ip_address = None
    access_interface_name = None
    for iface in access_interfaces:
        if iface.link_detected and iface.ip and is_access_network_ip(iface.ip):
            logging.info(f"detected access iface {iface.name} which has ip {iface.ip}")
            access_ip_address = iface.ip
            access_interface_name = iface.name
            break

    # interface_name = "eth0"  # Replace with your interface name
    # ip_address = get_ip_address(interface_name)
    # if ip_address:
    #     logging.info(f"IP address of {interface_name}: {ip_address}")
    # else:
    if not access_ip_address:
        raise ValueError(f"failed to get IP address for interface {access_interface_name}")

    access_cidr = ipaddress.IPv4Interface(access_ip_address)  # Validate the IP address
    access_ipv4_address = str(access_cidr.ip)
    data_ipv4_address = convert_ip_address(access_ipv4_address)

    logging.info(f"calculated ipv4 data-address: ({data_ipv4_address}) according to ipv4-access address: {access_ipv4_address}")
    assigned_data_ip = False
    for iface in data_interfaces:
        if iface.link_detected:
            logging.info(f"iface_name: {iface.name}, assign ipv4 data-address: ({data_ipv4_address}) according to ipv4-access address: {access_ipv4_address}")
            iface.assign_ip_persistent(data_ipv4_address)
            assigned_data_ip = True
            break

    if not assigned_data_ip:
        logging.error(f"failed to assign ipv4 data-address: ({data_ipv4_address}) according to ipv4-access address: {access_ipv4_address}")


class NetworkInfo(object):

    def list_network_interfaces(self):
        iface_names = run_cmd("ls /sys/class/net").split()
        # filter out loopback and idrac
        network_interface_list = [NetworkInterface(iface_name) for iface_name in iface_names if iface_name != "lo"
                                  and iface_name != "idrac"
                                  and not self._is_usb_interface(iface_name)]

        ifaces = {iface.name: iface for iface in network_interface_list}
        return ifaces

    def _is_usb_interface(self, iface_name: str):
        '''
        if "u" found in the iface name, this a sign that its a usb connection, we dont use that as
        a network device in the lab currently
        https://webhostinggeeks.com/howto/new-naming-scheme-for-the-network-interface-on-rhel-7centos-7/
        :param ifanme: iface name, examle ens01 or enp0s20f0u1u6
        :return: Boolean
        '''
        return 'u' in iface_name
