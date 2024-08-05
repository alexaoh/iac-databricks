# Provision Databricks Workspace Resources

Databricks Workspace resources are provisioned here. In this module, I have placed most resources that only need the [workspace-level](https://registry.terraform.io/providers/databricks/databricks/latest/docs#authenticating-with-azure-cliTerraform) Databricks provider. Thus, a non-exhaustive list of such resources is:

- Databricks Workflow Jobs
- Repos
- Compute
- Access control (on the workspace-level)
- Secret scopes and secrets

I have outlined some examples in this module. For more, [this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/workspace-management) is a good place to start. 
