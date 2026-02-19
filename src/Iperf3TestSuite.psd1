@{
  RootModule = 'Iperf3TestSuite.psm1'
  ModuleVersion = '0.1.0'
  GUID = 'c1f4c3a8-5a7f-4fd6-8ea3-1efb8e0f4b7b'
  Author = 'iperf3-test-suite'
  CompanyName = ''
  Copyright = ''
  Description = 'PowerShell iperf3 test suite runner (CSV/JSON artifacts, DSCP marking, optional MTU probe).'
  PowerShellVersion = '7.0'
  CompatiblePSEditions = @('Core')
  FunctionsToExport = @('Invoke-Iperf3TestSuite', 'Get-Iperf3TestSuiteDefaultParameterSet')
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

