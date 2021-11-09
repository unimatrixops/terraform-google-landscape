

variable "database" {}
variable "instance" {}
variable "service" {}
variable "service_account" {}


output "env" {
  description="Environment variables defined by this module."
  value={
    DB_ENGINE={
      kind="variable"
      value=var.instance.engine
    }
    DB_HOST={
      kind="variable"
      value=var.instance.host
    }
    DB_PORT={
      kind="variable"
      value="${var.instance.port}"
    }
    DB_NAME={
      kind="variable"
      value=var.database
    }
    # These are for use with Cloud IAM for SQL.
    #DB_HOST={
    #  kind="variable"
    #  value="127.0.0.1"
    #}
    #DB_USERNAME={
    #  kind="variable"
    #  value=trimsuffix(var.service_account, ".gserviceaccount.com")
    #}
  }
}
