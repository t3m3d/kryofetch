@echo off
setlocal

set KRYPTON=..\krypton
set KCC=%KRYPTON%\kcc.exe
set OPT=%KRYPTON%\compiler\windows_x86\optimize_host.exe
set X64=%KRYPTON%\compiler\windows_x86\x64_host.exe
set RT=%KRYPTON%\runtime\krypton_rt.dll
set IR=_kf_build.kir
set IRO=_kf_build_opt.kir

echo Building kryofetch (native PE/COFF, no gcc)...

if not exist "%KCC%"  ( echo ERROR: %KCC% not found  & exit /b 1 )
if not exist "%OPT%"  ( echo ERROR: %OPT% not found  & exit /b 1 )
if not exist "%X64%"  ( echo ERROR: %X64% not found  & exit /b 1 )

echo [1/3] Krypton to IR...
"%KCC%" --ir run.k > %IR%
if errorlevel 1 ( echo ERROR: IR emission failed & del /Q %IR% 2>nul & exit /b 1 )

echo [2/3] Optimizing IR...
"%OPT%" %IR% > %IRO%
if errorlevel 1 ( echo ERROR: optimizer failed & del /Q %IR% %IRO% 2>nul & exit /b 1 )

echo [3/3] IR to PE/COFF...
"%X64%" %IRO% kryofetch.exe
if errorlevel 1 ( echo ERROR: x64 codegen failed & del /Q %IR% %IRO% 2>nul & exit /b 1 )

del /Q %IR% %IRO% 2>nul

if exist "%RT%" copy /Y "%RT%" krypton_rt.dll >nul

echo Done! Run kryofetch.exe to see output.
echo (krypton_rt.dll bundled alongside.)
