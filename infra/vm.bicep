param name string
param location string
param tags object
param size string
param sshPublicKey string
param subnetId string
param privateIp string
param identityId string
param identityClientId string
param dcrId string
param role string
param storageName string
param vaultName string
param resourceGroupId string
param adminUsername string = 'labadmin'
param includeBootstrap bool = true

var appCode = loadFileAsBase64('../workload/server.js')
var bootstrap = replace(replace(replace(replace(replace(replace(replace(loadTextContent('../workload/bootstrap.sh'), '__APP_BASE64__', appCode), '__SHOP_BASE64__', loadFileAsBase64('../workload/shop.cjs')), '__ROLE__', role), '__STORAGE__', storageName), '__VAULT__', vaultName), '__CLIENT_ID__', identityClientId), '__RG_ID__', resourceGroupId)

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: replace(name, 'vm-', 'nic-')
  location: location
  tags: tags
  properties: {
    ipConfigurations: [{
      name: 'primary'
      properties: { subnet: { id: subnetId }, privateIPAllocationMethod: 'Static', privateIPAddress: privateIp }
    }]
  }
}
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityId}': {} } }
  properties: {
    hardwareProfile: { vmSize: size }
    networkProfile: { networkInterfaces: [{ id: nic.id }] }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: 'latest' }
      osDisk: { createOption: 'FromImage', diskSizeGB: 32, managedDisk: { storageAccountType: 'Standard_LRS' }, deleteOption: 'Delete' }
    }
    osProfile: union({
      computerName: role
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: sshPublicKey }] }
      }
    }, includeBootstrap ? { customData: base64(bootstrap) } : {})
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
    securityProfile: { securityType: 'TrustedLaunch', uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } }
  }
}
resource monitor 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: { authentication: { managedIdentity: { 'identifier-name': 'mi_res_id', 'identifier-value': identityId } } }
  }
}
resource association 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'srelab-vm'
  scope: vm
  properties: { dataCollectionRuleId: dcrId }
}
