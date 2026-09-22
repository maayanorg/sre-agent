[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Inject','Status','Reset','Verify')][string]$Action='Status', [ValidateSet('Injected','Recovered')][string]$Expected='Injected')
& "$PSScriptRoot/../Invoke-LabScenario.ps1" -Scenario DnsLinkMissing @PSBoundParameters