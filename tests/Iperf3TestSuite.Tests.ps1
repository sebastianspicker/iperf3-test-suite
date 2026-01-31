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

    It 'maps unknown values to 0' {
      InModuleScope Iperf3TestSuite {
        Get-TosFromDscpClass -Class 'NOPE' | Should -Be 0
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
        $s = 'banner {\"a\":1} trailer'
        Get-JsonSubstringOrNull -Text $s | Should -Be '{\"a\":1}'
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
}
