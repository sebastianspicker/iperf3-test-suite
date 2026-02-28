$ErrorActionPreference = 'Stop'

BeforeAll {
  . (Join-Path (Get-Item $PSScriptRoot).Parent.FullName 'scripts/Get-RepoRoot.ps1')
  $repoRoot = Get-RepoRoot
  $script:RepoRoot = $repoRoot
  $modulePath = Join-Path $repoRoot 'src/Iperf3TestSuite.psd1'
  Import-Module $modulePath -Force
  $script:TestCapability = [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true }
  $global:Iperf3TestSuite_TestCapability = $script:TestCapability
  try {
    $global:IsWindows = $true
  } catch {
    Write-Verbose 'On some hosts (e.g. macOS) $IsWindows is read-only; Windows-only tests may fail or be skipped.'
  }
}

function New-TestCapability {
  $script:TestCapability
}

function New-TestTcpResult {
  param([bool]$TcpSucceeded = $true, [object]$Trace = $null)
  [pscustomobject]@{
    Tcp   = [pscustomobject]@{ TcpTestSucceeded = $TcpSucceeded; RemoteAddress = '127.0.0.1'; PingSucceeded = $true }
    Trace = $Trace
  }
}

Describe 'Iperf3TestSuite helpers' {
  Context 'DSCP mapping' {
    It 'maps CS0 to 0' {
      InModuleScope Iperf3TestSuite {
        Get-TosFromDscpClass -Class 'CS0' | Should -Be 0
      }
    }

    It 'maps EF to 184' {
      InModuleScope Iperf3TestSuite {
        Get-TosFromDscpClass -Class 'EF' | Should -Be (46 -shl 2)
      }
    }

    It 'maps AF11 to 40' {
      InModuleScope Iperf3TestSuite {
        Get-TosFromDscpClass -Class 'AF11' | Should -Be 40
      }
    }

    It 'throws on unknown DSCP class' {
      InModuleScope Iperf3TestSuite {
        { Get-TosFromDscpClass -Class 'NOPE' } | Should -Throw "Unknown DSCP class*"
      }
    }
  }

  Context 'Hostname/IP validation' {
    It 'rejects invalid IPv6-like strings (e.g. :::)' {
      InModuleScope Iperf3TestSuite {
        Test-ValidHostnameOrIP -Name ':::' | Should -Be $false
        Test-ValidHostnameOrIP -Name ':' | Should -Be $false
      }
    }
  }

  Context 'Bandwidth parsing' {
    It 'parses 10M to 10' {
      InModuleScope Iperf3TestSuite {
        ConvertTo-MbitPerSecond -Value '10M' | Should -Be 10.0
      }
    }

    It 'parses 1G to 1000' {
      InModuleScope Iperf3TestSuite {
        ConvertTo-MbitPerSecond -Value '1G' | Should -Be 1000.0
      }
    }

    It 'parses 500K to 0.5' {
      InModuleScope Iperf3TestSuite {
        ConvertTo-MbitPerSecond -Value '500K' | Should -Be 0.5
      }
    }

    It 'throws on invalid format' {
      InModuleScope Iperf3TestSuite {
        { ConvertTo-MbitPerSecond -Value 'nope' } | Should -Throw
      }
    }
  }

  Context 'JSON extraction' {
    It 'extracts the JSON substring when surrounded by text' {
      InModuleScope Iperf3TestSuite {
        $s = 'banner {"a":1} trailer'
        Get-JsonSubstringOrNull -Text $s | Should -Be '{"a":1}'
      }
    }

    It 'skips invalid braces and returns the first valid JSON' {
      InModuleScope Iperf3TestSuite {
        $s = 'prefix {notjson} mid {"a":1} trailer'
        Get-JsonSubstringOrNull -Text $s | Should -Be '{"a":1}'
      }
    }

    It 'handles braces inside JSON strings' {
      InModuleScope Iperf3TestSuite {
        $s = 'banner {"a":"{x}"} trailer'
        Get-JsonSubstringOrNull -Text $s | Should -Be '{"a":"{x}"}'
      }
    }

    It 'returns null when braces exist but no valid JSON' {
      InModuleScope Iperf3TestSuite {
        $s = 'prefix {not json} trailer'
        Get-JsonSubstringOrNull -Text $s | Should -Be $null
      }
    }

    It 'returns null when no braces exist' {
      InModuleScope Iperf3TestSuite {
        Get-JsonSubstringOrNull -Text 'no json here' | Should -Be $null
      }
    }
  }

  Context 'Metric extraction' {
    It 'extracts TCP metrics (TX)' {
      InModuleScope Iperf3TestSuite {
        $json = ConvertFrom-Json '{"end":{"sum_sent":{"bits_per_second":10000000,"retransmits":2},"sum_received":{"bits_per_second":8000000}}}'
        $m = Get-Iperf3Metric -Json $json -Proto TCP -Dir TX
        $m.TxMbps | Should -Be 10.0
        $m.RxMbps | Should -Be 8.0
        $m.Retr | Should -Be 2
        $m.LossPct | Should -Be $null
        $m.JitterMs | Should -Be $null
      }
    }

    It 'extracts UDP metrics (TX)' {
      InModuleScope Iperf3TestSuite {
        $json = ConvertFrom-Json '{"end":{"sum_sent":{"bits_per_second":10000000,"lost_percent":2.5},"sum_received":{"bits_per_second":9000000},"sum":{"lost_percent":2.5,"jitter_ms":1.2}}}'
        $m = Get-Iperf3Metric -Json $json -Proto UDP -Dir TX
        $m.TxMbps | Should -Be 10.0
        $m.RxMbps | Should -Be 9.0
        $m.Retr | Should -Be $null
        $m.LossPct | Should -Be 2.5
        $m.JitterMs | Should -Be 1.2
      }
    }
  }

  Context 'CSV row shape' {
    It 'creates a stable column order' {
      InModuleScope Iperf3TestSuite {
        $row = ConvertTo-Iperf3CsvRow -No 1 -Proto 'TCP' -Dir 'TX' -DSCP 'CS0' -Streams 1 -Win 'default' `
          -ThrTxMbps 1.23 -RetrTx 0 -ThrRxMbps 0.0 -LossTxPct $null -JitterMs $null -Role 'end'

        $row.PSObject.Properties.Name | Should -Be @(
          'No',
          'Proto',
          'Dir',
          'DSCP',
          'Streams',
          'Win',
          'Thr_TX_Mbps',
          'Retr_TX',
          'Thr_RX_Mbps',
          'Loss_TX_Pct',
          'Jitter_ms',
          'Role'
        )
      }
    }
  }

  Context 'Invoke-Iperf3 args' {
    It 'adds -R for TCP RX' {
      $captured = InModuleScope Iperf3TestSuite {
        $script:captured = $null
        $caps = $global:Iperf3TestSuite_TestCapability
        $runner = { param([string[]]$IperfArgs); $script:captured = $IperfArgs; $global:LASTEXITCODE = 0; return '{"end":{}}' }
        $null = Invoke-Iperf3 -Server 'example' -Port 5201 -Stack 'IPv4' -Duration 1 -Omit 0 -Proto 'TCP' -Dir 'RX' -Caps $caps -Runner $runner
        return $script:captured
      }
      $captured | Should -Contain '-R'
    }

    It 'adds --bidir for TCP BD when supported' {
      $captured = InModuleScope Iperf3TestSuite {
        $script:captured = $null
        $caps = $global:Iperf3TestSuite_TestCapability
        $runner = { param([string[]]$IperfArgs); $script:captured = $IperfArgs; $global:LASTEXITCODE = 0; return '{"end":{}}' }
        $null = Invoke-Iperf3 -Server 'example' -Port 5201 -Stack 'IPv4' -Duration 1 -Omit 0 -Proto 'TCP' -Dir 'BD' -Caps $caps -Runner $runner
        return $script:captured
      }
      $captured | Should -Contain '--bidir'
    }

    It 'adds -u and -b for UDP' {
      $captured = InModuleScope Iperf3TestSuite {
        $script:captured = $null
        $caps = $global:Iperf3TestSuite_TestCapability
        $runner = { param([string[]]$IperfArgs); $script:captured = $IperfArgs; $global:LASTEXITCODE = 0; return '{"end":{}}' }
        $null = Invoke-Iperf3 -Server 'example' -Port 5201 -Stack 'IPv4' -Duration 1 -Omit 0 -Proto 'UDP' -Dir 'TX' -UdpBw '5M' -Caps $caps -Runner $runner
        return $script:captured
      }
      $captured | Should -Contain '-u'
      $captured | Should -Contain '-b'
      $captured | Should -Contain '5M'
    }
  }

  Context 'Failure handling' {
    It 'emits InputValidation ErrorId when target is missing' {
      InModuleScope Iperf3TestSuite {
        $err = $null
        try { Invoke-Iperf3TestSuite -OutDir $TestDrive -Quiet } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.FullyQualifiedErrorId | Should -Match 'Iperf3TestSuite.InputValidation'
      }
    }

    It 'throws when reachability fails' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }
        Mock Test-Reachability { 'None' }
        Mock Test-TcpPortAndTrace { throw 'Should not be called' }
        Mock Invoke-Iperf3 { throw 'Should not be called' }

        Should -Throw -ActualValue { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet } -ExpectedMessage "ICMP reachability*"
      }
    }

    It 'emits Connectivity ErrorId when reachability fails' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }
        Mock Test-Reachability { 'None' }
        Mock Test-TcpPortAndTrace { throw 'Should not be called' }
        Mock Invoke-Iperf3 { throw 'Should not be called' }

        $err = $null
        try { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.FullyQualifiedErrorId | Should -Match 'Iperf3TestSuite.Connectivity'
      }
    }

    It 'throws on non-Windows' -Skip:(-not $IsWindows) {
      InModuleScope Iperf3TestSuite {
        $global:IsWindows = $false
        Should -Throw -ActualValue { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet } -ExpectedMessage "*only supported on Windows*"
      }
    }

    It 'throws when TCP port is not reachable' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }
        Mock Test-Reachability { 'IPv4' }
        Mock Test-TcpPortAndTrace {
          [pscustomobject]@{ Tcp = [pscustomobject]@{ TcpTestSucceeded = $false; RemoteAddress = '127.0.0.1'; PingSucceeded = $true }; Trace = $null }
        }
        Mock Invoke-Iperf3 { throw 'Should not be called' }

        Should -Throw -ActualValue { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet } -ExpectedMessage "TCP port*"
      }
    }

    It 'throws when SingleTest and DscpClasses is empty' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }

        # Parameter binding may reject empty array; otherwise our explicit check throws
        $err = $null
        try { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet -SingleTest -DscpClasses @() } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        ($err.Exception.Message -match 'at least one DSCP|empty|null') | Should -Be $true
      }
    }
  }

  Context 'UDP saturation loop' {
    It 'stops when loss exceeds threshold' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
        $script:udpBws = New-Object System.Collections.Generic.List[string]

        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }
        Mock Test-Reachability { 'IPv4' }
        Mock Test-TcpPortAndTrace {
          [pscustomobject]@{ Tcp = [pscustomobject]@{ TcpTestSucceeded = $true; RemoteAddress = '127.0.0.1'; PingSucceeded = $true }; Trace = [pscustomobject]@{ TraceRoute = @() } }
        }

        Mock Invoke-Iperf3 {
          param(
            [string]$Server,
            [int]$Port,
            [string]$Stack,
            [int]$Duration,
            [int]$Omit,
            [int]$Tos,
            [string]$Proto,
            [string]$Dir,
            [int]$Streams,
            [string]$Win,
            [string]$UdpBw,
            [int]$ConnectTimeoutMs,
            [pscustomobject]$Caps,
            [scriptblock]$Runner
          )

          $null = $Server, $Port, $Stack, $Duration, $Omit, $Tos, $Dir, $Streams, $Win, $ConnectTimeoutMs, $Caps, $Runner

          if ($Proto -eq 'UDP') {
            $script:udpBws.Add($UdpBw) | Out-Null
            $json = [pscustomobject]@{
              end = [pscustomobject]@{
                sum_sent     = [pscustomobject]@{ bits_per_second = 1000000; lost_percent = 10 }
                sum_received = [pscustomobject]@{ bits_per_second = 900000 }
                sum          = [pscustomobject]@{ lost_percent = 10; jitter_ms = 1.0 }
              }
            }
          }
          else {
            $json = [pscustomobject]@{ end = $null }
          }

          return [pscustomobject]@{
            Args           = @()
            ExitCode       = 0
            RawLines       = @()
            RawText        = ''
            Json           = $json
            JsonParseError = $null
          }
        }

        $null = Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet -DisableMtuProbe `
          -TcpStreams @(1) -TcpWindows @('default') -DscpClasses @('CS0') `
          -UdpStart '1M' -UdpMax '2M' -UdpStep '1M' -UdpLossThreshold 1.0

        $script:udpBws | Where-Object { $_ -eq '2M' } | Should -BeNullOrEmpty
        $script:udpBws.Count | Should -BeGreaterOrEqual 1
        $script:udpBws[0] | Should -Be '1M'  # Verify first bandwidth was tried
      }
    }
  }

  Context 'SingleTest protocol filter' {
    It 'runs exactly one UDP TX test for SingleTest + Protocol UDP' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }
        Mock Test-Reachability { 'IPv4' }
        Mock Test-TcpPortAndTrace {
          [pscustomobject]@{ Tcp = [pscustomobject]@{ TcpTestSucceeded = $true; RemoteAddress = '127.0.0.1'; PingSucceeded = $true }; Trace = [pscustomobject]@{ TraceRoute = @() } }
        }

        $script:calls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-Iperf3 {
          param(
            [string]$Server,
            [int]$Port,
            [string]$Stack,
            [int]$Duration,
            [int]$Omit,
            [int]$Tos,
            [string]$Proto,
            [string]$Dir,
            [int]$Streams,
            [string]$Win,
            [string]$UdpBw,
            [int]$ConnectTimeoutMs,
            [pscustomobject]$Caps,
            [scriptblock]$Runner
          )
          $null = $Server, $Port, $Stack, $Duration, $Omit, $Tos, $Streams, $Win, $ConnectTimeoutMs, $Caps, $Runner
          $script:calls.Add([pscustomobject]@{ Proto = $Proto; Dir = $Dir; UdpBw = $UdpBw }) | Out-Null
          [pscustomobject]@{
            Args           = @()
            ExitCode       = 0
            RawLines       = @()
            RawText        = ''
            Json           = [pscustomobject]@{ end = [pscustomobject]@{ sum_sent = [pscustomobject]@{ bits_per_second = 1000000; lost_percent = 0.0 }; sum_received = [pscustomobject]@{ bits_per_second = 900000 }; sum = [pscustomobject]@{ lost_percent = 0.0; jitter_ms = 1.0 } } }
            JsonParseError = $null
          }
        }

        $summary = Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet -DisableMtuProbe -SingleTest -Protocol UDP -DscpClasses @('CS0') -PassThru
        $script:calls.Count | Should -Be 1
        $script:calls[0].Proto | Should -Be 'UDP'
        $script:calls[0].Dir | Should -Be 'TX'
        $summary.Counts.Total | Should -Be 1
      }
    }
  }

  Context 'Configuration normalization' {
    It 'ignores unknown keys in non-strict mode' {
      InModuleScope Iperf3TestSuite {
        $res = ConvertTo-Iperf3NormalizedParameterSet -InputParameters @{ Port = 5201; UnknownKey = 'x' } -AllowedKeys @('Port') -StrictConfiguration:$false
        $res.Parameters.ContainsKey('Port') | Should -Be $true
        $res.Parameters.ContainsKey('UnknownKey') | Should -Be $false
        @($res.Warnings).Count | Should -Be 1
      }
    }

    It 'throws on unknown keys in strict mode' {
      InModuleScope Iperf3TestSuite {
        { ConvertTo-Iperf3NormalizedParameterSet -InputParameters @{ UnknownKey = 'x' } -AllowedKeys @('Port') -StrictConfiguration } | Should -Throw
      }
    }

    It 'drops invalid range values in non-strict mode' {
      InModuleScope Iperf3TestSuite {
        $res = ConvertTo-Iperf3NormalizedParameterSet -InputParameters @{ Port = 70000 } -AllowedKeys @('Port') -StrictConfiguration:$false
        $res.Parameters.ContainsKey('Port') | Should -Be $false
        @($res.Warnings).Count | Should -Be 1
        $res.Warnings[0] | Should -Match 'range'
      }
    }

    It 'throws on invalid range values in strict mode' {
      InModuleScope Iperf3TestSuite {
        { ConvertTo-Iperf3NormalizedParameterSet -InputParameters @{ Port = 70000 } -AllowedKeys @('Port') -StrictConfiguration } | Should -Throw
      }
    }
  }

  Context 'Profiles' {
    It 'saves, lists, and loads profile parameters' {
      InModuleScope Iperf3TestSuite {
        $profilesFile = Join-Path $TestDrive 'profiles.json'
        $save = Save-Iperf3Profile -ProfileName 'lab' -ProfilesFile $profilesFile -Parameters @{ Target = 'example.local'; Port = 5201; Protocol = 'TCP' } -StrictConfiguration
        $save.ProfileName | Should -Be 'lab'
        $names = Get-Iperf3ProfileNames -ProfilesFile $profilesFile -StrictConfiguration
        $names | Should -Contain 'lab'
        $loaded = Get-Iperf3ProfileParameters -ProfileName 'lab' -ProfilesFile $profilesFile -StrictConfiguration
        $loaded.Target | Should -Be 'example.local'
        $loaded.Port | Should -Be 5201
        $loaded.Protocol | Should -Be 'TCP'
      }
    }

    It 'removes a saved profile' {
      InModuleScope Iperf3TestSuite {
        $profilesFile = Join-Path $TestDrive 'profiles-remove.json'
        $null = Save-Iperf3Profile -ProfileName 'to-remove' -ProfilesFile $profilesFile -Parameters @{ Target = 'example.local' }
        $removed = Remove-Iperf3Profile -ProfileName 'to-remove' -ProfilesFile $profilesFile
        $removed | Should -Be $true
        $names = Get-Iperf3ProfileNames -ProfilesFile $profilesFile
        $names | Should -Not -Contain 'to-remove'
      }
    }

    It 'creates a backup when profiles file is corrupt in non-strict mode' {
      InModuleScope Iperf3TestSuite {
        $profilesFile = Join-Path $TestDrive 'profiles-corrupt.json'
        Set-Content -LiteralPath $profilesFile -Encoding UTF8 -Value '{not-json'
        $names = Get-Iperf3ProfileNames -ProfilesFile $profilesFile
        @($names).Count | Should -Be 0
        $backups = @(Get-ChildItem -LiteralPath $TestDrive -Filter 'profiles-corrupt.json.corrupt.*.bak')
        $backups.Count | Should -Be 1
      }
    }

    It 'blocks profiles path traversal via relative path' {
      InModuleScope Iperf3TestSuite {
        Push-Location $TestDrive
        try {
          { Save-Iperf3Profile -ProfileName 'x' -ProfilesFile '../profiles.json' -Parameters @{ Target = 'example.local' } -StrictConfiguration } | Should -Throw '*must be under the current directory*'
        }
        finally {
          Pop-Location
        }
      }
    }

    It 'lists profiles via Invoke-Iperf3TestSuite passthru mode' {
      InModuleScope Iperf3TestSuite {
        $profilesFile = Join-Path $TestDrive 'profiles-list.json'
        $null = Save-Iperf3Profile -ProfileName 'a' -ProfilesFile $profilesFile -Parameters @{ Target = 'example.local' }
        $res = Invoke-Iperf3TestSuite -ListProfiles -ProfilesFile $profilesFile -PassThru -Quiet
        $res.Mode | Should -Be 'ListProfiles'
        @($res.Profiles) | Should -Contain 'a'
      }
    }
  }

  Context 'PassThru summary and supplemental outputs' {
    It 'returns summary and writes supplemental report files' {
      InModuleScope Iperf3TestSuite {
        Mock Test-Iperf3TestSuitePrerequisites { }
        Mock Get-Iperf3Capability { $global:Iperf3TestSuite_TestCapability }
        Mock Test-Reachability { 'IPv4' }
        Mock Test-TcpPortAndTrace {
          [pscustomobject]@{ Tcp = [pscustomobject]@{ TcpTestSucceeded = $true; RemoteAddress = '127.0.0.1'; PingSucceeded = $true }; Trace = [pscustomobject]@{ TraceRoute = @() } }
        }
        Mock Invoke-Iperf3 {
          [pscustomobject]@{
            Args           = @()
            ExitCode       = 0
            RawLines       = @()
            RawText        = ''
            Json           = [pscustomobject]@{ end = [pscustomobject]@{ sum_sent = [pscustomobject]@{ bits_per_second = 1000000; retransmits = 0 }; sum_received = [pscustomobject]@{ bits_per_second = 900000 } } }
            JsonParseError = $null
          }
        }

        $summary = Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -DisableMtuProbe -Quiet -Protocol TCP -DscpClasses @('CS0') -TcpStreams @(1) -TcpWindows @('default') -PassThru
        $summary.ExitCode | Should -Be 0
        (Test-Path -LiteralPath $summary.Supplemental.SummaryJsonPath) | Should -Be $true
        (Test-Path -LiteralPath $summary.Supplemental.ReportMdPath) | Should -Be $true
        (Test-Path -LiteralPath $summary.Supplemental.RunIndexPath) | Should -Be $true
      }
    }
  }

  Context 'CLI exit code mapping' {
    It 'returns 11 for unknown profile name' {
      $scriptPath = Join-Path $script:RepoRoot 'iPerf3Test.ps1'
      & pwsh -NoLogo -NoProfile -File $scriptPath -ProfileName '__does_not_exist__' -WhatIf *> $null
      $LASTEXITCODE | Should -Be 11
    }

    It 'deletes an existing profile via CLI DeleteProfile' {
      $scriptPath = Join-Path $script:RepoRoot 'iPerf3Test.ps1'
      $profilesFile = Join-Path $TestDrive 'cli-delete-profiles.json'

      & pwsh -NoLogo -NoProfile -File $scriptPath -Target 'example.local' -ProfilesFile $profilesFile -ProfileName 'cli-temp' -SaveProfile -WhatIf -Quiet *> $null
      $LASTEXITCODE | Should -Be 0

      & pwsh -NoLogo -NoProfile -File $scriptPath -ProfilesFile $profilesFile -DeleteProfile 'cli-temp' -Quiet *> $null
      $LASTEXITCODE | Should -Be 0

      $names = @(Get-Iperf3ProfileNames -ProfilesFile $profilesFile)
      $names | Should -Not -Contain 'cli-temp'
    }

    It 'returns 11 when deleting a non-existing profile via CLI DeleteProfile' {
      $scriptPath = Join-Path $script:RepoRoot 'iPerf3Test.ps1'
      $profilesFile = Join-Path $TestDrive 'cli-delete-missing.json'
      & pwsh -NoLogo -NoProfile -File $scriptPath -ProfilesFile $profilesFile -DeleteProfile '__missing__' -Quiet *> $null
      $LASTEXITCODE | Should -Be 11
    }
  }
}
