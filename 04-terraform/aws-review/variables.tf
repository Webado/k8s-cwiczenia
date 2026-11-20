variable "environment" {
  type    = string
  default = "production"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}
