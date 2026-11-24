terraform {
  cloud {
    organization = "todoapp-pm4"

    workspaces {
      prefix = "pm04-todoapp-"
    }
  }
}
