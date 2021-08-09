function Import-Ini () {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$src
    )

    $ini = @{}

    # Create a default section if none exist.
    $section = 'NO_SECTION'
    $ini[$section] = @{}

    switch -regex ( $src ) {
        '^\[(.+)\]$' {
            $section = $matches[1].Trim()
            $ini[$section] = @{}
        }
        '^\s*([^#].+?)\s*=\s*(.*)' {
            $name, $value = $matches[1..2]
            # skip comments that start with semicolon:
            if (!($name.StartsWith(';'))) {
                $ini[$section][$name] = $value.Trim()
            }
        }
    }

    return $ini
}
