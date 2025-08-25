targetScope = 'subscription'

param rgName string
var location = deployment().location

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  location: location
  name: rgName
  tags: {
    'created-by': 'ianphil'
  }
}
