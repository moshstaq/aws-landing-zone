# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-platform"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# Enables internet access for public subnets.
# One per VPC — no AZ dependency.

resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "igw-platform"
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
# One per AZ. Resources here can receive inbound internet traffic.
# map_public_ip_on_launch enables automatic public IP assignment.

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.platform.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "snet-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
# One per AZ. No inbound internet access.
# Outbound internet via NAT Gateway only.

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.platform.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "snet-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ── Elastic IP for NAT Gateway ────────────────────────────────────────────────
# NAT Gateway requires a static public IP.
# Single EIP — one NAT Gateway per ADR-003.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "eip-nat-platform"
  }

  depends_on = [aws_internet_gateway.platform]
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
# Sits in the first public subnet.
# Enables private subnets to reach the internet for outbound traffic.
# Single NAT Gateway — cost constraint documented in ADR-003.
# Production recommendation: one NAT Gateway per AZ.

resource "aws_nat_gateway" "platform" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "nat-platform"
  }

  depends_on = [aws_internet_gateway.platform]
}

# ── Public Route Table ────────────────────────────────────────────────────────
# Routes internet-bound traffic to the Internet Gateway.
# Associated with all public subnets.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.platform.id
  }

  tags = {
    Name = "rt-public-platform"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ───────────────────────────────────────────────────────
# Routes internet-bound traffic to the NAT Gateway.
# Associated with all private subnets.

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.platform.id
  }

  tags = {
    Name = "rt-private-platform"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
