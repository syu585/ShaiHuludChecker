#!/bin/bash

# Merge AffectedPackages.txt into AffectedPackages2.txt
# Usage: ./merge_packages.sh

set -e

SOURCE_FILE="AffectedPackages.txt"
TARGET_FILE="AffectedPackages2.txt"
TEMP_FILE=$(mktemp)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Package List Merger${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if files exist
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}Error: $SOURCE_FILE not found${NC}"
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo -e "${RED}Error: $TARGET_FILE not found${NC}"
    exit 1
fi

# Extract package names from TARGET_FILE (CSV format)
echo -e "${BLUE}Reading existing packages from $TARGET_FILE...${NC}"
declare -A EXISTING_PACKAGES

line_num=0
while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    
    # Skip header line
    if [ $line_num -eq 1 ]; then
        continue
    fi
    
    # Skip empty lines and comments
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Extract package name (before comma)
    IFS=',' read -r package_name version_spec <<< "$line"
    
    # Trim whitespace
    package_name="${package_name#"${package_name%%[![:space:]]*}"}"
    package_name="${package_name%"${package_name##*[![:space:]]}"}"
    
    if [ -n "$package_name" ]; then
        EXISTING_PACKAGES["$package_name"]=1
    fi
done < "$TARGET_FILE"

echo -e "${GREEN}✓ Found ${#EXISTING_PACKAGES[@]} existing packages${NC}"
echo ""

# Process SOURCE_FILE and collect new packages
echo -e "${BLUE}Checking packages from $SOURCE_FILE...${NC}"
NEW_PACKAGES=()
SKIPPED_COUNT=0

while IFS= read -r package_name || [ -n "$package_name" ]; do
    # Skip empty lines and comments
    if [ -z "$package_name" ] || [[ "$package_name" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Trim whitespace
    package_name="${package_name#"${package_name%%[![:space:]]*}"}"
    package_name="${package_name%"${package_name##*[![:space:]]}"}"
    
    if [ -n "$package_name" ]; then
        # Check if package already exists
        if [ -z "${EXISTING_PACKAGES[$package_name]}" ]; then
            NEW_PACKAGES+=("$package_name")
            echo -e "${YELLOW}  + New: $package_name${NC}"
        else
            ((SKIPPED_COUNT++))
        fi
    fi
done < "$SOURCE_FILE"

echo ""
echo -e "${GREEN}✓ Found ${#NEW_PACKAGES[@]} new packages${NC}"
echo -e "${GREEN}✓ Skipped $SKIPPED_COUNT existing packages${NC}"
echo ""

# If there are new packages, append them
if [ ${#NEW_PACKAGES[@]} -gt 0 ]; then
    echo -e "${BLUE}Appending new packages to $TARGET_FILE...${NC}"
    
    for package_name in "${NEW_PACKAGES[@]}"; do
        # Append with no version (empty second column)
        echo "$package_name," >> "$TARGET_FILE"
    done
    
    echo -e "${GREEN}✓ Successfully added ${#NEW_PACKAGES[@]} packages${NC}"
else
    echo -e "${GREEN}✓ No new packages to add${NC}"
fi

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Merge Complete${NC}"
echo -e "${BLUE}================================================${NC}"

exit 0

