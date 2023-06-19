@sys.description('Location of the Project. If none is provided, the resource group location is used.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(26)
@sys.description('Name of the Project')
param name string

param description string = ''

@sys.description('Name of the DevCenter')
param devCenterName string

@sys.description('The principal ids of users to assign the role of DevCenter Project Admin.  Users must either have DevCenter Project Admin or DevCenter Dev Box User role in order to create a Dev Box.')
param projectAdmins array

@sys.description('The principal id of the CI identity. This identity well be assigned the subscription reader role to all environment type subscriptions.')
param ciPrincipalId string

@sys.description('Tags to apply to the resources')
param tags object = {}

@sys.description('An object with property keys containing the Environment Type name and values containing Subscription and Description properties.')
param environmentTypes object

var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var environmentUserRoleId = '18e40d4e-8d2e-438d-97e1-9528336e149c'

resource devCenter 'Microsoft.DevCenter/devcenters@2023-04-01' existing = {
  name: devCenterName
}

// create the project
resource project 'Microsoft.DevCenter/projects@2023-04-01' = {
  name: name
  location: location
  properties: {
    devCenterId: devCenter.id
    description: (!empty(description) ? description : null)
  }
  tags: tags
}

// assign the project admins the project admin role
module userProjectAdminRoles 'projectRole.bicep' = [for user in projectAdmins: {
  name: guid('admin', devCenterName, name, user)
  params: {
    role: 'ProjectAdmin'
    projectName: project.name
    principalId: user
    principalType: 'User'
  }
}]

// assign the ci identity the project reader role
module ciProjectAdminRoles 'projectRole.bicep' = {
  name: guid('reader', devCenterName, name, ciPrincipalId)
  params: {
    role: 'Reader'
    projectName: project.name
    principalId: ciPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// create the the project environment types
resource envTypes 'Microsoft.DevCenter/projects/environmentTypes@2023-04-01' = [for envType in items(environmentTypes): {
  name: envType.key
  parent: project
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    status: 'Enabled'
    #disable-next-line use-resource-id-functions
    // if the environment type subscription is empty use the project's subscription
    deploymentTargetId: empty(envType.value) ? subscription().id : '/subscriptions/${envType.value}'
    creatorRoleAssignment: {
      roles: {
        '${contributorRoleId}': {}
      }
    }
  }
  tags: tags
}]

// assign the ci identity the environments user role to all project environment types
resource envTypeRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (envType, index) in items(environmentTypes): {
  name: guid(environmentUserRoleId, devCenterName, name, envType.key, ciPrincipalId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', environmentUserRoleId)
    principalId: ciPrincipalId
    principalType: 'ServicePrincipal'
  }
  scope: envTypes[index]
}]

output projectName string = project.name
