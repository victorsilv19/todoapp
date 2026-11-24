terraform {
  cloud {
    organization = "todoapp-pm4"

    workspaces {
      tags = {
        application = "pm04-todoapp"
      }
    }
  }
}
