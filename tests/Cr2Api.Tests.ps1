$here = $PSScriptRoot
. "$here\..\src\Cr2Api.ps1"

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
}
