@echo off
rem Usage: generate_drift.bat [watch]
rem   watch  - Continuously watch for changes and regenerate
rem   (none) - One-time generation

if /i "%1"=="watch" (
    echo Watching for Drift changes... (Ctrl+C to stop)
    call dart run build_runner watch --delete-conflicting-outputs
) else (
    echo Generating Drift classes...
    call dart run build_runner build --delete-conflicting-outputs
)
