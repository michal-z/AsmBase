@echo off
set NAME=base
if exist %NAME%.exe del %NAME%.exe
fasm %NAME%.asm
if "%1" == "run" if exist %NAME%.exe %NAME%.exe
