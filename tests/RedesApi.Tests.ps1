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
}

Describe "Parse-EmasDmcJson" {
    $precip  = Get-Content "$here\fixtures\precip_last.json" -Raw | ConvertFrom-Json
    $tempArr = Get-Content "$here\fixtures\temp_last.json"  -Raw | ConvertFrom-Json

    It "merge por nationalCode: precip y temp en mismo objeto" {
        $r = Parse-EmasDmcJson $precip $tempArr
        $e = $r | Where-Object { $_.Codigo -eq '330113' }
        $e.TasaMmH | Should Be 6.5
        $e.TempC   | Should Be 8.0
    }
    It "calcula isoterma 0C correctamente" {
        # altitud=275, temp=8.0 -> iso = 275 + (8.0/6.5)*1000 = 275 + 1230 = 1505
        $r = Parse-EmasDmcJson $precip $tempArr
        $e = $r | Where-Object { $_.Codigo -eq '330113' }
        $e.Isoterma | Should Be 1505
    }
    It "isoterma es null si no hay temperatura para esa estacion" {
        $r = Parse-EmasDmcJson $precip $tempArr
        $e = $r | Where-Object { $_.Codigo -eq '999999' }
        $e.Isoterma | Should BeNullOrEmpty
    }
    It "preserva altitud" {
        $r = Parse-EmasDmcJson $precip $tempArr
        $e = $r | Where-Object { $_.Codigo -eq '330113' }
        $e.Altitud | Should Be 275.0
    }
}
