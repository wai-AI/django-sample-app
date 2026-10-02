variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-central-1"
}

variable "repository_name" {
  description = "The name of the repository to create"
  type        = string
  default     = "week6-docker"
}

variable "availability_zones" {
  description = "The availability zones to deploy resources in; keep their order stable because subnets use count indices"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]

  validation {
    condition = (
      length(var.availability_zones) >= 2 &&
      length(var.availability_zones) <= 10 &&
      length(distinct(var.availability_zones)) == length(var.availability_zones)
    )
    error_message = "Choose 2 to 10 distinct AZs. The limit prevents public and private CIDR ranges from overlapping."
  }
}
