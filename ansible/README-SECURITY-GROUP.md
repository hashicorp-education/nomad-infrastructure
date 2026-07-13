# AWS security group management for Nomad infrastructure

This playbook allows you to dynamically add custom ingress rules to the AWS security group created by Terraform for the Nomad infrastructure. It provides a flexible, safe way to open additional ports for your applications without modifying Terraform configuration.

## Overview

The `update-security-group.yaml` playbook:
- Adds custom ingress rules to the existing security group
- Preserves all existing rules (non-destructive)
- Checks for duplicate rules before adding
- Supports flexible port and description configuration
- Works with the nomad-infra project's security group structure
- Provides detailed feedback and usage instructions

## Prerequisites

### 1. Install required Ansible collection

```bash
ansible-galaxy collection install amazon.aws
```

### 2. Install Python dependencies

```bash
pip install boto3 botocore
```

Or if using a virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate
pip install boto3 botocore
```

### 3. Configure AWS credentials

Choose one of the following methods:

**Option A: AWS CLI** (Recommended)
```bash
aws configure
```

**Option B: Environment Variables**
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-2"
```

**Option C: AWS Profile**
```bash
export AWS_PROFILE="your-profile-name"
```

**Option D: IAM Role** (if running on EC2 instance)
- No configuration needed, uses instance IAM role

### 4. Verify Terraform infrastructure

Ensure your Nomad infrastructure has been deployed:
```bash
cd ../terraform/aws
terraform output security_group_id
```

## Usage

### Basic usage - add default port (9002)

```bash
cd ansible
ansible-playbook update-security-group.yaml
```

This adds an ingress rule for port 9002 (default) with the description "Custom application port".

### Add custom port

```bash
ansible-playbook update-security-group.yaml \
  -e custom_port=8080 \
  -e custom_port_description="Web Application"
```

### Add multiple ports

Run the playbook multiple times with different ports:

```bash
# Add port 9002 for Countdash
ansible-playbook update-security-group.yaml \
  -e custom_port=9002 \
  -e custom_port_description="Countdash web app"

# Add port 8080 for Admin UI
ansible-playbook update-security-group.yaml \
  -e custom_port=8080 \
  -e custom_port_description="Admin UI"

# Add port 3000 for API
ansible-playbook update-security-group.yaml \
  -e custom_port=3000 \
  -e custom_port_description="REST API"
```

### Use different AWS region

```bash
ansible-playbook update-security-group.yaml \
  -e aws_region=us-west-2
```

### Use different project name

If you customized the project name in Terraform:

```bash
ansible-playbook update-security-group.yaml \
  -e project_name=my-nomad-cluster
```

### Use environment variables

```bash
export AWS_REGION=us-east-2
export PROJECT_NAME=nomad-consul
export CUSTOM_PORT=9002
export CUSTOM_PORT_DESC="Countdash web app"

ansible-playbook update-security-group.yaml
```

### Combine multiple options

```bash
ansible-playbook update-security-group.yaml \
  -e aws_region=us-west-2 \
  -e project_name=my-cluster \
  -e custom_port=8080 \
  -e custom_port_description="Custom App"
```

## What the playbook does

### Step-by-step process

1. **Lookup Security Group**: Finds the security group by tag `Name: {project_name}-sg`
2. **Retrieve Configuration**: Gets current security group rules and settings
3. **Check for Duplicates**: Verifies if the port already exists in the security group
4. **Display Status**: Shows whether the port will be added or already exists
5. **Add Rule** (if needed): Adds the ingress rule without removing existing rules
6. **Report Results**: Displays success message or indicates no changes needed
7. **Show Instructions**: Provides usage examples for future reference

### Security group rule format

Each rule added includes:
- **Protocol**: TCP
- **Port Range**: Single port (from_port = to_port)
- **Source**: 0.0.0.0/0 (all IPs) - see security considerations below
- **Description**: Custom description for the rule

## Configuration options

### Default values

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-2` | AWS region (matches nomad-infra default) |
| `project_name` | `nomad-consul` | Project name (matches Terraform default) |
| `custom_port` | `9002` | Port to add to security group |
| `custom_port_description` | `Custom application port` | Description for the rule |

### Override methods

**Command Line** (Recommended):
```bash
ansible-playbook update-security-group.yaml -e custom_port=8080
```

**Environment Variables**:
```bash
export CUSTOM_PORT=8080
ansible-playbook update-security-group.yaml
```

## Security considerations

### Important security notes

1. **Default CIDR is 0.0.0.0/0**: The playbook adds rules that allow access from anywhere. This is convenient for development but **not recommended for production**.

2. **Restrict Access in Production**: For production environments, modify the playbook to use specific IP ranges:

   ```yaml
   # Edit update-security-group.yaml
   cidr_ip: 10.0.0.0/8  # Internal network only
   # or
   cidr_ip: 203.0.113.0/24  # Your office network
   # or
   cidr_ip: 203.0.113.42/32  # Single IP address
   ```

3. **Use VPN or Bastion**: Consider accessing applications through:
   - VPN connection to your VPC
   - Bastion host/jump server
   - AWS Systems Manager Session Manager

4. **Regular Audits**: Periodically review security group rules:
   ```bash
   aws ec2 describe-security-groups \
     --group-names nomad-consul-sg \
     --region us-east-2
   ```

5. **Principle of Least Privilege**: Only open ports that are absolutely necessary

### Best practices

- **Document Rules**: Use descriptive names for each port
- **Remove Unused Rules**: Clean up rules for decommissioned applications
- **Use Security Groups Wisely**: Consider creating separate security groups for different application tiers
- **Enable VPC Flow Logs**: Monitor network traffic for security analysis
- **Implement WAF**: Use AWS WAF for web applications
- **Enable CloudTrail**: Audit all security group changes

## Troubleshooting

### Error: Security group not found

**Problem**: 
```
Security group nomad-consul-sg not found in region us-east-2
```

**Solutions**:
1. Verify the project name matches your Terraform deployment:
   ```bash
   cd ../terraform/aws
   terraform output security_group_id
   ```

2. Check the AWS region is correct:
   ```bash
   aws ec2 describe-security-groups --region us-east-2
   ```

3. Ensure Terraform has been applied successfully:
   ```bash
   cd ../terraform/aws
   terraform plan
   ```

---

### Error: Insufficient permissions

**Problem**:
```
An error occurred (UnauthorizedOperation) when calling the DescribeSecurityGroups operation
```

**Solution**: Ensure your AWS credentials have the following permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:DescribeSecurityGroupRules"
      ],
      "Resource": "*"
    }
  ]
}
```

