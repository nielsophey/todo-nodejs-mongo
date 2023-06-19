@description('Location of the Dev Center. If none is provided, the resource group location is used.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(26)
@description('Name of the Dev Center')
param name string

@description('Name of the Key Vault to create to hold the GitHub PAT token used to access the catalog.')
param keyVaultName string

@secure()
@description('Personal Access Token from GitHub with the repo scope on the repo containing the catalog.')
param githubPat string

@description('URI to the GitHub repo containing the catalog.')
param catalogUri string

@description('Branch of the GitHub repo containing the catalog.')
param catalogBranch string = 'main'

@description('Relative path to the catalog items in the catalog repo.')
param catalogPath string

param catalogName string = 'Catalog'

@description('An object with property keys containing the Environment Type name and values containing Subscription and Description properties.')
param environmentTypes object

@description('Tags to apply to the resources')
param tags object = {}

// docs: https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-secrets-officer
var secretsAssignmentId = guid('keyvaultsecretofficer', resourceGroup().id, keyVaultName, name)
var secretsOfficerRoleResourceId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')

// create the dev center
resource devCenter 'Microsoft.DevCenter/devcenters@2023-04-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
}

// create the catalog
resource catalog 'Microsoft.DevCenter/devcenters/catalogs@2023-04-01' = {
  parent: devCenter
  name: catalogName
  properties: {
    gitHub: {
      uri: catalogUri
      branch: catalogBranch
      path: catalogPath
      secretIdentifier: githubPatSecret.properties.secretUri
    }
  }
}

// create the dev center level environment types
resource envTypes 'Microsoft.DevCenter/devcenters/environmentTypes@2023-04-01' = [for envType in items(environmentTypes): {
  parent: devCenter
  name: envType.key
  properties: {}
}]

// create a key vault to hold our pat token used to access the catalog
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
  tags: tags
}

// assign dev center identity secrets officer role on key vault
resource keyVaultAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: secretsAssignmentId
  properties: {
    principalId: devCenter.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: secretsOfficerRoleResourceId
  }
  scope: keyVault
}

// add the github pat token to the key vault
resource githubPatSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  name: 'github-pat'
  parent: keyVault
  properties: {
    value: githubPat
    attributes: {
      enabled: true
    }
  }
  tags: tags
}

output devCenterId string = devCenter.id
output devCenterName string = devCenter.name
output devCenterPrincipalId string = devCenter.identity.principalId
