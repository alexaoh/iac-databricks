# Provision Unity Catalog and Azure Databricks with Terraform

This repo contains a minimal example, or a starting point if you wish, of how Unity Catalog (UC) and a Databricks Workspace can be provisioned (on Azure) through Terraform. It does not contain all the bells and whistles ([list](#improvements-and-further-work) of improvements), but it could hopefully be used as a starting point. Notice that, in addition to UC and a Databricks Workspace, some Azure resources are also created: storage account and key vault. These are mapped to a catalog and a secret scope in Databricks/UC, respectively.

In order to authenticate Terraform to Azure and to store the state remotely, certain steps need to be performed manually (e.g. through the Azure portal or through the Azure CLI) before provisioning the rest of the infrastructure. This process is described in the following. 

## Manual steps before provisioning through IaC
1. **Remote state**: We want to store the Terraform state file [remotely](https://developer.hashicorp.com/terraform/language/state/remote). In order to achieve this, we manually create a resource group, storage account and container (in a subscription of choice) with the following attributes: 
    1. Resource group name: `iac-databricks-tfstate-rg`
    2. Storage account name: `iacdatabrickstfstatest`
    3. Container name: `tfstate`
    4. Location: `northeurope`

2. **Authentication and authorization**: Authenticate and authorize Terraform to Azure. This can be done in many [different ways](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure) ([authenticate](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm) to `azurerm` backend storage account). In our case, we chose to authenticate with a user-assigned managed identity with OIDC and a federated identity credential (inspired by the Azure Login GitHub Action's [recommended authentication](https://github.com/Azure/login?tab=readme-ov-file#login-with-openid-connect-oidc-recommended)). The main reason behind using a user-assigned managed identity (e.g. instead of using a service principal) is that we want to avoid handling secrets. Moreover, we want to use GitHub Actions workflows to deploy the resource (more context from Azure and GitHub integration [documentation](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Clinux)). Anyhow, this means that we need to perform the following steps:
    1. [Create](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-manage-user-assigned-managed-identities?pivots=identity-mi-methods-azp#create-a-user-assigned-managed-identity) a user-assigned managed identity resource in the same resource group as in step 1 above. 
    2. Configure it to have the `Contributor` role on the subscription, as well as the `Storage Blob Data Contributor` on the storage account from step 1 above. 
    3. Add a [federated credential](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity?pivots=identity-wif-mi-methods-azp#github-actions-deploying-azure-resources) to the managed identity, to authenticate with GitHub's OIDC provider. We use `Environment` as the `Entity type` and create an environment called `production` in our repository. This is used in the [workflows](.github/workflows/). Moreover, we create a second federated credential for an environment called `testing`, that is meant to be used for CI pipelines, while `production` is meant for deployment pipelines. Note that good practice would most likely be to configure an entirely different managed identity with a federated credential for a separate testing (compute/cloud) environment, but, for simplicity, we have not done this here.

*Note*: This user-assigned managed identity cannot be used to authenticate Terraform to Azure locally (e.g. from your local computer). If you want a setup where you can both login locally with Azure CLI and in GitHub Actions, you should instead authenticate with a service principal through the Azure CLI (or with a personal account). 

Once these steps have been performed, the necessary environment variables need to be set. Notice that these are set in the GitHub Actions workflows we refer to in this guide already, more precisely [this workflow](https://github.com/Alv-no/iac-databricks/blob/main/.github/workflows/tf_ci_cd_callable.yml).

3. **Environment variables**: Set the necessary environment variables:
    - ARM_SUBSCRIPTION_ID: Azure Subscription ID.
    - ARM_TENANT_ID: Azure Tenant ID.
    - ARM_CLIENT_ID: Client ID of the user-assigned managed identity.
    - ARM_USE_OIDC: Should be set to 'true' for runners in GitHub Actions, since we chose to authenticate using OIDC. 
    - ARM_USE_AZUREAD: Should be set to 'true', such that the Terraform backend uses the Access Token of the Entra ID (Azure AD) principal to authenticate to the state file storage account. [More details](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm#authentication).
    - TF_VAR_...: Environment variables that [map](https://developer.hashicorp.com/terraform/language/values/variables#environment-variables) to input variables in Terraform.
        - TF_VAR_databricks_account_id: Databricks [Account](https://learn.microsoft.com/en-us/azure/databricks/admin/account-settings/) ID.
        - *Note*: [Variable precedence](https://developer.hashicorp.com/terraform/language/values/variables#variable-definition-precedence): This means that environment variables will be ignored when `terraform.tfvars` is present, since the latter has higher precedence. In our case, we choose to supply `terraform apply` with the variable file `tfstatevars.tfvars` (which matches the backend configuration in `backend.azurerm.tfbackend`), in addition to defining one `terraform.tfvars` in each module. In this way, we only need to define the backend storage configuration for azurerm once (actually: in the two mentioned files) in the root directory. If you would like to use environment variables of the form `TF_VAR_...` to pass variables to Terraform, remove the `terraform.tfvars` file. 


## Order of Provisioning Resources
After the manual processes are performed (and the necessary environment variables are set), the following list details the order in which the components in the infrastructure are provisioned: 
1. [Resource Group](./global/resource_group/)
2. [Storage Account](./global/storage_account/)
3. [Key Vault](./global/key_vault/)
4. [Unity Catalog Resources](./global/unity_catalog_metastore/)
5. [Databricks Workspace](./global/data_platform/)
6. [Databricks Specific Resources](./data_platform_resources/)

This process is [automated](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform?utm_source=WEBSITE&utm_medium=WEB_IO&utm_offer=ARTICLE_PAGE&utm_content=DOCS) with [GitHub Actions](.github/workflows/), which can be triggered manually or through a PR. 

*NOTE*: The automation is not completely fool-proof/robust as of now. I have not spent anymore time on this. However, when running the initial deployment via the CD-pipelines, I also had to: 
- give the user-assigned managed identity we created above a `Owner` role on the resource group we provision, to be able to assign the `Storage Blob Data Contributor` to the Databricks Access Connector,
- and make a service principal in the Databricks [account console](https://accounts.azuredatabricks.net/) for the same managed identity and make it `account admin`. This was necessary in order to create the metastore, a task that demands account admin rights, as well as to create the account level user groups, service principal and to set the group as account admin. This role can later be removed (after the initial setup is done), if you wish. The number of account admins should be limited.

## Improvements and Further Work
As noted, this example configuration does not include all infrastructure that should be included in a production setup. The following is a non-exhaustive list of recommendations for further work: 
- Public network access is allowed to the storage account that holds the Terraform statefile. Access should be restricted to this storage account in a production environment, through e.g. [firewalls and virtual networks](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security?tabs=azure-portal).
- Further and more robust CI/CD pipelines for integration, unit, compliance and end-to-end testing of code and infrastructure could be created. E.g. read [here](https://learn.microsoft.com/en-us/azure/developer/terraform/best-practices-testing-overview) for more details on testing Terraform code.
- Fool-proofing of GitHub Actions workflows (+ authentication and authorization) should be investigated for complete automation of *initial* infrastructure deployment. However, they work OK after the initial deployment has been performed.
- Roles/permissions/grants in Azure and in the Databricks Workspace has mostly not been provisioned here. This should also be defined with IaC (e.g. through the [azuread](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs) provider)
    - [SCIM provisioning](https://learn.microsoft.com/en-us/azure/databricks/admin/users-groups/users#sync-users-to-your-azure-databricks-account-from-your-microsoft-entra-id-formerly-azure-active-directory-tenant) for instance.
    - Moreover, I have not given any other users access to the workspace. This could be done in the Terraform configuration as well (or manually through the account console if you have account admin rights).
- Security, networking, etc: these are topics that go mostly unconsidered in this setup. Check out [this repo](https://github.com/databricks/terraform-databricks-sra/tree/main/azure) for inspiration.
- +++
