# PSScriptAnalyzer settings: exclude rules that are not practical for this repo.
# - PSAvoidGlobalVars: test file uses global for InModuleScope fixture visibility.
# - PSUseShouldProcessForStateChangingFunctions: New-* test/module helpers return in-memory objects only.
# - PSUseSingularNouns: Get-BitsPerSecondMbps uses standard unit "Mbps"; Get-Iperf3TestSuiteDefaultParameterSet is singular.
@{
  ExcludeRules = @(
    'PSAvoidGlobalVars',
    'PSUseShouldProcessForStateChangingFunctions',
    'PSUseSingularNouns'
  )
}
