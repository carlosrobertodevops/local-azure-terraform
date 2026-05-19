# Azure LocalStack Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing AWS Terraform infrastructure to Azure equivalents deployed on LocalStack.

**Architecture:** We will replace the `aws` Terraform provider with `azurerm` and route traffic to LocalStack using the `metadata_host` attribute. The AWS resources (VPC, Subnets, S3, Security Groups, ALB) will be translated to their Azure counterparts (Virtual Network, Subnets, Storage Account/Container, Network Security Group, Application Gateway) within a root Azure Resource Group.

**Tech Stack:** Terraform, LocalStack, AzureRM Provider

---

### Task 1: Update Provider and Variables Configuration

**Files:**
- Modify: `version.tf`
- Modify: `variables.tf`

- [x] **Step 1: Update `version.tf` with the Azure provider**

Replace the entire AWS provider configuration with the AzureRM equivalent, ensuring `metadata_host` points to LocalStack.

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "00000000-0000-0000-0000-000000000000"
  metadata_host   = "localhost.localstack.cloud:4566"
}
```

- [x] **Step 2: Update `variables.tf`**

Replace `aws_region` and `localstack_endpoint` with `azure_location`.

```hcl
variable "azure_location" {
  type    = string
  default = "westeurope"
}

variable "project_name" {
  type    = string
  default = "serverless-elb"
}

variable "stage" {
  type    = string
  default = "local"
}

variable "deployment_bucket_name" {
  type    = string
  default = null
}
```

---

### Task 2: Implement Resource Group and Storage

**Files:**
- Modify: `main.tf`

- [x] **Step 1: Replace S3 bucket with Azure Resource Group and Storage Account**

Remove `aws_s3_bucket.serverless_deployment_bucket` and replace it with:

```hcl
locals {
  name_prefix = "${var.project_name}-${var.stage}"
  # Storage account names must be between 3 and 24 characters and use numbers and lower-case letters only.
  sa_name = replace(lower("${var.project_name}${var.stage}"), "-", "")
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.azure_location
}

resource "azurerm_storage_account" "deployment" {
  name                     = local.sa_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "deployment" {
  name                  = var.deployment_bucket_name != null ? var.deployment_bucket_name : "deployment-container"
  storage_account_name  = azurerm_storage_account.deployment.name
  container_access_type = "private"
}
```

---

### Task 3: Convert Networking Components

**Files:**
- Modify: `main.tf`

- [x] **Step 1: Replace VPC, IGW, and Route Tables with Virtual Network and Subnets**

Remove `aws_vpc`, `aws_internet_gateway`, `aws_route_table`, `aws_route`, and `aws_route_table_association` resources. In Azure, Virtual Networks handle routing implicitly. Application Gateway requires a dedicated subnet.

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "public_a" {
  name                 = "${local.name_prefix}-public-a"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "public_b" {
  name                 = "${local.name_prefix}-public-b"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.2.0/24"]
}

# Azure Application Gateway requires a dedicated subnet
resource "azurerm_subnet" "appgw_subnet" {
  name                 = "${local.name_prefix}-appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.3.0/24"]
}
```

- [x] **Step 2: Replace Security Group with Network Security Group**

Remove `aws_security_group.alb` and replace with `azurerm_network_security_group`.

```hcl
resource "azurerm_network_security_group" "alb" {
  name                = "${local.name_prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
```

---

### Task 4: Convert Load Balancer

**Files:**
- Modify: `main.tf`

- [x] **Step 1: Replace AWS ALB with Azure Application Gateway**

Remove `aws_lb` and `aws_lb_listener.http`. Replace with a Public IP and an Application Gateway (the Layer 7 equivalent to AWS ALB).

```hcl
resource "azurerm_public_ip" "appgw" {
  name                = "${local.name_prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "app" {
  name                = "${local.name_prefix}-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }

  frontend_port {
    name = "frontend-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-configuration"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "backend-pool"
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "frontend-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "http-settings"
  }
}
```

---

### Task 5: Update Outputs

**Files:**
- Modify: `outputs.tf`

- [x] **Step 1: Replace AWS specific outputs with Azure equivalents**

```hcl
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.deployment.name
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "appgw_id" {
  value = azurerm_application_gateway.app.id
}
```

- [x] **Step 2: Validate the Terraform Configuration**

Run format and validation commands to verify correctness:
```bash
terraform fmt
terraform validate
```