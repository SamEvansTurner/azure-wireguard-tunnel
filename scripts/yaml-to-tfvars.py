#!/usr/bin/env python3
"""
Convert config.yml to Terraform tfvars format.

Only outputs infrastructure variables needed by Terraform.
Application configuration (WireGuard, Caddy, etc.) is handled by Ansible.

Usage:
    python3 yaml-to-tfvars.py config.yml > terraform/terraform.tfvars
    python3 yaml-to-tfvars.py config.yml --output terraform/terraform.tfvars
"""

import sys
import os
import argparse

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def to_hcl_value(value, indent=0):
    """Convert a Python value to HCL format."""
    if value is None:
        return '""'
    elif isinstance(value, bool):
        return 'true' if value else 'false'
    elif isinstance(value, int) or isinstance(value, float):
        return str(value)
    elif isinstance(value, str):
        # Escape quotes and backslashes
        value = value.replace('\\', '\\\\').replace('"', '\\"')
        return f'"{value}"'
    elif isinstance(value, list):
        if not value:
            return '[]'
        items = [to_hcl_value(item, indent + 2) for item in value]
        return '[' + ', '.join(items) + ']'
    elif isinstance(value, dict):
        if not value:
            return '{}'
        indent_str = ' ' * (indent + 2)
        items = []
        for k, v in value.items():
            items.append(f'{indent_str}{k} = {to_hcl_value(v, indent + 2)}')
        return '{\n' + '\n'.join(items) + '\n' + ' ' * indent + '}'
    else:
        return f'"{value}"'


def yaml_to_tfvars(config):
    """Convert YAML config dict to Terraform tfvars string.
    
    Only outputs infrastructure variables needed by Terraform:
    - Azure location, resource group, VM size
    - SSH config (admin user, key path, allowed IPs)
    - Network config (vnet, subnet)
    - WireGuard port (for NSG rule)
    - Tags
    """
    lines = [
        '# Auto-generated from config.yml',
        '# Do not edit directly - modify config.yml instead',
        '#',
        '# Only infrastructure variables are included here.',
        '# Application config (WireGuard, Caddy, etc.) is handled by Ansible.',
        '',
    ]

    # Azure configuration
    if 'azure' in config:
        azure = config['azure']
        if azure.get('location'):
            lines.append(f'location = {to_hcl_value(azure["location"])}')
        if azure.get('resource_group'):
            lines.append(f'resource_group_name = {to_hcl_value(azure["resource_group"])}')
        if azure.get('vm_size'):
            lines.append(f'vm_size = {to_hcl_value(azure["vm_size"])}')
        if 'use_static_ip' in azure:
            lines.append(f'use_static_ip = {to_hcl_value(azure["use_static_ip"])}')
        if azure.get('availability_zones'):
            lines.append(f'availability_zones = {to_hcl_value(azure["availability_zones"])}')
        lines.append('')

    # SSH configuration
    if 'ssh' in config:
        ssh = config['ssh']
        if ssh.get('admin_username'):
            lines.append(f'admin_username = {to_hcl_value(ssh["admin_username"])}')
        if ssh.get('public_key_path'):
            lines.append(f'ssh_public_key_path = {to_hcl_value(ssh["public_key_path"])}')
        if ssh.get('allowed_ipv4'):
            lines.append(f'allowed_ssh_ipv4 = {to_hcl_value(ssh["allowed_ipv4"])}')
        if 'allowed_ipv6' in ssh:
            lines.append(f'allowed_ssh_ipv6 = {to_hcl_value(ssh["allowed_ipv6"])}')
        lines.append('')

    # Network configuration (only vnet/subnet for Terraform)
    if 'network' in config:
        net = config['network']
        if net.get('vnet_address_space'):
            lines.append(f'vnet_address_space = {to_hcl_value(net["vnet_address_space"])}')
        if net.get('subnet_address'):
            lines.append(f'subnet_address = {to_hcl_value(net["subnet_address"])}')
        lines.append('')

    # WireGuard port (only for NSG rule - full config handled by Ansible)
    if 'wireguard' in config:
        wg = config['wireguard']
        if wg.get('port'):
            lines.append(f'wireguard_port = {to_hcl_value(wg["port"])}')
        lines.append('')

    # Tags
    if 'tags' in config:
        lines.append(f'tags = {to_hcl_value(config["tags"])}')
        lines.append('')

    return '\n'.join(lines)


def validate_config(config):
    """Validate required configuration values."""
    errors = []

    # Required fields for Terraform
    required = [
        ('ssh.admin_username', config.get('ssh', {}).get('admin_username')),
        ('ssh.allowed_ipv4', config.get('ssh', {}).get('allowed_ipv4')),
    ]

    for path, value in required:
        if not value or value == 'CHANGEME' or value == 'CHANGEME/32':
            errors.append(f"  - {path}: not set or still CHANGEME")

    # Validation rules
    ssh = config.get('ssh', {})
    if ssh.get('admin_username') in ['admin', 'root', 'azureuser', 'ubuntu', 'administrator']:
        errors.append(f"  - ssh.admin_username: cannot be a common default name")

    if ssh.get('allowed_ipv4') and not ssh['allowed_ipv4'].endswith('/32'):
        errors.append(f"  - ssh.allowed_ipv4: must end with /32")

    return errors


def main():
    parser = argparse.ArgumentParser(description='Convert config.yml to Terraform tfvars')
    parser.add_argument('config_file', help='Path to config.yml')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    parser.add_argument('--validate', '-v', action='store_true', help='Validate config only')
    args = parser.parse_args()

    # Load YAML config
    try:
        with open(args.config_file, 'r') as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: Config file not found: {args.config_file}", file=sys.stderr)
        print("Copy config.yml.example to config.yml and customize it.", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML: {e}", file=sys.stderr)
        sys.exit(1)

    # Validate
    errors = validate_config(config)
    if errors:
        print("Configuration errors:", file=sys.stderr)
        for error in errors:
            print(error, file=sys.stderr)
        if args.validate:
            sys.exit(1)
        print("\nContinuing anyway (Terraform will also validate)...", file=sys.stderr)
    elif args.validate:
        print("Configuration is valid.")
        sys.exit(0)

    # Convert to tfvars
    tfvars = yaml_to_tfvars(config)

    # Output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(tfvars)
        print(f"Generated: {args.output}", file=sys.stderr)
    else:
        print(tfvars)


if __name__ == '__main__':
    main()
