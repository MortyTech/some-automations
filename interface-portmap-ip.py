import subprocess
import csv

# Helper function to run a shell command and capture the output
def run_command(command):
    return subprocess.check_output(command, shell=True, text=True).strip()

# Function to get IP and interface status from `ip -br a`
def get_interface_data():
    interface_data = {}
    ip_output = run_command("ip -br a")
    for line in ip_output.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        interface = parts[0]
        status = parts[1]
        ip_info = next((part for part in parts[2:] if '/' in part), "N/A")
        interface_data[interface] = {
            "status": status,
            "ip": ip_info if "fe80::" not in ip_info else "N/A"  # exclude IPv6
        }
    return interface_data

# Function to determine physical, bond, and VLAN interfaces
def get_sorted_interfaces():
    physical_interfaces = []
    bond_interfaces = []
    vlan_interfaces = []

    sys_class_output = run_command("ls -l /sys/class/net/ | egrep 'vlan|bond|pci|br' | grep -v bonding_masters | awk {'print $9'}")
    for interface in sys_class_output.splitlines():
        if "vlan" in interface:
            # Capture the VLAN interface with its master (e.g., `vlan1000@bond0`)
            matching_interfaces = run_command(f"ip -br a | grep {interface}").splitlines()
            if matching_interfaces:
                vlan_interfaces.append(matching_interfaces[0].split()[0])  # Full VLAN name with master
        elif "bond" in interface:
            bond_interfaces.append(interface)
        else:
            physical_interfaces.append(interface)
    
    return physical_interfaces, bond_interfaces, vlan_interfaces

# Function to get the LLDP neighbor (PortDescr) for physical interfaces
def get_neighbor(interface):
    try:
        lldp_output = run_command(f"lldpctl show neighbors ports {interface}")
        for line in lldp_output.splitlines():
            if "PortDescr:" in line:
                return line.split("PortDescr:")[1].strip()
    except subprocess.CalledProcessError:
        return "N/A"
    return "N/A"

# Main function to generate CSV
def generate_interface_csv(hostname):
    interface_data = get_interface_data()
    physical_interfaces, bond_interfaces, vlan_interfaces = get_sorted_interfaces()

    # Prepare CSV rows
    csv_rows = []

    # Process physical interfaces
    for interface in physical_interfaces:
        neighbor = get_neighbor(interface)
        row = [
            hostname,
            interface,
            interface_data.get(interface, {}).get("ip", "N/A"),
            interface_data.get(interface, {}).get("status", "N/A"),
            neighbor
        ]
        csv_rows.append(row)

    # Process bond interfaces
    for interface in bond_interfaces:
        row = [
            hostname,
            interface,
            interface_data.get(interface, {}).get("ip", "N/A"),
            interface_data.get(interface, {}).get("status", "N/A"),
            "N/A"  # No direct neighbor for bond interfaces
        ]
        csv_rows.append(row)

    # Process VLAN interfaces
    for interface in vlan_interfaces:
        row = [
            hostname,
            interface,
            interface_data.get(interface, {}).get("ip", "N/A"),
            interface_data.get(interface, {}).get("status", "N/A"),
            "N/A"  # No direct neighbor for VLAN interfaces
        ]
        csv_rows.append(row)

    # Write to CSV
    csv_filename = f"{hostname}_interfaces.csv"
    with open(csv_filename, mode='w') as file:
        writer = csv.writer(file)
        writer.writerow(["Host", "Interface", "IP", "Status", "Neighbor"])
        writer.writerows(csv_rows)

    print(f"CSV file generated: {csv_filename}")

# Example usage
hostname = run_command("hostname")
generate_interface_csv(hostname)
