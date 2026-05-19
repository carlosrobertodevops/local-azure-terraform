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
