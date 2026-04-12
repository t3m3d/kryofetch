@echo off
setlocal

echo [1/2] Krypton to C...
..\krypton\kcc.exe --headers ..\krypton\headers run.k > kryofetch_tmp.c
if errorlevel 1 (
    echo ERROR: Krypton compilation failed.
    del /Q kryofetch_tmp.c 2>nul
    exit /b 1
)

echo [2/2] C to exe...
gcc kryofetch_tmp.c -o kryofetch.exe -lsetupapi -ladvapi32 -lpdh -lm -w
if errorlevel 1 (
    echo ERROR: gcc failed.
    del /Q kryofetch_tmp.c 2>nul
    exit /b 1
)
del /Q kryofetch_tmp.c

echo Done! Run kryofetch.exe to see output.
