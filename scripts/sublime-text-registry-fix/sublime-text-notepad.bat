for /f "tokens=1,* delims= " %%a in ("%*") do set ARGUEMENTS=%%b
"$sublime" -n "%ARGUEMENTS%"
