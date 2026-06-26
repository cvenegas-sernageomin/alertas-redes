$here = $PSScriptRoot
. "$here\..\src\RedesApi.ps1"

Describe "Sign" {
    It "calcula hash de 'test' correctamente" {
        Sign 'test' | Should Be '364492'
    }
    It "calcula hash para endpoint precip" {
        Sign 'api/raw-measure/by-measure-type/1/last' | Should Be '5f94b7ef'
    }
    It "calcula hash para endpoint temp" {
        Sign 'api/raw-measure/by-measure-type/2/last' | Should Be '6149908e'
    }
}

Describe "Get-EpochHora" {
    It "retorna entero positivo divisible por 3600" {
        $e = Get-EpochHora
        $e | Should BeGreaterThan 0
        ($e % 3600) | Should Be 0
    }
}

Describe "Get-RedFromCode" {
    It "numerico es DGA/DMC"  { Get-RedFromCode '01000005-K' | Should Be 'DGA/DMC' }
    It "AG es Agromet"        { Get-RedFromCode 'AG0501'     | Should Be 'Agromet' }
    It "CE es CEAZA"          { Get-RedFromCode 'CE1234'     | Should Be 'CEAZA'   }
    It "yy: es RedMeteo"     { Get-RedFromCode 'yy:00:00:00:00:01' | Should Be 'RedMeteo' }
    It "zx: es RedMeteo"     { Get-RedFromCode 'zx:00:00:00:00:25' | Should Be 'RedMeteo' }
    It "wl: es Otras"        { Get-RedFromCode 'wl:1d:0a:00:4b:ac' | Should Be 'Otras'   }
    It "UFRO es Otras"       { Get-RedFromCode 'UFRO_PP02'  | Should Be 'Otras'   }
}

Describe "Parse-RedesJson" {
    $fixture = Get-Content "$here\fixtures\redes_3h.json" -Raw | ConvertFrom-Json

    It "extrae el ultimo valor no-nulo de values" {
        $r = Parse-RedesJson $fixture
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).TasaMmH | Should Be 3.2
    }
    It "retorna 0.0 cuando todos los valores son null" {
        $r = Parse-RedesJson $fixture
        ($r | Where-Object { $_.Codigo -eq '02001001-K' }).TasaMmH | Should Be 0.0
    }
    It "usa el ultimo valor no-nulo cuando hay nulls al final" {
        $r = Parse-RedesJson $fixture
        ($r | Where-Object { $_.Codigo -eq '01001001-K' }).TasaMmH | Should Be 0.0
    }
    It "preserva lat y lon" {
        $r = Parse-RedesJson $fixture
        $v = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $v.Lat | Should Be -17.595
        $v.Lon | Should Be -69.4831
    }
    It "retorna tantos registros como el fixture" {
        $r = Parse-RedesJson $fixture
        $r.Count | Should Be 3
    }
    It "asigna red por codigo nacional" {
        $r = Parse-RedesJson $fixture
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).Red | Should Be 'DGA/DMC'
    }
    It "preserva ValoresSerie completo" {
        $r = Parse-RedesJson $fixture
        $v = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $v.ValoresSerie.Count | Should Be 3
        $v.ValoresSerie[2]    | Should Be 3.2
    }
    It "preserva TiemposSerie completo" {
        $r = Parse-RedesJson $fixture
        $v = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $v.TiemposSerie.Count | Should Be 3
        $v.TiemposSerie[0]    | Should Be 1781794800
    }
}

Describe "Merge-AltitudCache" {
    $tmp = Join-Path $env:TEMP "alt_cache_test_$(Get-Random).json"

    It "crea cache desde cero y persiste" {
        $r = Merge-AltitudCache $tmp @{ 'A' = 100.0; 'B' = 200.0 }
        $r.Keys.Count | Should Be 2
        (Test-Path $tmp) | Should Be $true
    }
    It "acumula nuevas altitudes sobre las previas" {
        $r = Merge-AltitudCache $tmp @{ 'C' = 300.0 }
        $r.Keys.Count | Should Be 3        # A y B persisten, se suma C
        $r['A'] | Should Be 100.0
        $r['C'] | Should Be 300.0
    }
    It "actualiza el valor de una altitud existente" {
        $r = Merge-AltitudCache $tmp @{ 'A' = 150.0 }
        $r['A'] | Should Be 150.0
    }
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
}

Describe "Parse-EmasDmcJson" {
    $redesFixture = Get-Content "$here\fixtures\redes_3h.json" -Raw | ConvertFrom-Json
    $precipSerie  = Parse-RedesJson $redesFixture
    $tempSerie    = Get-Content "$here\fixtures\temp_3h.json" -Raw | ConvertFrom-Json
    $altitudMap   = @{ '01000005-K' = 3800.0; '01001001-K' = 25.0; '02001001-K' = 2260.0 }

    It "extrae TasaMmH del ultimo no-nulo de ValoresSerie" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).TasaMmH | Should Be 3.2
    }
    It "extrae TempC del ultimo no-nulo de tempSerie" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).TempC | Should Be 10.8
    }
    It "calcula Isoterma correctamente" {
        # altitud=3800, temp=10.8 -> 3800 + floor((10.8/6.5)*1000) = 3800+1661 = 5461
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01000005-K' }).Isoterma | Should Be 5461
    }
    It "calcula ValoresIso por timestamp" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        $e = $r | Where-Object { $_.Codigo -eq '01000005-K' }
        $e.ValoresIso.Count | Should Be 3
        $e.ValoresIso[0]    | Should Be 5646
        $e.ValoresIso[2]    | Should Be 5461
    }
    It "TempC es null cuando todos los valores de temp son null" {
        $r = Parse-EmasDmcJson $precipSerie $tempSerie $altitudMap
        ($r | Where-Object { $_.Codigo -eq '01001001-K' }).TempC | Should BeNullOrEmpty
    }
    It "ValoresTemp vacio cuando no hay entrada en tempSerie" {
        $altSolo = @{ '02001001-K' = 2260.0 }
        $soloCalama = $precipSerie | Where-Object { $_.Codigo -eq '02001001-K' }
        $r = Parse-EmasDmcJson @($soloCalama) @() $altSolo
        ($r | Where-Object { $_.Codigo -eq '02001001-K' }).ValoresTemp.Count | Should Be 0
    }
}
