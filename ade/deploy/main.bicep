@description('Location of the resources. If none is provided, the resource group location is used.')
param location string = resourceGroup().location

@description('Name of the DevCenter')
param devCenterName string

@description('Name of the Project')
param projectName string

@description('The principal ids of users to assign the role of DevCenter Project Admin.')
param projectAdmins array

@description('The principal id of the CI identity. This identity well be assigned the subscription reader role to all environment type subscriptions. Note: this is not the appId')
param ciPrincipalId string

@secure()
@description('Personal Access Token from GitHub with the repo scope on the repo containing the catalog.')
param githubPat string

@description('URI to the GitHub repo containing the catalog.')
param catalogUri string

@description('Branch of the GitHub repo containing the catalog.')
param catalogBranch string = 'main'

@description('Relative path to the catalog items in the catalog repo.')
param catalogPath string

@description('An object with property keys containing the Environment Type name and values containing Subscription and Description properties.')
param environmentTypes object = {
  Dev: ''
  Test: ''
  Prod: ''
}

@description('Tags to apply to the resources')
param tags object = {}

// the dev center identity must be an owner on the dev center subscription as well as
// the subscription. since environment types could use the same subscriptions, or even
// use the dev center subscription, we need to create a list of unique subscriptions
var subscriptions = filter(reduce(map(items(environmentTypes), t => [ t.value ]), [ subscription().subscriptionId ], (cur, next) => union(cur, next)), s => !empty(s))

// clean up the keyvault name an add a suffix to ensure it's unique
var keyVaultNameStart = replace(replace(replace(toLower(trim(devCenterName)), ' ', '-'), '_', '-'), '.', '-')
var keyVaultNameAlmost = length(keyVaultNameStart) <= 24 ? keyVaultNameStart : take(keyVaultNameStart, 24)
var keyVaultName = '${keyVaultNameAlmost}kv'

module devCenter 'devcenter.bicep' = {
  name: 'devcenter'
  params: {
    name: devCenterName
    keyVaultName: keyVaultName
    githubPat: githubPat
    environmentTypes: environmentTypes
    catalogUri: catalogUri
    catalogBranch: catalogBranch
    catalogPath: catalogPath
    location: location
    tags: tags
  }
}

module project 'project.bicep' = {
  name: 'project'
  params: {
    devCenterName: devCenter.outputs.devCenterName
    name: projectName
    description: 'React web app with a Node.js API and a MongoDB'
    location: location
    environmentTypes: environmentTypes
    ciPrincipalId: ciPrincipalId
    projectAdmins: projectAdmins
    tags: tags
  }
}

// assign dev center identity owner role on the dev center
// subscription and all environment type subscriptions
module devCenterSubscriptionRoles 'subscriptionRole.bicep' = [for subscriptionId in subscriptions: {
  name: guid('owner', subscriptionId, 'devcenter', devCenterName)
  params: {
    role: 'Owner'
    principalId: devCenter.outputs.devCenterPrincipalId
    principalType: 'ServicePrincipal'
  }
  scope: subscription(subscriptionId)
}]

// the ci identity must be assigned subscription reader role to all environment type
// subscriptions otherwise it has to log out and log in again to see the environment
// type subscriptions after the first environment is created in that subscription
module ciSubscriptionRoles 'subscriptionRole.bicep' = [for subscriptionId in subscriptions:  {
  name: guid('reader', subscriptionId, devCenterName, ciPrincipalId)
  params: {
    role: 'Reader'
    principalId: ciPrincipalId
    principalType: 'ServicePrincipal'
  }
  scope: subscription(subscriptionId)
}]
