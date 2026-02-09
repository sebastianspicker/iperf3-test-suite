$ErrorActionPreference = 'Stop'

BeforeAll {
  $modulePath = Join-Path $PSScriptRoot '../src/Iperf3TestSuite.psd1'
  Import-Module $modulePath -Force
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
        $caps = [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true }
        $runner = {
          param([string[]]$IperfArgs)
          $script:captured = $IperfArgs
          $global:LASTEXITCODE = 0
          return '{"end":{}}'
        }
        $null = Invoke-Iperf3 -Server 'example' -Port 5201 -Stack 'IPv4' -Duration 1 -Omit 0 `
          -Proto 'TCP' -Dir 'RX' -Caps $caps -Runner $runner
        return $script:captured
      }

      $captured | Should -Contain '-R'
    }

    It 'adds --bidir for TCP BD when supported' {
      $captured = InModuleScope Iperf3TestSuite {
        $script:captured = $null
        $caps = [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true }
        $runner = {
          param([string[]]$IperfArgs)
          $script:captured = $IperfArgs
          $global:LASTEXITCODE = 0
          return '{"end":{}}'
        }
        $null = Invoke-Iperf3 -Server 'example' -Port 5201 -Stack 'IPv4' -Duration 1 -Omit 0 `
          -Proto 'TCP' -Dir 'BD' -Caps $caps -Runner $runner
        return $script:captured
      }

      $captured | Should -Contain '--bidir'
    }

    It 'adds -u and -b for UDP' {
      $captured = InModuleScope Iperf3TestSuite {
        $script:captured = $null
        $caps = [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true }
        $runner = {
          param([string[]]$IperfArgs)
          $script:captured = $IperfArgs
          $global:LASTEXITCODE = 0
          return '{"end":{}}'
        }
        $null = Invoke-Iperf3 -Server 'example' -Port 5201 -Stack 'IPv4' -Duration 1 -Omit 0 `
          -Proto 'UDP' -Dir 'TX' -UdpBw '5M' -Caps $caps -Runner $runner
        return $script:captured
      }

      $captured | Should -Contain '-u'
      $captured | Should -Contain '-b'
      $captured | Should -Contain '5M'
    }
  }

  Context 'Failure handling' {
    It 'throws when reachability fails' {
      InModuleScope Iperf3TestSuite {
        Mock Get-Command { [pscustomobject]@{ Name = 'iperf3' } } -ParameterFilter { $Name -eq 'iperf3' }
        Mock Get-Iperf3Capability { [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true } }
        Mock Test-Reachability { 'None' }
        Mock Test-TcpPortAndTrace { throw 'Should not be called' }

        Should -Throw -ActualValue { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet } -ExpectedMessage "ICMP reachability*"
      }
    }

    It 'throws when TCP port is not reachable' {
      InModuleScope Iperf3TestSuite {
        Mock Get-Command { [pscustomobject]@{ Name = 'iperf3' } } -ParameterFilter { $Name -eq 'iperf3' }
        Mock Get-Iperf3Capability { [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true } }
        Mock Test-Reachability { 'IPv4' }
        Mock Test-TcpPortAndTrace {
          [pscustomobject]@{
            Tcp   = [pscustomobject]@{ TcpTestSucceeded = $false }
            Trace = $null
          }
        }

        Should -Throw -ActualValue { Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet } -ExpectedMessage "TCP port*"
      }
    }
  }

  Context 'UDP saturation loop' {
    It 'stops when loss exceeds threshold' {
      InModuleScope Iperf3TestSuite {
        $script:udpBws = New-Object System.Collections.Generic.List[string]

        Mock Get-Command { [pscustomobject]@{ Name = 'iperf3' } } -ParameterFilter { $Name -eq 'iperf3' }
        Mock Get-Iperf3Capability { [pscustomobject]@{ VersionText = 'iperf3 3.9'; Major = 3; Minor = 9; BidirSupported = $true } }
        Mock Test-Reachability { 'IPv4' }
        Mock Test-TcpPortAndTrace {
          [pscustomobject]@{
            Tcp   = [pscustomobject]@{ TcpTestSucceeded = $true; RemoteAddress = '127.0.0.1'; PingSucceeded = $true }
            Trace = [pscustomobject]@{ TraceRoute = @() }
          }
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
            [pscustomobject]$Caps
          )

          $null = $Server, $Port, $Stack, $Duration, $Omit, $Tos, $Dir, $Streams, $Win, $ConnectTimeoutMs, $Caps

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
            Args     = @()
            ExitCode = 0
            RawLines = @()
            RawText  = ''
            Json     = $json
          }
        }

        $null = Invoke-Iperf3TestSuite -Target 'example.local' -OutDir $TestDrive -Quiet -DisableMtuProbe `
          -TcpStreams @(1) -TcpWindows @('default') -DscpClasses @('CS0') `
          -UdpStart '1M' -UdpMax '2M' -UdpStep '1M' -UdpLossThreshold 1.0

        $script:udpBws | Where-Object { $_ -eq '2M' } | Should -BeNullOrEmpty
      }
    }
  }
}
