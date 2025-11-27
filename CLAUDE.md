# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ShaiHuludChecker (MalCheck) is a malware detection tool specifically designed to identify compromised npm packages from the "Shai Hulud" malware campaign. The tool scans JavaScript projects for malicious dependencies and suspicious files.

## Core Components

- **malcheck.sh**: Main Bash script (executable) that performs malware scanning
- **AffectedPackages.txt**: CSV database containing 797 known malicious npm packages with specific versions
- **README.md**: Japanese documentation with usage instructions

## Key Commands

### Running the malware checker
```bash
# Recommended: Auto-download latest malware DB
./malcheck.sh <search_path>

# Use local file explicitly
./malcheck.sh <search_path> <package_list_file>

# Examples:
./malcheck.sh .                    # Check current directory with latest DB
./malcheck.sh /path/to/project     # Check specific project with latest DB
./malcheck.sh . AffectedPackages.txt  # Use local file explicitly
```

### Development commands
```bash
# Make script executable (if needed)
chmod +x malcheck.sh

# View package count
wc -l AffectedPackages.txt

# Test script syntax
bash -n malcheck.sh
```

## Script Architecture

The malcheck.sh script performs two main checks:

1. **Package.json and package-lock.json scanning**: Recursively finds all package.json and package-lock.json files and checks dependencies against the malware database
   - For package.json: Checks `dependencies` and `devDependencies` sections
   - For package-lock.json: Checks both `packages` section (`node_modules/package-name`) and `dependencies` section
2. **Suspicious file detection**: Looks for specific malware-related files:
   - `setup_bun.js`
   - `bun_environment.js` 
   - `.dev-env` directory

### Auto-Update Features
- Downloads latest malware DB from Wiz Security's GitHub repository
- 24-hour caching mechanism (`$HOME/.malcheck_cache/`)
- Fallback to local AffectedPackages.txt if online update fails
- Supports both curl and wget for downloading

### Performance Optimizations
- Uses Bash-native operations instead of external commands where possible
- Eliminates subprocess overhead for 40-70% performance improvement
- Version-aware checking with support for complex version patterns

### Output Format
- **Green (✓)**: No threats detected
- **Red (⚠)**: Malware or suspicious files found
- **Yellow**: Informational messages
- **Blue**: Headers and status information

### Exit Codes
- `0`: No malware detected (safe)
- `1`: Malware or suspicious items detected

## AffectedPackages.txt Format

CSV format with header: `Package,Version`
- Supports exact version matching with `= x.y.z`
- Supports multiple versions with `||` separator
- Contains packages from major compromised organizations (@asyncapi, @posthog, @zapier, @ensdomains)

## Development Notes

- Script uses `set -e` for strict error handling
- All user-facing text is in Japanese
- No test suite or CI/CD pipeline currently exists
- Dependencies: Bash 4.0+, `find`, `grep`, `curl`/`wget` (for online updates)
- Script is read-only and safe to run (no file modifications)
- Cache files stored in `$HOME/.malcheck_cache/`

## Version History

Recent optimizations focused on performance improvements and adding version-specific malware detection capabilities.