---

### Error: Module not found

**Problem**:
```
ERROR! couldn't resolve module/action 'amazon.aws.ec2_security_group_info'
```

**Solution**: Install the amazon.aws collection:
```bash
ansible-galaxy collection install amazon.aws
```

---

### Error: boto3 not found

**Problem**:
```
boto3 required for this module
```

**Solution**: Install boto3 and botocore:
```bash
pip install boto3 botocore
```

---

### Error: Premature end of stream (sudo password required)

**Problem**:
```
sudo: a password is required
```

**Solution**: This is already fixed in the updated playbook. The playbook now has `become: false` which prevents it from trying to use sudo for localhost AWS API calls.

If you still see this error, verify you're using the latest version of the playbook.

---

### Port Already Exists

**Behavior**: If the port already exists, the playbook will:
- Detect the duplicate
- Display a message: "Port XXXX ingress rule already exists"
- Skip adding the rule
- Exit successfully (no changes made)

This is **expected behavior** and indicates the playbook is working correctly.

---

### Verify Changes

After running the playbook, verify the rule was added:

```bash
# Using AWS CLI
aws ec2 describe-security-groups \
  --group-names nomad-consul-sg \
  --region us-east-2 \
  --query 'SecurityGroups[0].IpPermissions'

# Using Terraform
cd ../terraform/aws
terraform refresh
terraform output security_group_id
```

## Advanced Usage

### Restrict to specific IP range

Edit the playbook to restrict access:

```yaml
# In update-security-group.yaml, modify the rules section:
rules:
  - proto: tcp
    from_port: "{{ custom_port }}"
    to_port: "{{ custom_port }}"
    cidr_ip: 10.0.0.0/8  # Change this line
    rule_desc: "{{ custom_port_description }}"
```

### Add multiple ports in one run

Create a wrapper script:

```bash
#!/bin/bash
# add-multiple-ports.sh

PORTS=(9002 8080 3000)
DESCRIPTIONS=("Countdash" "Admin UI" "API")

for i in "${!PORTS[@]}"; do
  ansible-playbook update-security-group.yaml \
    -e custom_port="${PORTS[$i]}" \
    -e custom_port_description="${DESCRIPTIONS[$i]}"
done
```

### Integration with CI/CD

```yaml
# .github/workflows/deploy.yml
- name: Add application port to security group
  run: |
    ansible-playbook ansible/update-security-group.yaml \
      -e custom_port=${{ secrets.APP_PORT }} \
      -e custom_port_description="Application Port"
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    AWS_REGION: us-east-2
```

## Cleanup

### Remove a Port Rule

To remove a port, use the AWS CLI or Terraform:

**Using AWS CLI**:
```bash
# Get the security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=nomad-consul-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region us-east-2)

# Revoke the ingress rule
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 9002 \
  --cidr 0.0.0.0/0 \
  --region us-east-2
```

**Using Terraform** (Recommended):
Add the rule to your Terraform configuration for better infrastructure management.

## Related documentation

- [Main Project README](../README.md)
- [Ansible Configuration](README.md)
- [Terraform AWS Configuration](../terraform/aws/README.md)
- [AWS Security Groups Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)

## Examples

### Example 1: Add Countdash application port

```bash
ansible-playbook update-security-group.yaml \
  -e custom_port=9002 \
  -e custom_port_description="Countdash web application"
```

**Output**:
```
TASK [Display security group update result]
ok: [localhost] => {
    "msg": [
        "✓ Security group nomad-consul-sg updated successfully",
        "✓ Added ingress rule for port 9002",
        "✓ Description: Countdash web application"
    ]
}
```

### Example 2: Add multiple application ports

```bash
# Web frontend
ansible-playbook update-security-group.yaml \
  -e custom_port=3000 \
  -e custom_port_description="React Frontend"

# API backend
ansible-playbook update-security-group.yaml \
  -e custom_port=8080 \
  -e custom_port_description="REST API"

# Metrics endpoint
ansible-playbook update-security-group.yaml \
  -e custom_port=9090 \
  -e custom_port_description="Prometheus Metrics"
```

### Example 3: Different region and project

```bash
ansible-playbook update-security-group.yaml \
  -e aws_region=eu-west-1 \
  -e project_name=prod-nomad \
  -e custom_port=8443 \
  -e custom_port_description="HTTPS API"
```

## Contributing

When modifying this playbook:

1. Test changes in a development environment first
2. Update this README with any new features or changes
3. Follow Ansible best practices
4. Document any new variables or options
5. Consider security implications of changes

## License

This playbook is part of the nomad-infra project.

BSD 2-Clause License - see [LICENSE](../LICENSE) file for details.

Copyright (c) 2026, Aimee Ukasick