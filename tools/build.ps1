# Builds dist/fps_unlock.swf from src/PluginMain.as with Apache Flex mxmlc.
#
# Prerequisites (not redistributed, see README "Building from source"):
#   $env:FLEX_SDK   -> Apache Flex SDK root (bin/mxmlc.bat), e.g. Flex 4.16.1
#   $env:JAVA_HOME  -> a JRE/JDK 8+ (mxmlc is a Java tool)
# Optionally copy tools/compile-config.xml next to your SDK config or edit the
# -load-config path below.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$flex = $env:FLEX_SDK
$java = $env:JAVA_HOME

if (-not $flex) { $flex = Join-Path $root "tools\flexsdk" }
if (-not (Test-Path (Join-Path $flex "bin\mxmlc.bat"))) {
    throw "Flex SDK not found. Set `$env:FLEX_SDK to your Apache Flex SDK root."
}
if ($java) { $env:Path = "$java\bin;$env:Path" }

$env:JAVA_TOOL_OPTIONS = "-Duser.language=en -Duser.country=US -Dfile.encoding=UTF-8"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$cfg = Join-Path $PSScriptRoot "compile-config.xml"
$tpl = Join-Path $PSScriptRoot "compile-config.template.xml"
$src = Join-Path $root "src\PluginMain.as"
$out = Join-Path $root "dist\fps_unlock.swf"
New-Item -ItemType Directory -Path (Join-Path $root "dist") -Force | Out-Null

# Render the config template: the Flex compiler only resolves {playerglobalHome}
# inside its own framework config, so point at the SDK's playerglobal.swc here.
$playerglobal = Join-Path $flex "frameworks\libs\player\32.0\playerglobal.swc"
if (-not (Test-Path $playerglobal)) {
    throw "playerglobal.swc not found at $playerglobal. Copy it from " +
          "https://fpdownload.macromedia.com/get/flashplayer/updaters/32/playerglobal32_0.swc"
}
$cfgText = Get-Content $tpl -Raw
$cfgText = $cfgText.Replace("@PLAYERGLOBAL@", $playerglobal)
$cfgText = $cfgText.Replace("@SRC@", (Join-Path $root "src"))
Set-Content -Path $cfg -Value $cfgText -Encoding UTF8

& (Join-Path $flex "bin\mxmlc.bat") -load-config="$cfg" -output="$out" "$src"
if ($LASTEXITCODE -ne 0) { throw "mxmlc failed with exit code $LASTEXITCODE" }
Write-Output "built: $out"
