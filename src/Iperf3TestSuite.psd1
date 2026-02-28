@{
  RootModule = 'Iperf3TestSuite.psm1'
  ModuleVersion = '0.3.0'
  GUID = 'c1f4c3a8-5a7f-4fd6-8ea3-1efb8e0f4b7b'
  Author = 'iperf3-test-suite'
  CompanyName = ''
  Copyright = ''
  Description = 'Windows-first iperf3 Test Suite (PowerShell). Includes profile management, strict configuration validation, deterministic exit behavior, DSCP matrix tests, optional MTU probe, and additive summary/report/index outputs.'
  PowerShellVersion = '7.0'
  CompatiblePSEditions = @('Core')
  FunctionsToExport = @(
    'Invoke-Iperf3TestSuite',
    'Get-Iperf3TestSuiteDefaultParameterSet',
    'Get-Iperf3ProfileNames',
    'Get-Iperf3ProfileParameters',
    'Save-Iperf3Profile',
    'Remove-Iperf3Profile'
  )
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
  PrivateData = @{
    PSData = @{
      Tags = @('iperf3','network','benchmark')
      ProjectUri = ''
      LicenseUri = ''
      ReleaseNotes = ''
    }
  }
}
