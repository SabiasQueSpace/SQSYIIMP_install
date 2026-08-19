#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# This is the main import menu for Yiimpool
#
# Author: SabiasQue.Space
# Updated: 2025-02-16
#####################################################

source /etc/functions.sh
source /etc/yiimpoolversion.conf
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf


print_header "Database Import"
print_info "Creating database import sql file..."

# Format: YYYYMMDD for directory
dir_date=$(date +"%Y%m%d")
import_dir="$HOME/sqsyiimp/yiimp_upgrade/importdb"

print_info "What would you like to name your sql file?"
read -p "Enter the name of your sql file: " sql_file

# Format: YYYYMMDD_HHMMSS for SQL file
file_date=$(date +"%Y%m%d_%H%M%S")
import_file="${sql_file}_${file_date}.sql"


print_info "Setting up import file..."
echo

# Create directory if it doesn't exist
if [ ! -d "$import_dir" ]; then
    sudo mkdir -p "$import_dir"
    sudo chown -R $USER:$USER "$import_dir"
    sudo chmod 755 "$import_dir"
    print_success "Import directory created and permissions set"
    echo
else
    # Ensure proper permissions on existing directory
    sudo chown -R $USER:$USER "$import_dir"
    sudo chmod 755 "$import_dir"
    echo
fi

# Ensure we're in a directory we can write to
cd "$import_dir" || {
    print_error "Failed to change to import directory"
    exit 1
}

# Create and open the import file
if sudo touch "$import_file" && sudo chown $USER:$USER "$import_file" && sudo chmod 644 "$import_file"; then
    print_success "Created import file: $(basename "$import_file")"
    echo
    print_info "Opening editor to configure import settings..."
    print_info "Please add your SQL import commands to the file"
    echo
    read -p "Press Enter to continue..."

    sudo nano "$import_file"

else
    print_error "Failed to create import file. Please check permissions."
    exit 1
fi
print_success "Import file created: $import_file"
# Verify file is not empty
if [ ! -s "$import_file" ]; then
    print_warning "Import file is empty. Please make sure to add your SQL commands."
    exit 1
fi
clear
print_divider

print_info "Importing database tables..."
print_info "Import file location: $import_file"

if [ ! -f "$import_file" ]; then
    print_error "Import file not found: $import_file"
    exit 1
fi

print_info "File size: $(du -h "$import_file" | cut -f1)"

SQL_FILES=$import_file
print_success "FOUND IMPORT FILE $SQL_FILES"


print_info "Importing $SQL_FILES..."

for file in "${SQL_FILES[@]}"; do
    print_status "Importing $file..."
    if [[ "$file" == *.gz ]]; then
        print_info "Processing compressed file..."
        sudo zcat "$file" | sudo mariadb -u root -p"${DBRootPassword}" "${YiiMPDBName}" --force --binary-mode
    else
        print_info "Processing SQL file..."
        sudo mariadb -u root -p"${DBRootPassword}" "${YiiMPDBName}" --force < "$file"
    fi

    if [ $? -eq 0 ]; then
        print_success "Successfully imported: $(basename "$file")"
    else
        print_error "Failed to import: $(basename "$file")"
    fi
done

echo
print_success "Database import completed successfully"
echo
print_status "Do you want to keep the import file? (y/n)"
read -p "Enter your choice: " keep_file

if [[ "$keep_file" == "y" ]]; then
    print_success "Import file will be kept in $import_dir"
else
    print_success "Import file will be deleted"
    rm -f "$import_file"
fi
exit 0
