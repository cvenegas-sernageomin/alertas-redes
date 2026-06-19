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
