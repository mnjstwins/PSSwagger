Describe "Basic API" -Tag ScenarioTest {
    BeforeAll {
        # TODO: Pass all these locations dynamically - See issues/17
        # Ensure PSSwagger isn't loaded (including the one installed on the machine, if any)
        Get-Module PSSwagger | Remove-Module

        $testSpec = "PsSwaggerTestBasicSpec.json"
        $testData = "PsSwaggerTestBasicData.json"
        $testRoutes = "PsSwaggerTestBasicRoutes.json"

        # Import PSSwagger
        Import-Module "$PSScriptRoot\..\PSSwagger\PSSwagger.psd1" -Force

        $generatedModulesPath = Join-Path -Path "$PSScriptRoot" -ChildPath "Generated"
        $testCaseDataLocation = "$PSScriptRoot\Data\PsSwaggerTestBasic"

        # Note: This only works if these tests are never run in parallel, but our current usage of json-server is the same way, so...
        $global:testDataSpec = ConvertFrom-Json ((Get-Content (Join-Path $testCaseDataLocation $testSpec)) -join [Environment]::NewLine) -ErrorAction Stop
        
        # Generate module
        Write-Host "Generating module"
        Export-CommandFromSwagger -SwaggerSpecPath "$testCaseDataLocation\$testSpec" -Path "$generatedModulesPath" -ModuleName "Generated.Basic.Module"

        # Import generated module
        Write-Host "Importing module"
        Import-Module "$PSScriptRoot\..\PSSwagger\Generated.Azure.Common.Helpers\Generated.Azure.Common.Helpers.psd1" -Force
        Import-Module "$PSScriptRoot\Generated\Generated.Basic.Module\2017.1.1\Generated.Basic.Module.psd1"
        
        # Copy json-server data since it's updated live
        Copy-Item "$testCaseDataLocation\$testData" "$PSScriptRoot\NodeModules\db.json" -Force

        # Start json-server
        # TODO: Pick a port in a certain range that's open instead of hardcoding to 3000, replace the URI in Swagger spec  - See issues/16
        # Snapshot the node processes before starting json-server so we can stop the right one later
        # Not sure if we need it, but we'll also keep the returned process to stop later as well (which does not, by itself, stop json-server)
        $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue
        if ($nodeProcesses -eq $null) {
            $nodeProcesses = @()
        }

        $jsonServerProcess = Start-Process -FilePath "$PSScriptRoot\NodeModules\json-server.cmd" -ArgumentList "--watch `"$PSScriptRoot\NodeModules\db.json`" --routes `"$testCaseDataLocation\$testRoutes`"" -PassThru -WindowStyle Hidden
        $nodeProcessToStop = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {-not $nodeProcesses.Contains($_)}
        while ($nodeProcessToStop -eq $null) {
            $nodeProcessToStop = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {-not $nodeProcesses.Contains($_)}
        }

        Write-Host "json-server started at: $($nodeProcessToStop.ID)"
    }

    Context "Basic API tests" {
        # Mocks
        Mock Get-AzServiceCredential -ModuleName Generated.Basic.Module {
            return New-Object -TypeName PSSwagger.TestUtilities.TestCredentials
        }

        Mock Get-AzSubscriptionId -ModuleName Generated.Basic.Module {
            return "Test"
        }

        Mock Get-AzResourceManagerUrl -ModuleName Generated.Basic.Module {
            return "$($global:testDataSpec.schemes[0])://$($global:testDataSpec.host)"
        }

        It "Basic test" {
            Get-Cupcake -Flavor "chocolate"
            New-Cupcake -Flavor "vanilla"
        }
    }

    AfterAll {
        # Stop json-server
        Write-Host "Stopping process: $($jsonServerProcess.ID)"
        $jsonServerProcess | Stop-Process
        Write-Host "Stopping process: $($nodeProcessToStop.ID)"
        $nodeProcessToStop | Stop-Process
    }
}