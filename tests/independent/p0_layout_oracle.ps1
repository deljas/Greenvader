param(
    [Parameter(Mandatory = $true)][int]$ClientWidth,
    [Parameter(Mandatory = $true)][int]$ClientHeight
)

# Expectation comes from docs/02_TECH_AND_ART.md and docs/03_DEVELOPMENT_PLAN.md.
# This does not read project.godot or copy an implementation helper.
# It is an expectation generator, not evidence that the game passes.
$baseWidth = 640
$baseHeight = 360
if ($ClientWidth -lt $baseWidth -or $ClientHeight -lt $baseHeight) {
    throw 'Client size is below the specified minimum 640x360; resizing must be constrained.'
}
$integerScale = [int][Math]::Floor([Math]::Min($ClientWidth / $baseWidth, $ClientHeight / $baseHeight))
$contentWidth = $baseWidth * $integerScale
$contentHeight = $baseHeight * $integerScale
$remainingWidth = $ClientWidth - $contentWidth
$remainingHeight = $ClientHeight - $contentHeight
[pscustomobject]@{
    ClientWidth = $ClientWidth
    ClientHeight = $ClientHeight
    IntegerScale = $integerScale
    ContentWidth = $contentWidth
    ContentHeight = $contentHeight
    LeftMargin = [int][Math]::Floor($remainingWidth / 2)
    RightMargin = [int][Math]::Ceiling($remainingWidth / 2)
    TopMargin = [int][Math]::Floor($remainingHeight / 2)
    BottomMargin = [int][Math]::Ceiling($remainingHeight / 2)
}
