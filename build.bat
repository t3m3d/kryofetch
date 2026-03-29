@echo off
setlocal

set KCC=%~dp0kcc.exe
set GCC=gcc

echo [1/2] Compiling Krypton to C...
%KCC% run.k > out.c
if errorlevel 1 (
    echo ERROR: Krypton compilation failed.
    exit /b 1
)

echo [2/2] Compiling C to executable...
%GCC% out.c -o kryofetch.exe -lm -w -lsetupapi -ladvapi32
if errorlevel 1 (
    echo ERROR: C compilation failed.
    exit /b 1
)

echo Done! Run kryofetch.exe to see output.
